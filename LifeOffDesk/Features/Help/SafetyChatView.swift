import LifeOffDeskCore
import PhotosUI
import SwiftUI

/// Offline help assistant in the SOS sheet. Ask in Taglish or English (typed or spoken); the
/// on-device model only routes the question to a bundled card summarised from a public source.
/// It never writes advice itself, and life-threatening words always show "Call 911" first.
@MainActor
final class SafetyChat: ObservableObject {
    struct Message: Identifiable, Equatable {
        enum Kind: Equatable {
            case question(String, photo: UIImage?)
            /// Plain assistant line (e.g. "Saan mo gustong pumunta?").
            case say(String)
            /// Where you are now, to read out or text.
            case location(String)
            /// Offline map places matching a name, each with a Route button.
            case places([Place], query: String)
            /// Bundled hotlines (official sources), each number tap-to-call.
            case hotlines([Hotline], title: String)
            /// `seen`: what Apple's on-device image recognition named in the photo, if any.
            /// `suggestions`: offered when no card matched, instead of a dead end.
            case answer(SafetyCard?, emergency: Bool, routedByAI: Bool, seen: [String], photoUnclear: Bool = false,
                        continued: Bool = false, suggestions: [SafetyCard] = [], highlights: [String] = [],
                        alternatives: [SafetyCard] = [], hotlines: [Hotline] = [])
        }
        let id = UUID()
        let kind: Kind
    }

    @Published var messages: [Message] = []
    @Published var thinking = false
    /// Last question asked, so a short follow-up ("paano na?") continues it.
    private var lastQuestion: String?
    /// After the "lost" card the next message is treated as where the user wants to go.
    private var awaitingDestination = false
    let guide: SafetyGuide?
    let loadProblem: String?
    let hotlines: HotlineDirectory?

    init() {
        // Routing terms (Taglish/Tagalog/English); without them the model alone routes.
        if SafetyKeywords.lexicon == nil,
           let url = Bundle.main.url(forResource: "safety-lexicon", withExtension: "json", subdirectory: "StarterData") {
            SafetyKeywords.lexicon = try? SafetyLexicon.decode(Data(contentsOf: url))
        }
        hotlines = Bundle.main.url(forResource: "hotlines", withExtension: "json", subdirectory: "StarterData")
            .flatMap { try? HotlineDirectory.decode(Data(contentsOf: $0)) }
        if let url = Bundle.main.url(forResource: "safety-guide", withExtension: "json", subdirectory: "StarterData") {
            do {
                guide = try SafetyGuide.decode(Data(contentsOf: url)); loadProblem = nil
            } catch {
                guide = nil; loadProblem = "Help cards could not be read: \(error.localizedDescription)"
            }
        } else {
            guide = nil; loadProblem = "Help cards are not bundled in this build."
        }
    }

