import SwiftUI

struct ReviewRoute: Hashable { let entity: ReviewEntity; let id: String }
enum AdminDestination: String, CaseIterable, Identifiable {
    case wholesalers, retailers, system, account
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .wholesalers: return "shippingbox"
        case .retailers: return "storefront"
        case .system: return "server.rack"
        case .account: return "person.crop.circle"
        }
    }
}

struct AdminDashboardView: View {
    @EnvironmentObject private var auth: AdminAuth
    @Environment(\.horizontalSizeClass) private var size
    @StateObject private var queue = QueueStore()
    @State private var destination: AdminDestination? = .wholesalers
    @State private var selected: String?
    @State private var compactTab = 0
    var body: some View {
        Group {
            if size == .regular {
                NavigationSplitView {
                    List(selection: $destination) {
                        Section {
                            Label("Jewel India", systemImage: "diamond.fill").font(.title2.bold()).foregroundStyle(AdminTheme.accent)
                            EnvironmentBadge()
                        }
                        Section("Workspace") {
                            ForEach(AdminDestination.allCases) { item in
                                Label(item.title, systemImage: item.symbol).padding(.vertical, 6).tag(item)
                            }
                        }
                        if !queue.saved.isEmpty {
                            Section("Saved views") {
                                ForEach(queue.saved) { view in
                                    Button { destination = view.entity == .wholesaler ? .wholesalers : .retailers; queue.apply(view); selected = nil } label: {
                                        Label(view.name, systemImage: "bookmark").frame(minHeight: 44)
                                    }
                                    .contextMenu { Button("Delete saved view", role: .destructive) { queue.removeSaved(id: view.id) } }
                                }
                            }
                        }
                    }.navigationTitle("Workspace")
                        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 270)
                } content: {
                    if destination == .system { SystemView() }
                    else if destination == .account { AccountView() }
                    else { QueueView(store: queue, selection: $selected, split: true) }
                } detail: {
                    if let selected, destination != .system, destination != .account {
                        WholesalerReviewView(entity: queue.entity, submissionId: selected).id(queue.entity.table + selected)
                    } else {
                        ContentUnavailableView("Your review workspace", systemImage: "doc.text.magnifyingglass", description: Text("Choose an application to inspect its evidence, activity, and decision options."))
                    }
                }
                .navigationSplitViewStyle(.balanced)
            } else {
                TabView(selection: $compactTab) {
                    NavigationStack {
                        QueueView(store: queue, selection: $selected, split: false)
                            .navigationDestination(for: ReviewRoute.self) { route in WholesalerReviewView(entity: route.entity, submissionId: route.id) }
                    }.tabItem { Label("Queue", systemImage: "tray.full") }.tag(0)
                    NavigationStack { SystemView() }.tabItem { Label("System", systemImage: "server.rack") }.tag(1)
                    NavigationStack { AccountView() }.tabItem { Label("Account", systemImage: "person.crop.circle") }.tag(2)
                }
            }
        }
        .task { queue.loadSaved(actor: auth.profile?.id ?? "unknown") }
        .onChange(of: destination) { _, value in
            if value == .wholesalers { queue.entity = .wholesaler }
            if value == .retailers { queue.entity = .retailer }
            selected = nil
        }
        .onChange(of: queue.entity) { selected = nil }
        .onReceive(NotificationCenter.default.publisher(for: .adminDataChanged)) { _ in Task { await queue.refresh() } }
    }
}

