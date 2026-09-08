import SwiftUI

enum AdminTheme {
    static let accent = Color.indigo
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let background = Color(uiColor: .systemGroupedBackground)
}
extension WholesalerStatus {
    var tint: Color {
        switch self {
        case .pending: return .orange
        case .on_hold: return .purple
        case .verified: return .green
        case .resubmission_required: return .blue
        case .rejected, .banned: return .red
        case .unknown: return .secondary
        }
    }
}
struct StatusBadge: View {
    var status: WholesalerStatus
    var body: some View {
        Label(status.label, systemImage: status.symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(status.tint)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(status.tint.opacity(0.12), in: Capsule())
            .accessibilityLabel("Status: " + status.label)
    }
}
struct Panel<Content: View>: View {
    var title: String
    var symbol: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: symbol).font(.headline).accessibilityAddTraits(.isHeader)
            content
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(AdminTheme.surface, in: RoundedRectangle(cornerRadius: 20))
    }
}
struct ErrorPanel: View {
    let error: AdminAPIError
    var retry: (() -> Void)?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(error.title, systemImage: "exclamationmark.triangle.fill").font(.headline)
            Text(error.message).font(.subheadline)
            if let trace = error.traceID { Text("Support reference: " + trace).font(.caption).textSelection(.enabled) }
            if let retry { Button("Try again", action: retry).buttonStyle(.bordered).frame(minHeight: 44) }
        }
        .padding().frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .contain)
        .onAppear { UIAccessibility.post(notification: .announcement, argument: error.title + ". " + error.message) }
    }
}
struct EnvironmentBadge: View {
    var body: some View {
        Label(AppConfiguration.preview ? "Preview · sample data" : AppConfiguration.environment, systemImage: AppConfiguration.preview ? "testtube.2" : "lock.shield")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(AdminTheme.accent.opacity(0.1), in: Capsule())
    }
}