    func ask(_ question: String, photo: UIImage? = nil, model: AppModel) {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || photo != nil, !thinking else { return }
        messages.append(Message(kind: .question(text.isEmpty ? "(photo)" : text, photo: photo)))
        // Lost flow: "Starbucks" / "may nakita akong Starbucks" searches the offline map.
        if awaitingDestination, photo == nil, !SafetyKeywords.emergency(in: text) {
            let topic = SafetyKeywords.topic(in: text)
            if topic == nil || topic == .lost {
                searchDestination(text, model: model)
                return
            }
        }
        awaitingDestination = false
        // "nearest hospital" / "pinakamalapit na pulis": nearest places from the offline map (lookup,
        // never a card and never a follow-up of the previous question). Emergencies keep the 911 path.
        let placeKinds = NearestHelpRequest.kinds(in: text)
        if photo == nil, !placeKinds.isEmpty, hotlines?.isAsking(text) != true, !SafetyKeywords.emergency(in: text),
           SafetyKeywords.topic(in: text) == nil {
            lastQuestion = nil
            showNearestHelp(placeKinds, query: text, model: model, sayWhenNone: true)
            return
        }
        // "Ano ang number ng highway patrol / NLEX / Makati rescue?": a lookup in the bundled
        // directory, never the model. Emergencies still go through the card path (911 first).
        if photo == nil, let directory = hotlines, directory.isAsking(text), !SafetyKeywords.emergency(in: text),
           SafetyKeywords.topic(in: text) == nil {
            let found = directory.answer(for: text, regionID: model.regionIDHere)
            messages.append(Message(kind: .hotlines(found, title: directory.named(in: text).isEmpty
                ? "Emergency hotlines (offline copy)" : "Hotlines na nahanap")))
            showNearestHelp(NearestHelpRequest.kinds(in: text), query: text, model: model, sayWhenNone: false)
            lastQuestion = nil
            return
        }
        let ai = model.ai
        thinking = true
        let followUp = SafetyPrompt.followUp(text, previous: lastQuestion)
        let routedText = followUp ?? text
        Task {
            // Apple's on-device image recognition names what is in the photo; generic labels
            // ("structure", "wood") are dropped. The model reads the rest as context only.
            var all: [String] = []
            if let photo { all = await PhotoClassifier.labels(for: photo) }
            let labels = PhotoHints.useful(all)
            var routed: SafetyAnswer?
            if let result = try? await ai.run({ await SafetyPrompt.classify(routedText, photoLabels: labels, engine: $0) }),
               case let .valid(answer) = result.0 {
                routed = answer
            }
            let final = SafetyPrompt.combine(model: routed, question: routedText, photoLabels: labels)
            let card = final.topic.flatMap { guide?.card($0) }
            let suggestions = card == nil ? SafetyKeywords.suggestions(for: routedText).compactMap { guide?.card($0) } : []
            // Point at the card steps that answer the question ("buhusan ng tubig?" -> the water steps).
            let highlights = card.flatMap { c in SafetyKeywords.lexicon?.relevantSteps(in: c, for: text) } ?? []
            // A wrong route (model mistake or a steering message) is one tap from the right card.
            let alternatives = SafetyPrompt.alternatives(model: routed, question: routedText, shown: card?.topic)
                .compactMap { guide?.card($0) }
            // Emergencies: your city's rescue line and other national lines after the 911 button.
            let localLines = final.emergency ? (hotlines?.forEmergency(regionID: model.regionIDHere) ?? []) : []
            messages.append(Message(kind: .answer(card, emergency: final.emergency, routedByAI: routed != nil, seen: labels,
                                                  photoUnclear: photo != nil && labels.isEmpty, continued: followUp != nil,
                                                  suggestions: suggestions, highlights: highlights,
                                                  alternatives: alternatives, hotlines: localLines)))
            if !text.isEmpty { lastQuestion = routedText }
            if card?.topic == .lost { startLostFlow(model: model) }
            thinking = false
        }
    }

    func show(_ topic: SafetyTopic, model: AppModel) {
        messages.append(Message(kind: .answer(guide?.card(topic), emergency: false, routedByAI: false, seen: [])))
        lastQuestion = nil
        if topic == .lost { startLostFlow(model: model) } else { awaitingDestination = false }
    }

    /// "Nearest police / hospital / fire station": the closest ones in the loaded offline map.
    private func showNearestHelp(_ kinds: [HelpKind], query: String, model: AppModel, sayWhenNone: Bool) {
        guard !kinds.isEmpty else { return }
        thinking = true
        Task {
            let snapshot = await model.nearbyHelp()
            let places = kinds.flatMap { (snapshot.places[$0] ?? []).prefix(3).map(\.place) }
            if !places.isEmpty {
                messages.append(Message(kind: .places(places, query: query)))
            } else if sayWhenNone {
                messages.append(Message(kind: .say(snapshot.position == nil
                    ? "Wala pang GPS fix, kaya hindi ko mahanap ang pinakamalapit. Kung emergency, tumawag sa 911."
                    : "Walang ganyang lugar sa offline map na malapit sa iyo. Kung emergency, tumawag sa 911.")))
            }
            thinking = false
        }
    }

    /// Lost: say where the user is (offline GPS + nearest named place), then ask where to go.
    private func startLostFlow(model: AppModel) {
        model.refreshIdleLocation()
        if let position = model.currentPosition, let catalog = model.content?.catalog {
            messages.append(Message(kind: .location(HelpPlaces.locationDescription(
                position, accuracyMeters: model.lastFix?.horizontalAccuracy, catalog: catalog))))
        } else {
            messages.append(Message(kind: .say("Wala pang GPS fix. Pumunta sa bukas na lugar, malayo sa matataas na gusali, at subukan ulit.")))
        }
        messages.append(Message(kind: .say("Saan mo gustong pumunta? I-type ang lugar o landmark na nakikita mo (hal. Starbucks, Greenbelt, MRT).")))
        awaitingDestination = true
    }

    private func searchDestination(_ text: String, model: AppModel) {
        guard let catalog = model.content?.catalog else {
            messages.append(Message(kind: .say("Hindi pa naka-load ang offline map. Subukan ulit maya-maya.")))
            return
        }
        let found = PlaceNameSearch.find(text, in: catalog, from: model.currentPosition)
        if found.isEmpty {
            messages.append(Message(kind: .say("Wala akong nakitang ganyang lugar sa offline map na naka-load ngayon. Subukan ang ibang pangalan o landmark.")))
        } else {
            messages.append(Message(kind: .places(found, query: text)))
        }
    }
}

