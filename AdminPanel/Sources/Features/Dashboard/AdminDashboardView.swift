import SwiftUI

// Mirrors the web AdminDashboard screen.
struct AdminDashboardView: View {

    private enum Tab: String, CaseIterable {
        case wholesaler
        case retailer
        case apiBackend

        var label: String {
            switch self {
            case .wholesaler: return "Wholesalers"
            case .retailer: return "Retailers"
            case .apiBackend: return "API Key & Backend"
            }
        }

        // Fixed pill widths (not runtime-measured) so the glass thumb's
        // position/size is plain arithmetic — no GeometryReader, no
        // PreferenceKey, no chance of a measure/relayout feedback loop.
        var pillWidth: CGFloat {
            switch self {
            case .wholesaler: return 128
            case .retailer: return 108
            case .apiBackend: return 150
            }
        }
    }

    private static let pillHeight: CGFloat = 52
    private static let pillSpacing: CGFloat = 4
    private static let trayPadding: CGFloat = 4

    private struct LoadKey: Equatable {
        let entity: ReviewEntity
        let filter: WholesalerStatus?
        let search: String
    }

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private var isCompact: Bool { horizontalSizeClass == .compact }

    @State private var selectedEntity: ReviewEntity = .wholesaler
    @State private var selectedFilter: WholesalerStatus? = nil
    @State private var searchQuery = ""
    @State private var submissions: [Submission] = []
    @State private var statusCounts: [WholesalerStatus: Int] = [:]
    @State private var loading = true
    @State private var showApiPanel = false

    private var activeTab: Tab {
        showApiPanel ? .apiBackend : (selectedEntity == .retailer ? .retailer : .wholesaler)
    }

    var body: some View {
        ZStack {
            LiquidBackground()
                .ignoresSafeArea()

            ZStack(alignment: .top) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if !showApiPanel {
                            statsRow
                                .padding(.bottom, isCompact ? 32 : 48)
                        }

                        titleRow
                            .padding(.bottom, isCompact ? 20 : 32)

                        if showApiPanel {
                            APIBackendPanel()
                        } else {
                            searchBar
                                .padding(.bottom, 24)
                            filterChips
                                .padding(.bottom, isCompact ? 20 : 32)
                            submissionsTable
                        }
                    }
                    .padding(.horizontal, isCompact ? 16 : 32)
                    .padding(.top, isCompact ? 72 : 96)
                    .padding(.bottom, 40)
                    .frame(maxWidth: 1280)
                    .frame(maxWidth: .infinity)
                }

