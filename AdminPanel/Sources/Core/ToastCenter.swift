import SwiftUI
import Combine

// Lightweight stand-in for the web app's sonner toasts.
@MainActor
final class ToastCenter: ObservableObject {
    struct Toast: Equatable {
        let text: String
        let isError: Bool
    }

    @Published var toast: Toast?
    private var dismissTask: Task<Void, Never>?

    func show(_ text: String, isError: Bool = false) {
        dismissTask?.cancel()
        toast = Toast(text: text, isError: isError)
        dismissTask = Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            toast = nil
        }
    }
}

struct ToastView: View {
    let toast: ToastCenter.Toast

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .foregroundColor(toast.isError ? Color(hex: 0xFF8A8A) : .onPrimary)
            Text(toast.text)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.onPrimary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .background(Capsule().fill(Color.ink))
        .padding(.bottom, 28)
    }
}
