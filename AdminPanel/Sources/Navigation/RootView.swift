import SwiftUI

struct RootView: View {
    @StateObject private var auth = AdminAuth()
    @StateObject private var toast = ToastCenter()

    var body: some View {
        Group {
            if auth.isAuthenticated {
                NavigationStack {
                    AdminDashboardView()
                        .navigationDestination(for: ReviewRoute.self) { route in
                            WholesalerReviewView(entity: route.entity, submissionId: route.id)
                        }
                }
            } else {
                AdminLoginView()
            }
        }
        .environmentObject(auth)
        .environmentObject(toast)
        .overlay(alignment: .bottom) {
            if let current = toast.toast {
                ToastView(toast: current)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: toast.toast)
    }
}

#Preview {
    RootView()
}