                navBar
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task(id: LoadKey(entity: selectedEntity, filter: selectedFilter, search: searchQuery)) {
            // 300ms debounce, matching the web's search debounce.
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await loadDashboard()
        }
    }

    // MARK: - Sections

    private var navBar: some View {
        HStack {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.black)
                    .frame(width: 32, height: 32)
                Text("Admin")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.gray900)
            }
            Spacer()
            NavigationLink {
                AdminProfileView()
            } label: {
                HStack(spacing: 16) {
                    Text("Admin User")
                        .font(.system(size: 14))
                        .foregroundColor(.gray600)
                    Circle()
                        .fill(Color.black)
                        .frame(width: 36, height: 36)
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.white)
                        )
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open admin profile")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: Capsule())
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .frame(maxWidth: 1280)
        .frame(maxWidth: .infinity)
    }

    private var statsRow: some View {
        let cards = [
            StatCard(value: statusCounts[.pending] ?? 0, label: "Pending review"),
            StatCard(value: statusCounts[.on_hold] ?? 0, label: "On Hold"),
            StatCard(value: statusCounts[.verified] ?? 0, label: "Verified total"),
            StatCard(value: statusCounts[.banned] ?? 0, label: "Banned"),
        ]
        return GlassEffectContainer(spacing: 16) {
            if isCompact {
                // Four flexible-width cards in one row get crushed below iPad
                // width — a 2x2 grid keeps each card's number/label readable.
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible())], spacing: 16) {
                    ForEach(Array(cards.enumerated()), id: \.offset) { _, card in card }
                }
            } else {
                HStack(spacing: 24) {
                    ForEach(Array(cards.enumerated()), id: \.offset) { _, card in card }
                }
            }
        }
    }

    private var titleRow: some View {
        Group {
            if isCompact {
                // Fixed-width tab pills (128+108+150pt) don't fit beside a
                // title on phone width — stack them, and let the pills
                // scroll rather than resize (resizing would break the
                // hand-tuned thumb-offset math in thumbOffsetX).
                VStack(alignment: .leading, spacing: 16) {
                    titleText
                    ScrollView(.horizontal, showsIndicators: false) { tabPills }
                }
            } else {
                HStack(alignment: .center) {
                    titleText
                    Spacer()
                    tabPills
                }
            }
        }
    }

    private var titleText: some View {
        Text(showApiPanel ? "API Keys & Backend" : "\(selectedEntity.label) submissions")
            .font(.system(size: 30, weight: .light))
            .foregroundColor(.gray900)
    }

    private var tabPills: some View {
        GlassEffectContainer(spacing: 12) {
            ZStack(alignment: .topLeading) {
                // Single persistent glass thumb — never inserted/removed, so its
                // frame change under withAnimation always animates smoothly. Its
                // geometry is plain arithmetic from the fixed pill widths above.
                Capsule()
                    .glassEffect(.regular.tint(.black.opacity(0.62)).interactive(), in: Capsule())
                    .frame(width: activeTab.pillWidth, height: Self.pillHeight)
                    .offset(x: thumbOffsetX, y: Self.trayPadding)

                HStack(spacing: Self.pillSpacing) {
                    ForEach(Tab.allCases, id: \.self) { tab in
                        tabButton(tab)
                    }
                }
                .padding(Self.trayPadding)
            }
            .glassEffect(.regular, in: Capsule())
        }
    }

    private var thumbOffsetX: CGFloat {
        var x = Self.trayPadding
        for tab in Tab.allCases {
            if tab == activeTab { break }
            x += tab.pillWidth + Self.pillSpacing
        }
        return x
    }

    private func tabButton(_ tab: Tab) -> some View {
        Button {
            selectTab(tab)
        } label: {
            Text(tab.label)
                .multilineTextAlignment(.center)
                .font(.system(size: 14, weight: .medium))
                .frame(width: tab.pillWidth, height: Self.pillHeight)
                .foregroundColor(activeTab == tab ? .white : .gray700)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func selectTab(_ tab: Tab) {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.74, blendDuration: 0.2)) {
            if tab == .apiBackend {
                showApiPanel = true
            } else {
                showApiPanel = false
                selectedEntity = tab == .retailer ? .retailer : .wholesaler
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17))
                .foregroundColor(.gray400)
            TextField("Search \(selectedEntity.label.lowercased())s...", text: $searchQuery)
                .font(.system(size: 16))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .glassEffect(.regular.tint(.white.opacity(0.4)), in: Capsule())
        .frame(maxWidth: 448)
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                FilterChip(
                    label: "All",
                    count: nil,
                    isSelected: selectedFilter == nil
                ) { selectedFilter = nil }

                ForEach([WholesalerStatus.pending, .on_hold, .verified, .rejected, .resubmission_required, .banned], id: \.self) { status in
                    FilterChip(
                        label: status.filterLabel,
                        count: statusCounts[status] ?? 0,
                        isSelected: selectedFilter == status
                    ) { selectedFilter = status }
                }
            }
        }
    }

    private var submissionsTable: some View {
        Group {
            // The 6-column table divides width into fixed fractions (down to
            // a 10%-wide action column) — below iPad width that's unreadably
            // narrow, so phones get a stacked card per submission instead.
            if isCompact {
                compactSubmissionsList
            } else {
                GeometryReader { geo in
                    let width = geo.size.width
                    VStack(spacing: 0) {
                        SubmissionHeaderRow(entityLabel: selectedEntity.label, width: width)
                        Divider().overlay(Color.gray100)

                        if loading {
                            tableMessage("Loading \(selectedEntity.label.lowercased())s...")
                        } else if submissions.isEmpty {
                            tableMessage("No \(selectedEntity.label.lowercased())s found.")
                        } else {
                            ForEach(Array(submissions.enumerated()), id: \.element.id) { index, submission in
                                SubmissionRow(submission: submission, entity: selectedEntity, width: width)
                                if index < submissions.count - 1 {
                                    Divider().overlay(Color.gray100)
                                }
                            }
                        }
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.gray200.opacity(0.6), lineWidth: 1)
                    )
                }
                .frame(minHeight: tableHeight)
            }
        }
    }

    private var compactSubmissionsList: some View {
        VStack(spacing: 0) {
            if loading {
                tableMessage("Loading \(selectedEntity.label.lowercased())s...")
            } else if submissions.isEmpty {
                tableMessage("No \(selectedEntity.label.lowercased())s found.")
            } else {
                ForEach(Array(submissions.enumerated()), id: \.element.id) { index, submission in
                    CompactSubmissionCard(submission: submission, entity: selectedEntity)
                    if index < submissions.count - 1 {
                        Divider().overlay(Color.gray100)
                    }
                }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray200.opacity(0.6), lineWidth: 1)
        )
    }

    private var tableHeight: CGFloat {
        let rows = loading || submissions.isEmpty ? 1 : CGFloat(submissions.count)
        let rowHeight: CGFloat = loading || submissions.isEmpty ? 88 : 81
        return 49 + rows * rowHeight + 8
    }

    private func tableMessage(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15))
            .foregroundColor(.gray500)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
    }

    // MARK: - Data

    private func loadDashboard() async {
        loading = true
        do {
            async let counts = AdminAPI.fetchStatusCounts(entity: selectedEntity)
            async let rows = AdminAPI.fetchSubmissions(
                entity: selectedEntity,
                statusFilter: selectedFilter,
                searchQuery: searchQuery
            )
            statusCounts = try await counts
            submissions = try await rows
        } catch {
            if !(error is CancellationError) {
                print("Failed to fetch dashboard data: \(error)")
            }
        }
        loading = false
    }
}

