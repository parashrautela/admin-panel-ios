import SwiftUI

struct AdminProfileView: View {
    @EnvironmentObject private var auth: AdminAuth
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showingLogoutConfirmation = false

    private var isCompact: Bool { horizontalSizeClass == .compact }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    var body: some View {
        ZStack {
            Color.canvas
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    profileCard

                    if isCompact {
                        VStack(spacing: 16) {
                            sessionCard
                            appInformationCard
                        }
                    } else {
                        HStack(alignment: .top, spacing: 16) {
                            sessionCard
                            appInformationCard
                        }
                    }

                    securityNotice
                    logoutButton
                }
                .padding(.horizontal, isCompact ? 16 : 32)
                .padding(.top, 92)
                .padding(.bottom, 40)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }

            VStack {
                profileNavigationBar
                Spacer()
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .confirmationDialog(
            "Log out of Jewel India Admin?",
            isPresented: $showingLogoutConfirmation,
            titleVisibility: .visible
        ) {
            Button("Log Out", role: .destructive) {
                auth.logout()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will need the administrator password to sign in again.")
        }
    }

    private var profileNavigationBar: some View {
        HStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.ink)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            Text("Profile")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.ink)

            Spacer()

            Text("ADMIN")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Color.inkMuted)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.surface2, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: 900)
        .frame(maxWidth: .infinity)
        .background(Color.canvas.ignoresSafeArea(edges: .top))
    }

    private var profileCard: some View {
        HStack(spacing: isCompact ? 18 : 24) {
            Circle()
                .fill(Color.ink)
                .frame(width: isCompact ? 72 : 88, height: isCompact ? 72 : 88)
                .overlay {
                    Text("A")
                        .font(.system(size: isCompact ? 28 : 34, weight: .medium))
                        .foregroundStyle(Color.onPrimary)
                }

            VStack(alignment: .leading, spacing: 7) {
                Text("Admin User")
                    .font(.system(size: isCompact ? 24 : 28, weight: .medium))
                    .foregroundStyle(Color.ink)

                Text("Jewel India Administration")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.inkMuted)

                Label("Active session", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.success)
            }

            Spacer(minLength: 0)
        }
        .padding(isCompact ? 22 : 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .webCard()
    }

    private var sessionCard: some View {
        ProfileSectionCard(title: "Account & Access", icon: "person.badge.key.fill") {
            ProfileInfoRow(label: "Account", value: "Shared admin")
            Divider().overlay(Color.hairlineSoft)
            ProfileInfoRow(label: "Role", value: "Administrator")
            Divider().overlay(Color.hairlineSoft)
            ProfileInfoRow(label: "Authentication", value: "Session password")
        }
    }

    private var appInformationCard: some View {
        ProfileSectionCard(title: "App Information", icon: "iphone") {
            ProfileInfoRow(label: "Application", value: "Jewel India Admin")
            Divider().overlay(Color.hairlineSoft)
            ProfileInfoRow(label: "Version", value: appVersion)
            Divider().overlay(Color.hairlineSoft)
            ProfileInfoRow(label: "Build", value: buildNumber)
        }
    }

    private var securityNotice: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 22))
                .foregroundStyle(Color.warning)

            VStack(alignment: .leading, spacing: 6) {
                Text("Security upgrade pending")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.ink)

                Text("This app currently uses one shared admin session. Individual admin identities, roles and multi-factor authentication will appear here after the account system is connected.")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .background(Color.warningBg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.warning.opacity(0.2), lineWidth: 1)
        }
    }

    private var logoutButton: some View {
        Button {
            showingLogoutConfirmation = true
        } label: {
            Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.danger)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Color.surface1, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.hairline, lineWidth: 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Returns to the admin login screen")
    }
}

private struct ProfileSectionCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(title, systemImage: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.ink)

            VStack(spacing: 14) {
                content
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .webCard()
    }
}

private struct ProfileInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(Color.inkMuted)

            Spacer(minLength: 12)

            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.ink)
                .multilineTextAlignment(.trailing)
        }
    }
}

#Preview {
    NavigationStack {
        AdminProfileView()
            .environmentObject(AdminAuth())
    }
}