struct QueueView: View {
    @ObservedObject var store: QueueStore
    @Binding var selection: String?
    var split: Bool
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var saveSheet = false
    @State private var saveName = ""
    var body: some View {
        List {
            overview
            filtersAndState
            applications
        }
        .listStyle(.insetGrouped).navigationTitle(store.entity.label + "s")
        .searchable(text: $store.search, prompt: "Search applicant or business")
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await store.refresh() }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { Task { await store.refresh() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }.keyboardShortcut("r", modifiers: .command)
                Button { saveSheet = true } label: { Label("Save view", systemImage: "bookmark") }
            }
        }
        .task(id: store.signature) { await store.load(debounce: true) }
        .task(id: store.entity) { await store.loadCounts() }
        .sheet(isPresented: $saveSheet) { savedViewsSheet }
    }
    private var overview: some View {
        Section {
                if !split {
                    Picker("Application type", selection: $store.entity) {
                        ForEach(ReviewEntity.allCases) { entity in Text(entity.label + "s").tag(entity) }
                    }.pickerStyle(.segmented).accessibilityIdentifier("entityPicker")
                }
                EnvironmentBadge()
                DisclosureGroup("Queue totals · all applications") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: textSize.isAccessibilitySize ? 160 : 100))], spacing: 10) {
                    ForEach(WholesalerStatus.allCases.filter { $0 != .unknown }) { status in
                        Button {
                            store.status = store.status == status ? nil : status
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(countText(status, fallback: "—")).font(.title2.bold())
                                Text(status.label).font(.caption.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                            }.frame(maxWidth: .infinity, minHeight: 58, alignment: .leading).padding(10)
                                .foregroundStyle(.primary)
                                .background(store.status == status ? AdminTheme.accent.opacity(0.15) : AdminTheme.background, in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain)
                            .accessibilityLabel(status.label + ", " + countText(status, fallback: "unavailable"))
                            .accessibilityAddTraits(store.status == status ? [.isSelected] : [])
                    }
                }
                }
            }.listRowSeparator(.hidden)
    }
    private func countText(_ status: WholesalerStatus, fallback: String) -> String {
        guard let value = store.counts?[status.rawValue] else { return fallback }
        return String(value)
    }
    private var filtersAndState: some View {
        Section {
                ViewThatFits(in: .horizontal) {
                    HStack { controls }
                    VStack(alignment: .leading) { controls }
                }
                HStack {
                    Text("\(store.total) matching applications").font(.subheadline.weight(.semibold))
                    Spacer()
                    if store.loading { ProgressView().accessibilityLabel("Updating applications") }
                }
                if let updated = store.updated {
                    Text("Updated " + updated.formatted(date: .omitted, time: .shortened) + (store.loading || store.error != nil ? " · showing previous results" : ""))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error = store.countError { ErrorPanel(error: error) { Task { await store.loadCounts() } } }
                if let error = store.error { ErrorPanel(error: error) { Task { await store.load() } } }
            }.listRowSeparator(.hidden)
    }
    private var applications: some View {
        Section("Applications") {
                if store.rows.isEmpty && !store.loading && store.error == nil {
                    ContentUnavailableView(store.search.trimmed.isEmpty && store.status == nil ? "Queue is clear" : "No matching applications", systemImage: "tray", description: Text("Try another filter, or refresh for new submissions."))
                    if store.status != nil || !store.search.isEmpty || store.ownership != "all" {
                        Button("Clear filters") { store.status = nil; store.search = ""; store.ownership = "all" }.frame(minHeight: 44)
                    }
                } else if store.rows.isEmpty && store.loading {
                    ProgressView("Loading applications…").frame(maxWidth: .infinity, minHeight: 100)
                }
                ForEach(store.rows) { row in
                    if split {
                        Button { selection = row.id } label: { SubmissionRow(submission: row, selected: row.id == selection) }
                            .buttonStyle(.plain).accessibilityIdentifier("review-" + row.id)
                            .accessibilityAddTraits(row.id == selection ? [.isSelected] : [])
                    } else {
                        NavigationLink(value: ReviewRoute(entity: store.entity, id: row.id)) {
                            SubmissionRow(submission: row, selected: false)
                        }.accessibilityIdentifier("review-" + row.id)
                    }
                }
                if store.cursor != nil {
                    Button { Task { await store.loadMore() } } label: {
                        HStack { if store.loadingMore { ProgressView() }; Text("Load more applications") }.frame(maxWidth: .infinity, minHeight: 44)
                    }.disabled(store.loading || store.loadingMore)
                }
            }
    }
    private var savedViewsSheet: some View {
        NavigationStack {
                Form {
                    TextField("View name", text: $saveName)
                    Text("Saves these filters and search on this device for your account.").font(.footnote)
                    Button("Save current view") { store.save(name: saveName); saveName = ""; saveSheet = false }.disabled(saveName.trimmed.isEmpty)
                    ForEach(store.saved) { view in
                        Button(view.name) { store.apply(view); saveSheet = false }
                            .swipeActions { Button("Delete", role: .destructive) { store.removeSaved(id: view.id) } }
                    }
                }.navigationTitle("Saved views")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { saveSheet = false } } }
        }
    }
    @ViewBuilder private var controls: some View {
        Menu {
            Button("All statuses") { store.status = nil }
            ForEach(WholesalerStatus.allCases) { status in Button(status.label) { store.status = status } }
        } label: { Label(store.status?.label ?? "All statuses", systemImage: "line.3.horizontal.decrease").frame(minHeight: 44) }
        Picker("Sort", selection: $store.sort) {
            Text("Oldest first").tag("oldest")
            Text("Newest first").tag("newest")
            Text("Business name").tag("name")
        }.pickerStyle(.menu).frame(minHeight: 44)
        Picker("Assignment", selection: $store.ownership) {
            Text("Everyone").tag("all")
            Text("Assigned to me").tag("mine")
            Text("Unassigned").tag("unassigned")
        }.pickerStyle(.menu).frame(minHeight: 44)
    }
}
struct SubmissionRow: View {
    let submission: Submission
    let selected: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ViewThatFits(in: .horizontal) {
                HStack { Text(submission.business).font(.headline); Spacer(); StatusBadge(status: submission.status) }
                VStack(alignment: .leading, spacing: 8) { Text(submission.business).font(.headline); StatusBadge(status: submission.status) }
            }
            Text(submission.displayName).font(.subheadline)
            Label(submission.location, systemImage: "mappin.and.ellipse").font(.caption).foregroundStyle(.secondary)
            HStack {
                Text(submission.createdDate == nil ? "Submitted time unavailable" : "\(submission.ageDays) days in queue")
                Spacer()
                Label(submission.assigned_to == nil ? "Unassigned" : "Assigned", systemImage: "person")
            }.font(.caption).foregroundStyle(.secondary)
            if let due = Submission.date(submission.follow_up_at) {
                Label(due < Date() ? "Follow-up overdue" : "Follow-up " + due.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                    .font(.caption).foregroundStyle(due < Date() ? .red : .secondary)
            }
        }
        .padding(.vertical, 10).padding(.horizontal, selected ? 10 : 0)
        .background(selected ? AdminTheme.accent.opacity(0.1) : Color.clear, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}
