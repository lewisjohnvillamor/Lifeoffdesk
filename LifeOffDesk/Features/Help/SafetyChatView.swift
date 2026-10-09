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
            /// `seen`: what Apple's on-device image recognition named in the photo, if any.
            case answer(SafetyCard?, emergency: Bool, routedByAI: Bool, seen: [String])
        }
        let id = UUID()
        let kind: Kind
    }

    @Published var messages: [Message] = []
    @Published var thinking = false
    let guide: SafetyGuide?
    let loadProblem: String?

    init() {
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

    func ask(_ question: String, photo: UIImage? = nil, ai: AIService) {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || photo != nil, !thinking else { return }
        messages.append(Message(kind: .question(text.isEmpty ? "(photo)" : text, photo: photo)))
        thinking = true
        Task {
            // Apple's on-device image recognition names what is in the photo; the model reads those
            // names as context. Nothing is diagnosed from the image.
            var labels: [String] = []
            if let photo { labels = await PhotoClassifier.labels(for: photo) }
            var routed: SafetyAnswer?
            if let result = try? await ai.run({ await SafetyPrompt.classify(text, photoLabels: labels, engine: $0) }),
               case let .valid(answer) = result.0 {
                routed = answer
            }
            let final = SafetyPrompt.combine(model: routed, question: text, photoLabels: labels)
            messages.append(Message(kind: .answer(final.topic.flatMap { guide?.card($0) }, emergency: final.emergency,
                                                  routedByAI: routed != nil, seen: labels)))
            thinking = false
        }
    }

    func show(_ topic: SafetyTopic) {
        messages.append(Message(kind: .answer(guide?.card(topic), emergency: false, routedByAI: false, seen: [])))
    }
}

struct SafetyChatView: View {
    @EnvironmentObject private var model: AppModel
    /// Screenshot helper (simulator only): questions asked on appear.
    var initialQuestion: String?
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
            chat.ask(initialQuestion, ai: model.ai)
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
                        Button(quickTopics[index].0) { chat.show(quickTopics[index].1) }
                            .font(.footnote.weight(.semibold)).foregroundStyle(Theme.ink)
                            .padding(.horizontal, 12).frame(minHeight: 36)
                            .background(Theme.surface, in: Capsule()).overlay(Capsule().stroke(Theme.border))
                    }
                }
            }
        }
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
        case let .answer(card, emergency, routedByAI, seen):
            VStack(alignment: .leading, spacing: 10) {
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
                }
                if let card {
                    Text(card.title).font(.headline).foregroundStyle(Theme.ink)
                    ForEach(Array(card.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(index + 1).").font(.subheadline.bold()).foregroundStyle(Theme.primary)
                            Text(step).font(.subheadline).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if !card.callNow.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Call 911 if:").font(.footnote.bold()).foregroundStyle(Theme.danger)
                            ForEach(card.callNow, id: \.self) { Text("• " + $0).font(.footnote).foregroundStyle(Theme.ink) }
                        }
                    }
                    if let url = URL(string: card.sourceURL) {
                        Link("Source: \(card.sourceTitle)", destination: url).font(.caption).foregroundStyle(Theme.primary)
                    }
                } else {
                    Text("Wala akong reviewed na gabay para diyan. Kung delikado o may nasaktan, tumawag sa 911. Puwede mo ring subukan ang ibang salita o pumili sa mga button sa itaas.")
                        .font(.subheadline).foregroundStyle(Theme.ink)
                }
                Text(routedByAI ? "On-device AI chose this card · text from the linked source" : "Matched by keywords (no AI) · text from the linked source")
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
        chat.ask(text, photo: photo, ai: model.ai)
        text = ""
        photo = nil
    }
}
