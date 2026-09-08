import SwiftUI

struct SystemView: View {
    @State private var services: [IntegrationHealth] = []
    @State private var error: AdminAPIError?
    @State private var loading = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                EnvironmentBadge()
                Text("Service status").font(.largeTitle.bold())
                Text("Health is reported by the server. A missing or stale check remains unknown.").foregroundStyle(.secondary)
                if let error { ErrorPanel(error: error) { Task { await load() } } }
                if loading { ProgressView("Checking services…") }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260))], spacing: 16) {
                    ForEach(services) { service in
                        Panel(title: service.name, symbol: "server.rack") {
                            Label(displayStatus(service), systemImage: displayStatus(service) == "Operational" ? "checkmark.circle" : "questionmark.circle")
                                .font(.headline).foregroundStyle(displayStatus(service) == "Operational" ? .green : .secondary)
                            Text(service.detail).font(.subheadline)
                            Text(service.environment).font(.caption.weight(.semibold))
                            Text("Last checked: " + Submission.timeText(service.checked_at)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }.padding(24).frame(maxWidth: 1100).frame(maxWidth: .infinity)
        }.background(AdminTheme.background).navigationTitle("System")
            .task { await load() }.refreshable { await load() }
            .toolbar { Button { Task { await load() } } label: { Label("Refresh services", systemImage: "arrow.clockwise") } }
    }
    private func displayStatus(_ service: IntegrationHealth) -> String {
        guard let checked = Submission.date(service.checked_at), Date().timeIntervalSince(checked) < 300 else { return "Unknown" }
        return service.status == "healthy" ? "Operational" : service.status.capitalized
    }
    private func load() async {
        guard !loading else { return }
        loading = true; error = nil
        defer { loading = false }
        do { services = try await AdminAPI.shared.health() }
        catch { self.error = AdminAPIError.map(error); services = [] }
    }
}
struct AccountView: View {
    @EnvironmentObject private var auth: AdminAuth
    @State private var confirmLogout = false
    var body: some View {
        Form {
            Section("Administrator") {
                Label(auth.profile?.display_name ?? "Administrator", systemImage: "person.crop.circle.fill").font(.headline)
                LabeledContent("Role", value: auth.profile?.role.capitalized ?? "Unknown")
                EnvironmentBadge()
            }
            Section("Privacy and security") {
                Label("Individual account with server-checked permissions", systemImage: "lock.shield")
                Label("Sensitive details are masked by default", systemImage: "eye.slash")
                Label("Background previews are protected", systemImage: "rectangle.on.rectangle.slash")
                Text("The workspace locks after 15 minutes in the background. Screenshots cannot be reliably prevented by iOS; handle identity documents only in approved settings.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Support") {
                Text("For access, password resets, or an account lockout, contact your organization's Jewel India administrator. Include the support reference shown with an error, never applicant documents.")
            }
            Section {
                Button("Sign out", role: .destructive) { confirmLogout = true }.frame(minHeight: 44).disabled(auth.busy).accessibilityIdentifier("signOut")
            }
        }.navigationTitle("Account")
            .confirmationDialog("Sign out on this device?", isPresented: $confirmLogout, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { Task { await auth.logout() } }
            } message: { Text("Saved session credentials and open sensitive content will be cleared.") }
    }
}
