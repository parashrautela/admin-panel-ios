import SwiftUI

// Split login screen from the 2026-09-10 Figma redesign: a brand
// illustration beside a dark navy panel on regular width, illustration
// dropped on compact width (no room for a side-by-side split on iPhone).
struct AdminLoginView: View {
    @EnvironmentObject private var auth: AdminAuth
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var password = ""
    @State private var isPasswordVisible = false
    @State private var error = ""
    @State private var isLoggingIn = false

    private var isCompact: Bool { horizontalSizeClass == .compact }

    var body: some View {
        HStack(spacing: 0) {
            if !isCompact {
                illustrationPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            formPanel
                .frame(maxWidth: isCompact ? .infinity : 460, maxHeight: .infinity)
        }
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: isCompact ? 0 : 28,
                bottomLeadingRadius: isCompact ? 0 : 28,
                bottomTrailingRadius: isCompact ? 0 : 28,
                topTrailingRadius: isCompact ? 0 : 28
            )
        )
        .padding(isCompact ? 0 : 16)
        .background(Color.gray50)
        .ignoresSafeArea()
    }

    // MARK: - Illustration side (regular width only)

    private var illustrationPanel: some View {
        Color.white
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

            VStack(spacing: 6) {
                Text("Jewel India")
                    .font(.system(size: 30, weight: .regular, design: .serif))
                    .foregroundColor(.white)
                Text("Made for Moments That Matter")
                    .font(.system(size: 13))
                    .tracking(0.5)
                    .foregroundColor(.loginMutedText)
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: 40)

            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Welcome back")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.white)
                    Text("Enter password to access the admin panel")
                        .font(.system(size: 15))
                        .foregroundColor(.loginMutedText)
                }

                VStack(alignment: .leading, spacing: 14) {
                    passwordField

                    if !error.isEmpty {
                        Text(error)
                            .font(.system(size: 14))
                            .foregroundColor(.red500)
                    }

                    loginButton
                }
            }
            .padding(.horizontal, 32)

            Spacer(minLength: 32)
            Spacer(minLength: 32)
        }
        .background(
            LinearGradient(
                colors: [.loginNavyTop, .loginNavyBottom],
                startPoint: .top,
                endPoint: .bottom
            )
        )
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
            .textContentType(.password)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .onSubmit(handleLogin)

            Button {
                isPasswordVisible.toggle()
            } label: {
                Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                    .foregroundColor(.gray500)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
    }

    private var loginButton: some View {
        Button(action: handleLogin) {
            Text(isLoggingIn ? "Checking..." : "Login")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        }
        .buttonStyle(.plain)
        .background(Color.loginButtonFill, in: RoundedRectangle(cornerRadius: 14))
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