// MARK: - Components

struct StatCard: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(value)")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(.gray900)
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(.gray600)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .glassEffect(.regular.tint(.white.opacity(0.35)), in: RoundedRectangle(cornerRadius: 16))
    }
}

struct FilterChip: View {
    let label: String
    let count: Int?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            withAnimation(.smooth(duration: 0.3)) {
                action()
            }
        } label: {
            HStack(spacing: 6) {
                Text(label)
                if let count {
                    Text("\(count)")
                }
            }
            .font(.system(size: 14, weight: .medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .foregroundColor(isSelected ? .white : .gray700)
            .background(isSelected ? Color.black : Color.gray100, in: Capsule())
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: isSelected)
    }
}

struct StatusBadge: View {
    let status: WholesalerStatus

    private var background: Color {
        switch status {
        case .pending: return .gray100
        case .on_hold: return .blue100
        case .verified, .banned: return .black
        case .resubmission_required: return .yellow100
        case .rejected: return .red100
        }
    }

    private var foreground: Color {
        switch status {
        case .pending: return .gray900
        case .on_hold: return .blue900
        case .verified, .banned: return .white
        case .resubmission_required: return .yellow900
        case .rejected: return .red900
        }
    }

    var body: some View {
        Text(status.label)
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(background)
            .foregroundColor(foreground)
            .clipShape(Capsule())
    }
}

private struct TableColumns {
    let person: CGFloat
    let business: CGFloat
    let location: CGFloat
    let submitted: CGFloat
    let status: CGFloat
    let action: CGFloat

    init(width: CGFloat) {
        let usable = max(width - 48, 300)
        person = usable * 0.26
        business = usable * 0.19
        location = usable * 0.19
        submitted = usable * 0.13
        status = usable * 0.13
        action = usable * 0.10
    }
}

private struct SubmissionHeaderRow: View {
    let entityLabel: String
    let width: CGFloat

    var body: some View {
        let cols = TableColumns(width: width)
        HStack(spacing: 0) {
            headerCell(entityLabel.uppercased(), width: cols.person)
            headerCell("BUSINESS", width: cols.business)
            headerCell("LOCATION", width: cols.location)
            headerCell("SUBMITTED", width: cols.submitted)
            headerCell("STATUS", width: cols.status)
            headerCell("", width: cols.action)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private func headerCell(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .kerning(0.6)
            .foregroundColor(.gray500)
            .lineLimit(1)
            .frame(width: width, alignment: .leading)
    }
}

private struct SubmissionRow: View {
    let submission: Submission
    let entity: ReviewEntity
    let width: CGFloat

    var body: some View {
        let cols = TableColumns(width: width)
        HStack(spacing: 0) {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.gray900)
                    .frame(width: 40, height: 40)
                    .overlay(
                        Text(submission.initial)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                    )
                Text(submission.displayName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.gray900)
                    .lineLimit(1)
            }
            .frame(width: cols.person, alignment: .leading)

            Text(submission.business_name ?? "—")
                .font(.system(size: 15))
                .foregroundColor(.gray700)
                .lineLimit(1)
                .frame(width: cols.business, alignment: .leading)

            Text("\(submission.city ?? "—"), \(submission.state ?? "—")")
                .font(.system(size: 15))
                .foregroundColor(.gray600)
                .lineLimit(1)
                .frame(width: cols.location, alignment: .leading)

            Text(submission.submittedDateText)
                .font(.system(size: 14))
                .foregroundColor(.gray600)
                .lineLimit(1)
                .frame(width: cols.submitted, alignment: .leading)

            HStack {
                StatusBadge(status: submission.status)
                Spacer(minLength: 0)
            }
            .frame(width: cols.status, alignment: .leading)

            NavigationLink(value: ReviewRoute(entity: entity, id: submission.id)) {
                Text(submission.status == .verified || submission.status == .banned ? "View" : "Review")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.black)
            }
            .buttonStyle(.plain)
            .frame(width: cols.action, alignment: .leading)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }
}

