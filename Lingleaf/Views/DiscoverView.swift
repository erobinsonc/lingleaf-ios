import SwiftUI
import LingleafCore

/// Recommended classics (shipped with the app) and search of Project Gutenberg, with a
/// download that shows its progress, can be cancelled, and says why it failed (S9, S12).
struct DiscoverView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var results: [GutenbergBook]?
    @State private var searchTask: Task<Void, Never>?
    @State private var searching = false
    /// The search has taken over 8 s: say Project Gutenberg can be slow, and offer Cancel.
    @State private var slow = false
    @State private var searchError: GutenbergError?
    @State private var downloads: [Int: Download] = [:]
    /// Level chosen in the filter chips; nil shows every recommended book.
    @State private var level: String?

    /// A download in progress (0…1) or why it failed.
    private enum Download: Equatable {
        case running(Double, Task<Void, Never>)
        case failed(GutenbergError)

        static func == (lhs: Download, rhs: Download) -> Bool {
            switch (lhs, rhs) {
            case let (.running(a, _), .running(b, _)): a == b
            case let (.failed(a), .failed(b)): a == b
            default: false
            }
        }
    }

    /// Levels that have at least one recommended book, easiest first.
    private static let filterLevels = GutenbergClient.levels.filter { level in
        GutenbergClient.recommended.contains { $0.level == level }
    }

    private var recommended: [GutenbergBook] { GutenbergClient.filter(GutenbergClient.recommendedBooks, level: level) }

    var body: some View {
        NavigationStack {
            List {
                if searching || searchError != nil { searchStatus }
                if let results {
                    Section {
                        if results.isEmpty {
                            Text("No books found. Try another title or author.")
                        } else {
                            ForEach(results) { row($0) }
                        }
                    } header: {
                        Text("Results").foregroundStyle(Brand.secondaryText)
                    }
                }
                Section {
                    levelFilter
                    if recommended.isEmpty {
                        Text("No recommended books at this level.")
                    } else {
                        ForEach(recommended) { row($0) }
                    }
                } header: {
                    // The credit lives in the header: as a footer, a row among the books or
                    // a section of its own, the audit reported it as not scaling with Dynamic Type.
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Recommended for learners")
                        Text("Free public-domain classics from Project Gutenberg.")
                            .font(.footnote)
                            .textCase(nil)
                    }
                    .foregroundStyle(Brand.secondaryText)
                }
            }
            .navigationTitle("Discover")
            .navigationDestination(for: String.self) { ReaderView(bookID: $0) }
            .searchable(text: $query, prompt: "Title or author")
            .onSubmit(of: .search) { startSearch() }
            .onChange(of: query) { _, newValue in
                if newValue.isEmpty { cancelSearch() }
            }
        }
    }

    // MARK: Search

    /// "Searching Project Gutenberg…", after 8 s "Still searching…" with Cancel, or why it failed with Retry.
    @ViewBuilder
    private var searchStatus: some View {
        Section {
            if searching {
                HStack(spacing: 12) {
                    ProgressView()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Searching Project Gutenberg…")
                        if slow {
                            Text("Still searching. Project Gutenberg can be slow.")
                                .font(.subheadline)
                                .foregroundStyle(Brand.secondaryText)
                        }
                    }
                    Spacer(minLength: 8)
                    if slow {
                        Button("Cancel") { cancelSearch() }.buttonStyle(.bordered)
                    }
                }
                .accessibilityElement(children: .contain)
            } else if let searchError {
                VStack(alignment: .leading, spacing: 10) {
                    Text(searchMessage(searchError))
                    Button("Retry") { startSearch() }.buttonStyle(.bordered)
                }
            }
        }
    }

    private func searchMessage(_ error: GutenbergError) -> String {
        switch error {
        case .offline: String(localized: "You're offline. Connect to the internet to search.")
        default: String(localized: "Project Gutenberg didn't answer. Try again.")
        }
    }

    /// A new search cancels the one still running.
    private func startSearch() {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        searchTask?.cancel()
        searching = true
        slow = false
        searchError = nil
        results = nil
        let gutenberg = model.gutenberg
        searchTask = Task {
            let slowTimer = Task {
                try? await Task.sleep(for: .seconds(8))
                if !Task.isCancelled { slow = true }
            }
            defer { slowTimer.cancel() }
            do {
                let found = try await gutenberg.search(text)
                guard !Task.isCancelled else { return }
                results = found
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                searchError = (error as? GutenbergError) ?? .failed
            }
            searching = false
        }
    }

    private func cancelSearch() {
        searchTask?.cancel()
        searchTask = nil
        searching = false
        slow = false
        searchError = nil
        results = nil
    }

    // MARK: Level filter

    /// "All" plus one chip per level; scrolls sideways when the text is large.
    private var levelFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(nil)
                ForEach(Self.filterLevels, id: \.self) { chip($0) }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 4)
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }

    private func chip(_ value: String?) -> some View {
        let selected = level == value
        return Button {
            level = value
        } label: {
            Group {
                if let value { Text(verbatim: value) } else { Text("All") }
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            // System background is white in light mode and black in dark mode, where the ink is light.
            .foregroundStyle(selected ? Color(uiColor: .systemBackground) : Color.primary)
            .background(selected ? Brand.ink : Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
            .contentShape(Capsule())
        }
        // Plain style so a tap in the row triggers only this chip.
        .buttonStyle(.plain)
        .accessibilityLabel(value.map { Text("Level \($0)") } ?? Text("All levels"))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("level-filter-\(value ?? "all")")
    }

    // MARK: Books

    private func row(_ book: GutenbergBook) -> some View {
        let failure = failure(book.id)
        return HStack(spacing: 14) {
            AsyncImage(url: book.coverURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                BookCover(title: book.displayTitle)
            }
            .frame(width: 44, height: 62)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(book.displayTitle).font(.headline)
                HStack(spacing: 6) {
                    if let level = GutenbergClient.level(for: book.id) { LevelBadge(level: level) }
                    Text(book.authorName ?? String(localized: "Unknown author"))
                        .font(.subheadline).foregroundStyle(Brand.secondaryText)
                }
                if let failure {
                    Text(downloadMessage(failure))
                        .font(.subheadline)
                        .foregroundStyle(Brand.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            action(book, failure: failure)
        }
        .padding(.vertical, 4)
    }

    /// Get → a progress ring (tap to cancel) → Read; Retry after a failure that may pass.
    @ViewBuilder
    private func action(_ book: GutenbergBook, failure: GutenbergError?) -> some View {
        if let saved = model.state.books.first(where: { $0.gutenbergID == book.id }) {
            NavigationLink(value: saved.id) {
                Text("Read")
            }
            .buttonStyle(.borderedProminent)
            .tint(Brand.ink)
            .accessibilityLabel(Text("Read \(book.displayTitle)"))
        } else if case let .running(fraction, task) = downloads[book.id] {
            Button {
                task.cancel()
                downloads[book.id] = nil
            } label: {
                ProgressView(value: fraction)
                    .progressViewStyle(.circular)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Downloading \(book.displayTitle)"))
            .accessibilityValue(Text(fraction, format: .percent.precision(.fractionLength(0))))
            .accessibilityHint(Text("Cancel download"))
        } else if book.textURL == nil || failure == .unavailable {
            // No plain-text edition: a disabled button would be dimmed below readable contrast.
            if book.textURL == nil {
                Text("Not available")
                    .font(.subheadline)
                    .foregroundStyle(Brand.secondaryText)
            }
        } else {
            Button(failure == nil ? LocalizedStringKey("Get") : LocalizedStringKey("Retry")) { download(book) }
                .buttonStyle(.bordered)
                .accessibilityLabel(failure == nil ? Text("Get \(book.displayTitle)") : Text("Retry \(book.displayTitle)"))
        }
    }

    private func failure(_ id: Int) -> GutenbergError? {
        if case let .failed(error) = downloads[id] { return error }
        return nil
    }

    private func downloadMessage(_ error: GutenbergError) -> String {
        switch error {
        case .unavailable: String(localized: "This book isn't available right now.")
        case .offline: String(localized: "You're offline. Connect to the internet to download it.")
        case .timedOut, .failed: String(localized: "Project Gutenberg didn't answer. Try again.")
        }
    }

    private func download(_ book: GutenbergBook) {
        let gutenberg = model.gutenberg
        let library = model.library
        let id = book.id
        let task = Task {
            do {
                let text = try await gutenberg.downloadText(book) { fraction in
                    Task { @MainActor in
                        if case let .running(_, task) = downloads[id] { downloads[id] = .running(fraction, task) }
                    }
                }
                library.addBook(
                    title: book.displayTitle,
                    author: book.authorName ?? String(localized: "Unknown author"),
                    text: text,
                    level: GutenbergClient.level(for: id),
                    gutenbergID: id
                )
                downloads[id] = nil
            } catch is CancellationError {
                downloads[id] = nil
            } catch {
                guard !Task.isCancelled else { return }
                downloads[id] = .failed((error as? GutenbergError) ?? .failed)
            }
        }
        downloads[id] = .running(0, task)
    }
}
