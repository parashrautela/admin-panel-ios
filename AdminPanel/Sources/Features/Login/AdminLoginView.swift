import SwiftUI

struct AdminLoginView: View {
    @EnvironmentObject private var auth: AdminAuth
    @State private var email = ""
    @State private var password = ""
    @State private var code = ""
    @State private var visible = false
    @FocusState private var field: Field?
    enum Field { case email, password, code }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: "diamond.fill").font(.largeTitle).foregroundStyle(AdminTheme.accent).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Jewel India").font(.largeTitle.bold())
                    Text(auth.needsMFA ? "Verify your identity" : "Your review workspace").font(.title2.weight(.semibold))
                    Text(auth.needsMFA ? "Enter the six-digit code from your authenticator app." : "Sign in with your individual administrator account.").foregroundStyle(.secondary)
                }
                EnvironmentBadge()
                if let error = auth.error { ErrorPanel(error: error, retry: nil) }
                if auth.needsMFA {
                    if let secret = auth.enrollmentSecret {
                        Text("Set up your authenticator").font(.headline)
                        Text("Add a time-based account in your authenticator using this setup key, then enter its current code.").font(.subheadline)
                        Text(secret).font(.body.monospaced()).textSelection(.enabled).privacySensitive()
                    }
                    TextField("Authentication code", text: $code)
                        .textContentType(.oneTimeCode).keyboardType(.numberPad).focused($field, equals: .code)
                        .textFieldStyle(.roundedBorder).frame(minHeight: 44).accessibilityIdentifier("mfaCode")
                    Button { Task { await auth.verifyMFA(code: code) } } label: { loginLabel("Verify and continue") }
                        .buttonStyle(.borderedProminent).disabled(auth.busy || code.trimmed.count != 6)
                    Button("Cancel sign-in") { auth.reset(); password = ""; code = "" }.frame(minHeight: 44).disabled(auth.busy)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Work email").font(.headline)
                        TextField("name@company.com", text: $email)
                            .textContentType(.username).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .focused($field, equals: .email).textFieldStyle(.roundedBorder).frame(minHeight: 44)
                            .submitLabel(.next).onSubmit { field = .password }.accessibilityIdentifier("email")
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Password").font(.headline)
                        HStack {
                            Group {
                                if visible { TextField("Account password", text: $password) }
                                else { SecureField("Account password", text: $password) }
                            }
                            .textContentType(.password).focused($field, equals: .password).onSubmit(signIn)
                            .textFieldStyle(.roundedBorder).frame(minHeight: 44).accessibilityIdentifier("password")
                            Button { visible.toggle() } label: {
                                Image(systemName: visible ? "eye.slash" : "eye").frame(width: 44, height: 44)
                            }.accessibilityLabel(visible ? "Hide password" : "Show password")
                        }
                    }
                    Toggle("Save session on this device", isOn: $auth.remember).font(.subheadline)
                    Text("Saved sessions require Face ID, Touch ID, or the device passcode to reopen.").font(.caption).foregroundStyle(.secondary)
                    Button(action: signIn) { loginLabel("Sign in") }
                        .buttonStyle(.borderedProminent).disabled(auth.busy || email.trimmed.isEmpty || password.isEmpty)
                        .accessibilityIdentifier("signIn")
                    if auth.savedSession {
                        Button { Task { await auth.unlock() } } label: { Label("Unlock saved session", systemImage: "faceid").frame(minHeight: 44) }
                            .disabled(auth.busy)
                    }
                    Text("Need access or a password reset? Contact the person who manages your Jewel India administrator accounts.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(28).frame(maxWidth: 520)
            .background(AdminTheme.surface, in: RoundedRectangle(cornerRadius: 28))
            .padding(24).frame(maxWidth: .infinity)
        }
        .safeAreaPadding(.vertical, 30)
        .background(AdminTheme.background).tint(AdminTheme.accent)
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: password) { auth.error = nil }
        .onChange(of: email) { auth.error = nil }
    }
    private func loginLabel(_ label: String) -> some View {
        HStack { if auth.busy { ProgressView() }; Text(auth.busy ? "Please wait…" : label) }.frame(maxWidth: .infinity, minHeight: 44)
    }
    private func signIn() {
        guard !email.trimmed.isEmpty, !password.isEmpty else { return }
        field = nil
        Task { await auth.login(email: email, password: password); if auth.isAuthenticated || auth.needsMFA { password = "" } }
    }
}
