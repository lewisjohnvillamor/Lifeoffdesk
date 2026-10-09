import LifeOffDeskCore
import SwiftUI

/// Adventures tab: this week at a glance, calendar, the timelapse, and every adventure by month.
struct WalksView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selected: WalkSession?
    @State private var month = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
    @State private var selectedDay: Date?
    @State private var searchText = ""

    private var calendar: Calendar { Calendar.current }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if model.demoMode {
                        Label("Sample adventures · not real GPS", systemImage: "sparkles")
                            .font(.footnote.weight(.semibold)).foregroundStyle(Theme.danger)
                    }
                    searchCard
                    if model.historyQuery != nil || model.historyState != .idle {
                        searchResults
                    }
                    weekCard
                    Button {
                        model.selectedTab = .map
                        model.startTimelapse()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "play.fill").font(.system(size: 15, weight: .semibold))
                                .frame(width: 44, height: 44).background(PaperStyle.paper, in: Circle())
                            Text("Watch your world grow").font(.headline)
                            Spacer()
                        }
                        .foregroundStyle(PaperStyle.ink)
                        .padding(14)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.border))
                    }
                    .buttonStyle(.plain)
                    .disabled(model.historyWalks.isEmpty || model.activeSession != nil)
                    calendarCard
                    months
                }
                .padding(Theme.inset)
            }
            .background(PaperStyle.island)
            .navigationTitle("Adventures")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $selected) { RecapView(session: $0).environmentObject(model) }
        }
    }

    // MARK: Search (P0-12: on-device AI turns the question into filters; app code searches)

    private var searchCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "sparkle.magnifyingglass").foregroundStyle(Theme.secondaryInk).accessibilityHidden(true)
                TextField("Hanapin: \"short walks last week na may photos\"", text: $searchText)
                    .submitLabel(.search)
                    .onSubmit { model.searchHistory(searchText) }
                    .disabled(!model.historySearchAvailable)
                if model.historyState == .searching {
                    ProgressView()
                } else if !searchText.isEmpty || model.historyQuery != nil {
                    Button {
                        searchText = ""
                        model.clearHistorySearch()
                    } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.secondaryInk) }
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(12)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.border))
            if model.demoMode {
                Text("Search covers your own saved adventures, not sample data.")
                    .font(.caption).foregroundStyle(Theme.secondaryInk)
            } else if model.finishedWalks.isEmpty {
                Text("No saved adventures yet.").font(.caption).foregroundStyle(Theme.secondaryInk)
            }
        }
    }

    private var searchResults: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let query = model.historyQuery {
                let chips = HistoryCopy.chips(query)
                if !chips.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(chips) { chip in
                                Button { model.applyHistoryQuery(HistoryCopy.removing(chip.id, from: query)) } label: {
                                    HStack(spacing: 4) {
                                        Text(chip.label)
                                        Image(systemName: "xmark").font(.caption2.bold())
                                    }
                                    .font(.footnote.weight(.semibold))
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(PaperStyle.paper, in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove filter \(chip.label)")
                            }
                        }
                    }
                }
                if query.categories.isEmpty == false {
                    Text("“Dumaan malapit” = within 40 m of your trail; not proof you went inside.")
                        .font(.caption).foregroundStyle(Theme.secondaryInk)
                }
            }
            switch model.historyState {
            case .idle, .searching: EmptyView()
            case let .clarify(question):
                Text(question).font(.subheadline).foregroundStyle(Theme.ink)
            case let .failed(message):
                Text(message).font(.footnote).foregroundStyle(Theme.danger)
            case let .results(ids):
                let walks = ids.compactMap { id in model.finishedWalks.first { $0.id == id } }
                Text(walks.isEmpty ? "Walang tugma. Subukang alisin ang isang filter." : "\(walks.count) adventure\(walks.count == 1 ? "" : "s")")
                    .font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondaryInk)
                ForEach(walks) { walk in
                    Button { selected = walk } label: { row(walk) }.buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    // MARK: This week

    private var weekCard: some View {
        let start = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? calendar.startOfDay(for: Date())
        let end = start.addingTimeInterval(7 * 86_400)
        let lastStart = start.addingTimeInterval(-7 * 86_400)
        let thisWeek = model.stats.recaps(in: model.historyWalks, from: start, to: end)
        let lastWeek = model.stats.recaps(in: model.historyWalks, from: lastStart, to: start)
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("This week").font(.headline)
                Spacer()
                Text("\(start.formatted(.dateTime.month(.defaultDigits).day())) – \(end.addingTimeInterval(-1).formatted(.dateTime.month(.defaultDigits).day()))")
                    .font(.footnote).foregroundStyle(Theme.secondaryInk)
            }
            HStack(spacing: 0) {
                weekStat("\(thisWeek.count)", "Adventures", last: "\(lastWeek.count)")
                Divider().frame(height: 44)
                weekStat(Self.km(thisWeek.reduce(0) { $0 + $1.newDistanceMeters }), "New streets",
                         last: Self.km(lastWeek.reduce(0) { $0 + $1.newDistanceMeters }))
                Divider().frame(height: 44)
                weekStat("\(placesFound(from: start, to: end))", "Places found",
                         last: "\(placesFound(from: lastStart, to: start))")
            }
            HStack {
                ForEach(0..<7, id: \.self) { offset in
                    let day = start.addingTimeInterval(Double(offset) * 86_400)
                    let walked = model.historyWalks.contains { calendar.isDate($0.startedAt, inSameDayAs: day) }
                    let isToday = calendar.isDateInToday(day)
                    VStack(spacing: 8) {
                        Text(day.formatted(.dateTime.weekday(.narrow))).font(.caption).foregroundStyle(Theme.secondaryInk)
                        ZStack {
                            Circle().fill(walked ? PaperStyle.ink : Theme.border).frame(width: 12, height: 12)
                            if isToday { Circle().stroke(PaperStyle.ink, lineWidth: 2).frame(width: 22, height: 22) }
                        }
                        .frame(height: 24)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement()
                    .accessibilityLabel("\(day.formatted(.dateTime.weekday(.wide))): \(walked ? "adventure" : "none")")
                }
            }
        }
        .foregroundStyle(PaperStyle.ink)
        .padding(18)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.border))
    }

    /// Distinct places passed by adventures that started in [start, end).
    private func placesFound(from start: Date, to end: Date) -> Int {
        Set(model.historyWalks.filter { $0.startedAt >= start && $0.startedAt < end }
            .flatMap { model.discoveries[$0.id] ?? [] }.map(\.id)).count
    }

    private func weekStat(_ value: String, _ title: String, last: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.weight(.bold).monospacedDigit())
            Text(title).font(.caption).foregroundStyle(Theme.secondaryInk)
            Text("Last week \(last)").font(.caption2).foregroundStyle(Theme.secondaryInk)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: Calendar

    private var calendarCard: some View {
        let days = monthDays(month)
        let walksByDay = Dictionary(grouping: model.historyWalks) { calendar.startOfDay(for: $0.startedAt) }
        return VStack(spacing: 12) {
            HStack {
                Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                    .accessibilityLabel("Previous month")
                Spacer()
                Text(month.formatted(.dateTime.month(.wide).year())).font(.headline)
                Spacer()
                Button { shiftMonth(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                    .accessibilityLabel("Next month")
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
                ForEach(Array(calendar.veryShortWeekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol).font(.caption2).foregroundStyle(Theme.secondaryInk)
                }
                ForEach(days.indices, id: \.self) { index in
                    if let day = days[index] {
                        let count = walksByDay[day]?.count ?? 0
                        let isSelected = selectedDay.map { calendar.isDate($0, inSameDayAs: day) } ?? false
                        Button {
                            selectedDay = isSelected ? nil : day
                        } label: {
                            VStack(spacing: 2) {
                                Text("\(calendar.component(.day, from: day))")
                                    .font(.subheadline.weight(count > 0 ? .bold : .regular))
                                    .foregroundStyle(isSelected ? Theme.canvas : PaperStyle.ink)
                                    .frame(width: 34, height: 34)
                                    .background(isSelected ? PaperStyle.ink : (count > 0 ? Theme.revealedGround : .clear), in: Circle())
                                    .overlay(Circle().stroke(calendar.isDateInToday(day) ? PaperStyle.ink : .clear, lineWidth: 1.5))
                                HStack(spacing: 2) {
                                    ForEach(0..<min(count, 3), id: \.self) { _ in
                                        Circle().fill(Theme.primary).frame(width: 4, height: 4)
                                    }
                                }
                                .frame(height: 4)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(count == 0)
                        .accessibilityLabel("\(day.formatted(date: .complete, time: .omitted)), \(count) adventure\(count == 1 ? "" : "s")")
                    } else {
                        Color.clear.frame(height: 40)
                    }
                }
            }
        }
        .foregroundStyle(PaperStyle.ink)
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.border))
    }

    /// Leading blanks then each day of the month.
    private func monthDays(_ month: Date) -> [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let leading = (calendar.component(.weekday, from: month) - calendar.firstWeekday + 7) % 7
        return Array(repeating: nil, count: leading) + range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: month) }
    }

    private func shiftMonth(_ delta: Int) {
        if let next = calendar.date(byAdding: .month, value: delta, to: month) { month = next }
        selectedDay = nil
    }

    // MARK: By month

    private var months: some View {
        let shown = selectedDay.map { day in model.historyWalks.filter { calendar.isDate($0.startedAt, inSameDayAs: day) } }
            ?? model.historyWalks
        let groups = Dictionary(grouping: shown) { calendar.dateInterval(of: .month, for: $0.startedAt)?.start ?? $0.startedAt }
        return VStack(alignment: .leading, spacing: 12) {
            if let day = selectedDay {
                HStack {
                    Text(day.formatted(date: .complete, time: .omitted)).font(.subheadline.weight(.semibold))
                    Spacer()
                    Button("Show all") { selectedDay = nil }.font(.subheadline).foregroundStyle(Theme.primary)
                }
            }
            if model.historyWalks.isEmpty {
                Text("Your adventures will appear here.").font(.subheadline).foregroundStyle(Theme.secondaryInk)
                    .frame(maxWidth: .infinity).padding(.top, 24)
            }
            ForEach(groups.keys.sorted(by: >), id: \.self) { month in
                let walks = (groups[month] ?? []).sorted { $0.startedAt > $1.startedAt }
                let newKm = walks.compactMap { model.stats.recaps[$0.id]?.newDistanceMeters }.reduce(0, +)
                HStack {
                    Text(month.formatted(.dateTime.month(.wide).year()).uppercased())
                        .font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondaryInk)
                    Spacer()
                    Text("\(Self.km(newKm)) new").font(.footnote).foregroundStyle(Theme.secondaryInk)
                }
                .padding(.top, 8)
                ForEach(walks) { walk in
                    Button { selected = walk } label: { row(walk) }.buttonStyle(.plain)
                }
            }
        }
    }

    private func row(_ walk: WalkSession) -> some View {
        let recap = model.stats.recaps[walk.id]
        let photo = model.moments(for: walk).first.flatMap { model.thumbnail(for: $0) }
        return HStack(spacing: 14) {
            Group {
                if let photo {
                    Image(uiImage: photo).resizable().scaledToFill()
                } else {
                    RoutePreview(segments: walk.segments).padding(6).background(PaperStyle.paper)
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text("Adventure at \(walk.startedAt.formatted(date: .omitted, time: .shortened))").font(.headline)
                Text("\(walk.startedAt.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) · \(Int((walk.activeDuration(at: walk.endedAt ?? walk.startedAt) / 60).rounded())) min")
                    .font(.footnote).foregroundStyle(Theme.secondaryInk)
                HStack(spacing: 4) {
                    Text("\(Self.km(recap?.newDistanceMeters ?? 0)) new streets").font(.subheadline.weight(.semibold))
                    let found = model.discoveries[walk.id]?.count ?? 0
                    Text("· \(found) place\(found == 1 ? "" : "s")").font(.footnote).foregroundStyle(Theme.secondaryInk)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(Theme.secondaryInk)
        }
        .foregroundStyle(PaperStyle.ink)
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.border))
    }

    static func km(_ meters: Double) -> String { String(format: "%.2f km", meters / 1000) }
}
