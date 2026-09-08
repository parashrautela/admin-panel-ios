import Foundation
import Combine

@MainActor
final class QueueStore: ObservableObject {
    @Published var entity: ReviewEntity = .wholesaler {
        didSet {
            guard oldValue != entity else { return }
            requestGeneration = UUID(); countGeneration = UUID()
            rows = []; counts = nil; cursor = nil; total = 0; updated = nil
            loading = false; error = nil; countError = nil
        }
    }
    @Published var status: WholesalerStatus?
    @Published var search = ""
    @Published var sort = "oldest"
    @Published var ownership = "all"
    @Published private(set) var rows: [Submission] = []
    @Published private(set) var counts: [String: Int]?
    @Published private(set) var total = 0
    @Published private(set) var cursor: String?
    @Published private(set) var loading = false
    @Published private(set) var loadingMore = false
    @Published private(set) var updated: Date?
    @Published var error: AdminAPIError?
    @Published var countError: AdminAPIError?
    @Published var saved: [SavedQueue] = []
    private var requestGeneration = UUID()
    private var countGeneration = UUID()
    private var saveKey = ""
    var signature: String { [entity.rawValue, status?.rawValue ?? "", search, sort, ownership].joined(separator: "|") }
    func loadSaved(actor: String) {
        saveKey = "admin.savedQueues." + actor
        guard let data = UserDefaults.standard.data(forKey: saveKey), let values = try? JSONDecoder().decode([SavedQueue].self, from: data) else { return }
        saved = values
    }
    func save(name: String) {
        guard let name = name.nonblank, !saveKey.isEmpty else { return }
        saved.append(SavedQueue(name: name, entity: entity, status: status, query: search, sort: sort, ownership: ownership))
        persistSaved()
    }
    func removeSaved(id: UUID) { saved.removeAll { $0.id == id }; persistSaved() }
    private func persistSaved() { if let data = try? JSONEncoder().encode(saved) { UserDefaults.standard.set(data, forKey: saveKey) } }
    func apply(_ view: SavedQueue) { entity = view.entity; status = view.status; search = view.query; sort = view.sort; ownership = view.ownership }
    func load(debounce: Bool = false) async {
        let stamp = UUID()
        requestGeneration = stamp
        let scope = signature
        loading = true; error = nil
        defer { if requestGeneration == stamp { loading = false } }
        do {
            if debounce { try await Task.sleep(for: .milliseconds(300)) }
            let value = try await AdminAPI.shared.queue(entity: entity, status: status, search: search, sort: sort, ownership: ownership, cursor: nil)
            try Task.checkCancellation()
            guard requestGeneration == stamp, scope == signature else { return }
            rows = value.rows; total = value.total; cursor = value.next_cursor; updated = Date()
        } catch is CancellationError { }
        catch { if requestGeneration == stamp, !Task.isCancelled { self.error = AdminAPIError.map(error) } }
    }
    func loadMore() async {
        guard let cursor, !loading, !loadingMore else { return }
        let stamp = requestGeneration
        let scope = signature
        loadingMore = true
        defer { loadingMore = false }
        do {
            let page = try await AdminAPI.shared.queue(entity: entity, status: status, search: search, sort: sort, ownership: ownership, cursor: cursor)
            guard stamp == requestGeneration, scope == signature else { return }
            let existing = Set(rows.map(\.id))
            rows += page.rows.filter { !existing.contains($0.id) }
            self.cursor = page.next_cursor; total = page.total
        } catch { if stamp == requestGeneration { self.error = AdminAPIError.map(error) } }
    }
    func loadCounts() async {
        let stamp = UUID()
        countGeneration = stamp
        let scope = entity
        countError = nil
        do {
            let value = try await AdminAPI.shared.counts(entity: scope)
            guard countGeneration == stamp, entity == scope else { return }
            counts = value
        } catch {
            if countGeneration == stamp { counts = nil; countError = AdminAPIError.map(error) }
        }
    }
    func refresh() async { async let a: () = load(); async let b: () = loadCounts(); _ = await (a, b) }
}