struct SafetyChatView: View {
    @EnvironmentObject private var model: AppModel
    /// Screenshot helper (simulator only): questions asked on appear.
    var initialQuestion: String?
    /// Closes the whole help sheet after "Route" so the map shows the route.
    var onRoute: () -> Void = {}
    @StateObject private var chat = SafetyChat()
    @StateObject private var speech = SpeechInput()
    @State private var text = ""
    @State private var photo: UIImage?
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false

    private let quickTopics: [(String, SafetyTopic)] = [
        ("Sugat / dugo", .bleeding), ("Natapilok", .sprain), ("Sobrang init", .heat), ("Nahimatay", .fainting),
        ("Kagat ng aso", .animalBite), ("Baha", .flood), ("Flat na gulong", .flatTire), ("Tumirik", .breakdown),
        ("Overheat", .overheating), ("Lowbat", .phoneBattery), ("Naligaw", .lost),
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        intro
                        ForEach(chat.messages) { message in bubble(message).id(message.id) }
                        if chat.thinking {
                            HStack(spacing: 8) { ProgressView(); Text("Hinahanap ang tamang gabay…").font(.footnote) }
                                .foregroundStyle(Theme.secondaryInk)
                        }
                    }
                    .padding(Theme.inset)
                }
                .onChange(of: chat.messages.count) { _, _ in
                    if let last = chat.messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .top) } }
                }
            }
            inputBar
        }
        .background(Theme.canvas)
        .navigationTitle("Help assistant")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: speech.transcript) { _, value in if speech.state == .listening { text = value } }
        .onDisappear { speech.cancel() }
        .task {
            guard let initialQuestion, chat.messages.isEmpty else { return }
            try? await Task.sleep(nanoseconds: 600_000_000)
            chat.ask(initialQuestion, model: model)
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Itanong sa Taglish o English: first aid, init, baha, kagat ng aso, naligaw, lowbat… Offline ito.")
                .font(.subheadline).foregroundStyle(Theme.ink)
            Text("Answers are reviewed cards summarised from public health and safety sources (linked). The on-device AI only picks the card; it does not write medical advice. In an emergency, call 911 first.")
                .font(.caption).foregroundStyle(Theme.secondaryInk)
            if let problem = chat.loadProblem { Text(problem).font(.caption).foregroundStyle(Theme.danger) }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(quickTopics.indices, id: \.self) { index in
                        Button(quickTopics[index].0) { chat.show(quickTopics[index].1, model: model) }
                            .font(.footnote.weight(.semibold)).foregroundStyle(Theme.ink)
                            .padding(.horizontal, 12).frame(minHeight: 36)
                            .background(Theme.surface, in: Capsule()).overlay(Capsule().stroke(Theme.border))
                    }
                }
            }
        }
    }

    /// Tap-to-call rows; every number shows its source so it can be checked.
    @ViewBuilder private func hotlineRows(_ lines: [Hotline]) -> some View {
        ForEach(lines) { line in
            VStack(alignment: .leading, spacing: 4) {
                Text(line.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                HStack(spacing: 8) {
                    ForEach(line.numbers, id: \.self) { number in
                        if let url = URL(string: "tel:\(Hotline.dialable(number))") {
                            Link(destination: url) {
                                Label(number, systemImage: "phone.fill").font(.footnote.bold())
                                    .padding(.horizontal, 10).frame(minHeight: Theme.minTarget)
                                    .background(Theme.revealedGround, in: Capsule()).foregroundStyle(Theme.primary)
                            }
                            .accessibilityLabel("Call \(line.name), \(number)")
                        }
                    }
                }
                if let url = URL(string: line.sourceURL) {
                    Link("Source: \(line.sourceName)\(line.confidence == "secondary" ? " (news report)" : "") · checked \(line.retrieved)", destination: url)
                        .font(.caption2).foregroundStyle(Theme.secondaryInk)
                }
            }
        }
        Text("Offline copy; numbers can change. 911 works nationwide.").font(.caption2).foregroundStyle(Theme.secondaryInk)
    }

    @ViewBuilder private func bubble(_ message: SafetyChat.Message) -> some View {
        switch message.kind {
        case let .question(q, photo):
            HStack { Spacer(minLength: 40)
                VStack(alignment: .trailing, spacing: 6) {
                    if let photo {
                        Image(uiImage: photo).resizable().scaledToFill().frame(width: 140, height: 140)
                            .clipShape(RoundedRectangle(cornerRadius: 14)).accessibilityLabel("Attached photo")
                    }
                    Text(q).font(.subheadline).foregroundStyle(Theme.canvas)
                        .padding(12).background(Theme.primary, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        case let .say(line):
            Text(line).font(.subheadline).foregroundStyle(Theme.ink)
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
        case let .location(line):
            VStack(alignment: .leading, spacing: 8) {
                Label("Nasaan ka ngayon (offline GPS)", systemImage: "location.fill").font(.footnote.bold()).foregroundStyle(Theme.ink)
                Text(line).font(.subheadline.monospacedDigit()).foregroundStyle(Theme.ink).textSelection(.enabled)
                HStack(spacing: 10) {
                    Button("Copy") { UIPasteboard.general.string = line }.buttonStyle(.bordered)
                    ShareLink("Text it", item: "My location: \(line)").buttonStyle(.bordered)
                }
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
        case let .places(places, _):
            VStack(alignment: .leading, spacing: 8) {
                Text("Nakita sa offline map:").font(.footnote.bold()).foregroundStyle(Theme.ink)
                ForEach(places) { place in
                    HStack(spacing: 10) {
                        Image(systemName: PlaceIcon.symbol(place)).foregroundStyle(Theme.canvas)
                            .frame(width: 32, height: 32).background(PlaceIcon.tint(place), in: Circle())
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(place.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                            if let here = model.currentPosition {
                                Text("\(Format.distance(Geo.distanceMeters(here, place.coordinate))) straight-line")
                                    .font(.caption).foregroundStyle(Theme.secondaryInk)
                            }
                        }
                        Spacer()
                        Button("Route") {
                            model.choose(place)
                            onRoute()
                        }
                        .buttonStyle(.borderedProminent).tint(Theme.primary)
                        .accessibilityLabel("Show route to \(place.name)")
                    }
                }
                Text("OpenStreetMap · route follows mapped streets").font(.caption2).foregroundStyle(Theme.secondaryInk)
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
        case let .hotlines(lines, title):
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.footnote.bold()).foregroundStyle(Theme.ink)
                hotlineRows(lines)
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
        case let .answer(card, emergency, routedByAI, seen, photoUnclear, continued, suggestions, highlights, alternatives, hotlines):
            VStack(alignment: .leading, spacing: 10) {
                if continued {
                    Label("Tuloy sa huling tanong mo", systemImage: "arrow.turn.down.right")
                        .font(.caption).foregroundStyle(Theme.secondaryInk)
                }
                if photoUnclear {
                    Label("Hindi malinaw kung ano ang nasa photo; sinunod ko ang tanong mo.", systemImage: "eye.slash")
                        .font(.caption).foregroundStyle(Theme.secondaryInk)
                }
                if !seen.isEmpty {
                    Label("Nakikita sa photo: \(PhotoHints.describe(seen))", systemImage: "eye")
                        .font(.caption).foregroundStyle(Theme.secondaryInk)
                    Text("Apple on-device image recognition names objects only; hindi nito masasabi kung sira, sugatan o ligtas kainin.")
                        .font(.caption2).foregroundStyle(Theme.secondaryInk)
                }
                if emergency {
                    Link(destination: URL(string: "tel:911")!) {
                        Label("Mukhang emergency ito. Call 911 now", systemImage: "phone.fill")
                            .font(.subheadline.bold()).foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(Theme.danger, in: RoundedRectangle(cornerRadius: 12))
                    }
                    if !hotlines.isEmpty {
                        Text("Iba pang matatawagan:").font(.footnote.bold()).foregroundStyle(Theme.ink)
                        hotlineRows(hotlines)
                    }
                }
                if let card {
                    if !highlights.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Sagot sa tanong mo (mula sa card):", systemImage: "text.quote")
                                .font(.footnote.bold()).foregroundStyle(Theme.primary)
                            ForEach(highlights, id: \.self) { Text("“\($0)”").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink) }
                            Text("Walang iba pang sinasabi ang source tungkol dito. Kung hindi sigurado, maghintay at humingi ng tulong.")
                                .font(.caption2).foregroundStyle(Theme.secondaryInk)
                        }
                        .padding(10)
                        .background(Theme.revealedGround, in: RoundedRectangle(cornerRadius: 12))
                    }
                    Text(card.title).font(.headline).foregroundStyle(Theme.ink)
                    ForEach(Array(card.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(index + 1).").font(.subheadline.bold()).foregroundStyle(Theme.primary)
                            Text(step).font(.subheadline).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if !card.callNow.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(card.topic.isVehicle ? "Safety warnings:" : "Call 911 if:").font(.footnote.bold()).foregroundStyle(Theme.danger)
                            ForEach(card.callNow, id: \.self) { Text("• " + $0).font(.footnote).foregroundStyle(Theme.ink) }
                        }
                    }
                    if let url = URL(string: card.sourceURL) {
                        Link("Source: \(card.sourceTitle)", destination: url).font(.caption).foregroundStyle(Theme.primary)
                    }
                    if !alternatives.isEmpty {
                        Text("Hindi ito ang tanong mo? Subukan:").font(.footnote.bold()).foregroundStyle(Theme.ink)
                        ForEach(alternatives) { other in
                            Button { chat.show(other.topic, model: model) } label: {
                                Label(other.title, systemImage: "arrow.right.circle")
                                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.primary)
                                    .frame(minHeight: Theme.minTarget)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else {
                    Text("Wala akong reviewed na gabay para diyan. Kung delikado o may nasaktan, tumawag sa 911.")
                        .font(.subheadline).foregroundStyle(Theme.ink)
                    if !suggestions.isEmpty {
                        Text("Baka ito ang hinahanap mo:").font(.footnote.bold()).foregroundStyle(Theme.ink)
                        ForEach(suggestions) { suggestion in
                            Button { chat.show(suggestion.topic, model: model) } label: {
                                Label(suggestion.title, systemImage: "arrow.right.circle")
                                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.primary)
                                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Text(card == nil
                     ? (routedByAI ? "On-device AI found no matching card" : "No matching card (keywords)")
                     : (routedByAI ? "On-device AI chose this card · text from the linked source"
                                   : "Matched by keywords (no AI) · text from the linked source"))
                    .font(.caption2).foregroundStyle(Theme.secondaryInk)
            }
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(emergency ? Theme.danger : Theme.border))
        }
    }

    private var inputBar: some View {
        VStack(spacing: 6) {
            if let photo {
                HStack {
                    Image(uiImage: photo).resizable().scaledToFill().frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    Text("Photo attached").font(.caption).foregroundStyle(Theme.secondaryInk)
                    Spacer()
                    Button { self.photo = nil } label: { Image(systemName: "xmark.circle.fill") }
                        .foregroundStyle(Theme.secondaryInk).accessibilityLabel("Remove photo")
                }
                .padding(.horizontal, 12).padding(.top, 6)
            }
        HStack(spacing: 8) {
            Menu {
                Button("Take photo", systemImage: "camera") { showCamera = true }
                PhotosPicker(selection: $photoItem, matching: .images) { Label("Choose photo", systemImage: "photo") }
            } label: {
                Image(systemName: "camera.fill").foregroundStyle(Theme.primary)
                    .frame(width: 36, height: 36).background(Theme.revealedGround, in: Circle())
            }
            .frame(width: Theme.minTarget, height: Theme.minTarget)
            .accessibilityLabel("Attach a photo")
            TextField("Ano ang nangyari?", text: $text, axis: .vertical)
                .lineLimit(1...3).submitLabel(.send).onSubmit(send)
                .padding(.vertical, 10).padding(.leading, 12)
            Button {
                if speech.state == .listening { speech.stop() } else { speech.start { text = $0; send() } }
            } label: {
                Image(systemName: speech.state == .listening ? "waveform" : "mic.fill")
                    .foregroundStyle(speech.state == .listening ? Theme.canvas : Theme.primary)
                    .frame(width: 36, height: 36)
                    .background(speech.state == .listening ? Theme.danger : Theme.revealedGround, in: Circle())
            }
            .frame(width: Theme.minTarget, height: Theme.minTarget)
            .accessibilityLabel(speech.state == .listening ? "Stop and send" : "Speak your question")
            Button(action: send) {
                Image(systemName: "arrow.up").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.canvas)
                    .frame(width: 36, height: 36).background(Theme.primary, in: Circle())
            }
            .frame(width: Theme.minTarget, height: Theme.minTarget)
            .disabled((text.trimmingCharacters(in: .whitespaces).isEmpty && photo == nil) || chat.thinking)
            .accessibilityLabel("Ask")
        }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(Theme.surface)
        .overlay(alignment: .top) { Divider() }
        .fullScreenCover(isPresented: $showCamera) { CameraPicker { photo = $0 }.ignoresSafeArea() }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) { photo = image }
                photoItem = nil
            }
        }
    }

    private func send() {
        chat.ask(text, photo: photo, model: model)
        text = ""
        photo = nil
    }
}