// Phone-width replacement for SubmissionRow: the same fields, stacked
// instead of split across six fixed-width columns.
private struct CompactSubmissionCard: View {
    let submission: Submission
    let entity: ReviewEntity

    var body: some View {
        NavigationLink(value: ReviewRoute(entity: entity, id: submission.id)) {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(Color.gray900)
                    .frame(width: 40, height: 40)
                    .overlay(
                        Text(submission.initial)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 8) {
                        Text(submission.displayName)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.gray900)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        StatusBadge(status: submission.status)
                    }
                    Text(submission.business_name ?? "—")
                        .font(.system(size: 14))
                        .foregroundColor(.gray700)
                        .lineLimit(1)
                    Text("\(submission.city ?? "—"), \(submission.state ?? "—") · \(submission.submittedDateText)")
                        .font(.system(size: 13))
                        .foregroundColor(.gray500)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}

// MARK: - API panel

private struct APIService: Identifiable {
    let name: String
    let description: String
    let url: String
    let initial: String
    var id: String { name }
}

struct APIBackendPanel: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private var isCompact: Bool { horizontalSizeClass == .compact }

    private let services = [
        APIService(name: "Supabase", description: "Database, Authentication & Storage", url: "https://supabase.com/", initial: "S"),
        APIService(name: "Railway", description: "Backend Infrastructure & Deployment", url: "https://railway.com/dashboard", initial: "R"),
        APIService(name: "Vercel", description: "Frontend Hosting & Edge Network", url: "https://vercel.com/", initial: "V"),
        APIService(name: "Nano Banana", description: "Service Integration", url: "https://nanobananaapi.ai/dashboard", initial: "N")
    ]

    var body: some View {
        VStack(spacing: 0) {
            if !isCompact {
                HStack(spacing: 0) {
                    headerCell("SERVICE").frame(maxWidth: .infinity, alignment: .leading)
                    headerCell("DESCRIPTION").frame(maxWidth: .infinity, alignment: .leading)
                    headerCell("STATUS").frame(width: 120, alignment: .leading)
                    headerCell("").frame(width: 90, alignment: .leading)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                Divider().overlay(Color.gray100)
            }

            ForEach(Array(services.enumerated()), id: \.element.id) { index, service in
                if isCompact {
                    CompactServiceRow(service: service)
                } else {
                    HStack(spacing: 0) {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Color.gray900)
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Text(service.initial)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.white)
                                )
                            Text(service.name)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.gray900)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Text(service.description)
                            .font(.system(size: 14))
                            .foregroundColor(.gray600)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        HStack {
                            Text("Active")
                                .font(.system(size: 12, weight: .medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.black)
                                .foregroundColor(.white)
                                .clipShape(Capsule())
                            Spacer(minLength: 0)
                        }
                        .frame(width: 120)

                        if let url = URL(string: service.url) {
                            Link(destination: url) {
                                HStack(spacing: 6) {
                                    Text("Open")
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.black)
                            }
                            .frame(width: 90, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                }

                if index < services.count - 1 {
                    Divider().overlay(Color.gray100)
                }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray200.opacity(0.6), lineWidth: 1)
        )
    }

    private func headerCell(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .kerning(0.6)
            .foregroundColor(.gray500)
            .lineLimit(1)
    }
}

// Phone-width replacement for the 4-column service row: name+status on one
// line, description below, Open link on its own row instead of a squeezed
// fixed-width column.
private struct CompactServiceRow: View {
    let service: APIService

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.gray900)
                    .frame(width: 40, height: 40)
                    .overlay(
                        Text(service.initial)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                    )
                Text(service.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.gray900)
                Spacer(minLength: 8)
                Text("Active")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.black)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
            }

            Text(service.description)
                .font(.system(size: 14))
                .foregroundColor(.gray600)

            if let url = URL(string: service.url) {
                Link(destination: url) {
                    HStack(spacing: 6) {
                        Text("Open")
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.black)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}

#Preview {
    NavigationStack {
        AdminDashboardView()
    }
}
