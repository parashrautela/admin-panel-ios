import SwiftUI

// Login screen in the light Intercom style. Regular width shows the brand
// illustration beside the form inside one floating white card on the cream
// canvas; compact width drops the illustration and sits the form directly on
// the canvas (no room for a side-by-side split on iPhone).
struct AdminLoginView: View {
    @EnvironmentObject private var auth: AdminAuth
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var password = ""
    @State private var isPasswordVisible = false
    @State private var error = ""
    @State private var isLoggingIn = false
    @State private var page: BrowserPage?

    private var isCompact: Bool { horizontalSizeClass == .compact }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: isCompact ? 0 : 12, style: .continuous)
    }

    var body: some View {
        HStack(spacing: 0) {
            if !isCompact {
                illustrationPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Rectangle()
                    .fill(Color.hairline)
                    .frame(width: 1)
            }
            formPanel
                .frame(maxWidth: isCompact ? .infinity : 460, maxHeight: .infinity)
        }
        .background(isCompact ? Color.canvas : Color.surface1)
        .clipShape(cardShape)
        .overlay {
            if !isCompact {
                cardShape.stroke(Color.hairline, lineWidth: 1)
            }
        }
        .padding(isCompact ? 0 : 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.canvas)
        .ignoresSafeArea()
    }

    // MARK: - Illustration side (regular width only)

    private var illustrationPanel: some View {
        Color.surface1
            .overlay(
                Image("LoginIllustration")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(56)
            )
    }

    // MARK: - Form side

    private var formPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 32)

            brandBlock
                .padding(.horizontal, 32)

            Spacer(minLength: 40)

            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Admin Login")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(.ink)
                    Text("Enter password to access the admin panel")
                        .font(.system(size: 15))
                        .foregroundColor(.inkMuted)
                }

                VStack(alignment: .leading, spacing: 14) {
                    passwordField

                    if !error.isEmpty {
                        Text(error)
                            .font(.system(size: 14))
                            .foregroundColor(.danger)
                    }

                    loginButton
                }
            }
            .padding(.horizontal, 32)

            Spacer(minLength: 32)

            legalFooter
                .padding(.horizontal, 32)
                .padding(.bottom, 28)
        }
    }

    // MARK: - Brand mark

    private var brandBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            brandMark
            VStack(alignment: .leading, spacing: 2) {
                Text("Jewel India")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.ink)
                Text("Made for Moments That Matter")
                    .font(.system(size: 13))
                    .foregroundColor(.inkMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var brandMark: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.ink)
            .frame(width: 40, height: 40)
            .overlay(
                Text("JI")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.onPrimary)
            )
            .accessibilityHidden(true)
    }

    // MARK: - Terms, privacy, support

    /// Reachable before signing in, as App Review expects. The pages open
    /// over the app rather than in Safari.
    private var legalFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(agreement)
            Text(support)
        }
        .font(.system(size: 13))
        .foregroundColor(.inkMuted)
        // Links take the tint, not the run's own colour.
        .tint(.ink)
        .lineSpacing(4)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.openURL, OpenURLAction { url in
            page = BrowserPage(url: url)
            return .handled
        })
        .sheet(item: $page) { page in
            InAppBrowser(url: page.url).ignoresSafeArea()
        }
    }

    private var agreement: AttributedString {
        var text = AttributedString("By continuing, you agree to our ")
        text += link("Terms of Service", to: LegalLinks.terms)
        text += AttributedString(" and ")
        text += link("Privacy Policy", to: LegalLinks.privacy)
        return text
    }

    private var support: AttributedString {
        var text = AttributedString("Need help? ")
        text += link("Contact support", to: LegalLinks.support)
        return text
    }

    private func link(_ label: String, to url: URL) -> AttributedString {
        var part = AttributedString(label)
        part.link = url
        part.font = .system(size: 13, weight: .semibold)
        part.underlineStyle = .single
        return part
    }

    private var passwordField: some View {
        HStack(spacing: 8) {
            Group {
                if isPasswordVisible {
                    TextField("Enter Password", text: $password)
                } else {
                    SecureField("Enter Password", text: $password)
                }
            }
            .foregroundColor(.ink)
            .textContentType(.password)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .onSubmit(handleLogin)

            Button {
                isPasswordVisible.toggle()
            } label: {
                Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                    .foregroundColor(.inkSubtle)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.surface1, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.hairline, lineWidth: 1)
        )
    }

    private var loginButton: some View {
        Button(action: handleLogin) {
            Text(isLoggingIn ? "Checking..." : "Login")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.onPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
        }
        .buttonStyle(.plain)
        .background(Color.ink, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .opacity(isLoggingIn || password.isEmpty ? 0.55 : 1)
        .disabled(isLoggingIn || password.isEmpty)
    }

    // MARK: - Auth (unchanged from before the redesign)

    private func handleLogin() {
        guard !isLoggingIn else { return }
        isLoggingIn = true
        Task {
            do {
                if try await auth.login(password: password) {
                    error = ""
                } else {
                    error = "Incorrect password"
                }
            } catch {
                self.error = "Couldn't reach the server. Check your connection and try again."
            }
            isLoggingIn = false
        }
    }
}

#Preview {
    AdminLoginView()
        .environmentObject(AdminAuth())
}
