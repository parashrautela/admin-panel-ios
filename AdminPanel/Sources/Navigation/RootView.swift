import SwiftUI
import Combine

struct RootView: View {
    @StateObject private var auth = AdminAuth()
    @Environment(\.scenePhase) private var scenePhase
    @State private var backgroundTime: Date?
    @State private var captured = UIScreen.main.isCaptured
    var body: some View {
        Group {
            if auth.isAuthenticated { AdminDashboardView().id(auth.profile?.id) }
            else { AdminLoginView() }
        }
        .environmentObject(auth).tint(AdminTheme.accent)
        .privacySensitive()
        .background(PrivacyCurtain().frame(width: 0, height: 0))
        .overlay {
            if scenePhase != .active || captured {
                ZStack {
                    AdminTheme.background.ignoresSafeArea()
                    VStack(spacing: 16) {
                        Image(systemName: "lock.shield.fill").font(.largeTitle)
                        Text(captured ? "Screen sharing paused" : "Jewel India").font(.title2.bold())
                        Text(captured ? "Stop screen recording or sharing to view sensitive information." : "Your review workspace is protected.").foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.padding(32)
                }.accessibilityAddTraits(.isModal)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .adminSessionExpired)) { _ in
            auth.reset()
            auth.error = AdminAPIError(code: "unauthorized", message: "Your session expired or was revoked. Sign in to continue.")
        }
        .onReceive(NotificationCenter.default.publisher(for: UIScreen.capturedDidChangeNotification)) { _ in captured = UIScreen.main.isCaptured }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { backgroundTime = Date() }
            if phase == .active {
                if let time = backgroundTime, Date().timeIntervalSince(time) > 900, !AppConfiguration.preview { auth.reset(removeSaved: false) }
                backgroundTime = nil
            }
        }
    }
}
