import SwiftUI

// Mirrors the web AdminDashboard screen.
// Intercom-inspired presentation: cream canvas, white floating cards, charcoal
// primary actions, hairline borders, dot-style status badges, no shadows.
struct AdminDashboardView: View {

    private enum Tab: String, CaseIterable {
        case wholesaler
        case retailer
        case apiBackend

        var label: String {
            switch self {
            case .wholesaler: return "Wholesalers"
            case .retailer: return "Retailers"
            case .apiBackend: return "API"
            }
        }

        // Fixed pill widths (not runtime-measured) so the selected thumb's
        // position/size is plain arithmetic — no GeometryReader, no
        // PreferenceKey, no chance of a measure/relayout feedback loop.
        // The three pills plus tray padding fit a 370pt phone content width.
        var pillWidth: CGFloat {
            switch self {
            case .wholesaler: return 118
            case .retailer: return 104
            case .apiBackend: return 88
            }
        }
    }

    private static let pillHeight: CGFloat = 40
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
    @State private var dashboardError: String?

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
            HStack(spacing: 10) {
                // Same brand mark as the login screen.
                Text("JI")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.onPrimary)
                    .frame(width: 32, height: 32)
                    .background(Color.ink, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text("Admin")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.ink)
            }
            Spacer()
            NavigationLink {
                AdminProfileView()
            } label: {
                HStack(spacing: 16) {
                    Text("Admin User")
                        .font(.system(size: 14))
                        .foregroundColor(.inkMuted)
                    Circle()
                        .fill(Color.ink)
                        .frame(width: 36, height: 36)
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.onPrimary)
                        )
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open admin profile")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .webCard()
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
        return Group {
            if isCompact {
                // Four flexible-width cards in one row get crushed below iPad
                // width — a 2x2 grid keeps each card's number/label readable.
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible())], spacing: 16) {
                    ForEach(Array(cards.enumerated()), id: \.offset) { _, card in card }
                }
            } else {
                HStack(spacing: 16) {
                    ForEach(Array(cards.enumerated()), id: \.offset) { _, card in card }
                }
            }
        }
    }

    private var titleRow: some View {
        Group {
            if isCompact {
                // Fixed-width tab segments don't fit beside a title on phone
                // width, so stack them. The segments are short enough to fit
                // on one row without scrolling.
                VStack(alignment: .leading, spacing: 16) {
                    titleText
                    tabPills
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
            .font(.system(size: 28, weight: .semibold))
            .foregroundColor(.ink)
    }

    private var tabPills: some View {
        ZStack(alignment: .topLeading) {
            // Single persistent selected thumb — never inserted/removed, so its
            // frame change under withAnimation always animates smoothly. Its
            // geometry is plain arithmetic from the fixed pill widths above.
            Capsule()
                .fill(Color.surface1)
                .overlay(Capsule().stroke(Color.hairline, lineWidth: 1))
                .frame(width: activeTab.pillWidth, height: Self.pillHeight)
                .offset(x: thumbOffsetX, y: Self.trayPadding)

            HStack(spacing: Self.pillSpacing) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    tabButton(tab)
                }
            }
            .padding(Self.trayPadding)
        }
        .background(Capsule().fill(Color.surface2))
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
                .foregroundColor(activeTab == tab ? .ink : .inkMuted)
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
                .foregroundColor(.inkSubtle)
            TextField("Search \(selectedEntity.label.lowercased())s...", text: $searchQuery)
                .font(.system(size: 16))
                .foregroundColor(.ink)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(minHeight: 44)
        .webCard()
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
        LazyVStack(alignment: .leading, spacing: 16) {
            if loading { tableMessage("Loading businesses…") }
            else if let dashboardError {
                VStack(alignment: .leading, spacing: 12) {
                    Text(dashboardError)
                        .font(.system(size: 15))
                        .foregroundColor(.danger)
                    Button("Retry") { Task { await loadDashboard() } }
                        .buttonStyle(.plain)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.ink)
                        .frame(minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .webCard()
            }
            else if submissions.isEmpty { tableMessage("No businesses found.") }
            else {
                ForEach(submissions) { submission in
                    CompactSubmissionCard(submission: submission, entity: selectedEntity)
                }
            }
        }
    }

    private func tableMessage(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15))
            .foregroundColor(.inkSubtle)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
            .webCard()
    }

    // MARK: - Data

    private func loadDashboard() async {
        let key = LoadKey(entity: selectedEntity, filter: selectedFilter, search: searchQuery)
        loading = true; dashboardError = nil; submissions = []
        defer {
            if key == LoadKey(entity: selectedEntity, filter: selectedFilter, search: searchQuery) && !Task.isCancelled { loading = false }
        }
        do {
            async let counts = AdminAPI.fetchStatusCounts(entity: key.entity)
            async let rows = AdminAPI.fetchSubmissions(
                entity: key.entity,
                statusFilter: key.filter,
                searchQuery: key.search
            )
            let (newCounts, newRows) = try await (counts, rows)
            guard !Task.isCancelled, key == LoadKey(entity: selectedEntity, filter: selectedFilter, search: searchQuery) else { return }
            statusCounts = newCounts; submissions = newRows
        } catch {
            if !Task.isCancelled && key == LoadKey(entity: selectedEntity, filter: selectedFilter, search: searchQuery) { dashboardError = error.localizedDescription }
        }
    }
}

