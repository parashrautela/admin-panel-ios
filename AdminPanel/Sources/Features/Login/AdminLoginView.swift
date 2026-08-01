import SwiftUI

// Mirrors the web AdminProtected login card.
struct AdminLoginView: View {
    @EnvironmentObject private var auth: AdminAuth
    @State private var password = ""
    @State private var error = ""

    var body: some View {
        ZStack {
            LiquidBackground()

            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    Text("Admin Login")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.gray900)
                    Text("Enter password to access the admin panel")
                        .font(.system(size: 14))
                        .foregroundColor(.gray500)
                }
                .padding(.bottom, 32)

                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Password")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.gray700)

                        SecureField("Enter admin password", text: $password)
                            .textContentType(.password)
                            .padding(14)
                            .glassEffect(
                                .regular.tint(.white.opacity(0.5)),
                                in: RoundedRectangle(cornerRadius: 10)
                            )
                            .onSubmit(handleLogin)
                    }

                    if !error.isEmpty {
                        Text(error)
                            .font(.system(size: 14))
                            .foregroundColor(.red500)
                    }

                    Button(action: handleLogin) {
                        Text("Login")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.blue600)
                }
            }
            .padding(32)
            .frame(maxWidth: 448)
            .glassEffect(
                .regular.tint(.white.opacity(0.4)),
                in: RoundedRectangle(cornerRadius: 24)
            )
            .padding(16)
        }
    }

    private func handleLogin() {
        if auth.login(password: password) {
            error = ""
        } else {
            error = "Incorrect password"
        }
    }
}

#Preview {
    AdminLoginView()
        .environmentObject(AdminAuth())
}