// MARK: - Components

struct StatCard: View {
    let value: Int
    let label: String

    var body: some View {
        // Label first, then the figure: the number is the thing to read, so it gets the
        // weight, and the card stays short enough for four to sit on one screen.
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.inkMuted)
            Text("\(value)")
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .webCard()
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
            .frame(minHeight: 44)
            .foregroundColor(isSelected ? .onPrimary : .ink)
            .background(isSelected ? Color.ink : Color.surface1, in: Capsule())
            .overlay(Capsule().stroke(isSelected ? Color.clear : Color.hairline, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: isSelected)
    }
}

// Dot-style status badge: a coloured dot plus label on a tinted capsule.
struct StatusBadge: View {
    let status: WholesalerStatus

    private var background: Color {
        switch status {
        case .pending: return .surface2
        case .on_hold: return .infoBg
        case .verified: return .successBg
        case .resubmission_required: return .warningBg
        case .rejected: return .dangerBg
        case .banned: return .ink
        }
    }

    private var foreground: Color {
        switch status {
        case .pending: return .ink
        case .on_hold: return .info
        case .verified: return .success
        case .resubmission_required: return .warning
        case .rejected: return .danger
        case .banned: return .onPrimary
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(foreground)
                .frame(width: 7, height: 7)
            Text(status.label)
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundColor(foreground)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(background, in: Capsule())
    }
}

private struct CompactSubmissionCard: View {
    let submission: Submission
    let entity: ReviewEntity
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Name and status on one line; the person and location sit under it.
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(submission.business_name ?? submission.displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.ink)
                    .lineLimit(1)
                Spacer(minLength: 8)
                StatusBadge(status: submission.status)
            }
            Text("\(submission.displayName) · \(submission.city ?? "—"), \(submission.state ?? "—")")
                .font(.system(size: 13))
                .foregroundColor(.inkMuted)
                .lineLimit(1)

            // Two equal-height buttons side by side: the primary action and the credits toggle.
            HStack(spacing: 8) {
                NavigationLink(value: ReviewRoute(entity: entity, id: submission.id)) {
                    Text(submission.status == .verified || submission.status == .banned ? "View documents" : "Review application")
                        .adminButtonChrome(primary: true)
                }
                .buttonStyle(.plain)

                Button {
                    expanded.toggle()
                } label: {
                    Text(expanded ? "Hide credits" : "Credits")
                        .adminButtonChrome()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(expanded ? "Hide credits and referrals" : "Credits and referrals")
                .accessibilityIdentifier("business-credits-toggle")
            }

            if expanded { BusinessCreditsAndReferrals(entity: entity, submission: submission) }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .webCard()
        .id("\(entity.rawValue):\(submission.id)")
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
                Divider().overlay(Color.hairlineSoft)
            }

            ForEach(Array(services.enumerated()), id: \.element.id) { index, service in
                if isCompact {
                    CompactServiceRow(service: service)
                } else {
                    HStack(spacing: 0) {
                        HStack(spacing: 12) {
                            ServiceInitialMark(initial: service.initial, size: 40)
                            Text(service.name)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.ink)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Text(service.description)
                            .font(.system(size: 14))
                            .foregroundColor(.inkMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        HStack {
                            ActiveTag()
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
                                .foregroundColor(.ink)
                                .frame(minHeight: 44, alignment: .leading)
                            }
                            .frame(width: 90, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                }

                if index < services.count - 1 {
                    Divider().overlay(Color.hairlineSoft)
                }
            }
        }
        .webCard()
    }

    private func headerCell(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .kerning(0.6)
            .foregroundColor(.inkSubtle)
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
                ServiceInitialMark(initial: service.initial, size: 40)
                Text(service.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.ink)
                Spacer(minLength: 8)
                ActiveTag()
            }

            Text(service.description)
                .font(.system(size: 14))
                .foregroundColor(.inkMuted)

            if let url = URL(string: service.url) {
                Link(destination: url) {
                    HStack(spacing: 6) {
                        Text("Open")
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.ink)
                    .frame(minHeight: 44, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}

// Charcoal circle carrying the service's initial.
private struct ServiceInitialMark: View {
    let initial: String
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(Color.ink)
            .frame(width: size, height: size)
            .overlay(
                Text(initial)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.onPrimary)
            )
    }
}

// Dot-style "Active" status tag, matching the verified badge colours.
private struct ActiveTag: View {
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.success)
                .frame(width: 7, height: 7)
            Text("Active")
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundColor(.success)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color.successBg, in: Capsule())
    }
}

#Preview {
    NavigationStack {
        AdminDashboardView()
    }
}

struct AdminReferralsView: View {
    var wholesalerID: String? = nil
    var retailerID: String? = nil
    var body: some View {
        ScrollView {
            BusinessReferralsView(wholesalerID: wholesalerID, retailerID: retailerID).padding()
        }.navigationTitle("Referrals").navigationBarTitleDisplayMode(.inline)
    }
}
