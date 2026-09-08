import SwiftUI

/// A separate, non-key window also covers presented document and decision sheets.
struct PrivacyCurtain: UIViewRepresentable {
    func makeUIView(context: Context) -> AttachmentView {
        let view = AttachmentView()
        view.attach = { [weak coordinator = context.coordinator] window in coordinator?.attach(to: window) }
        return view
    }
    func updateUIView(_ uiView: AttachmentView, context: Context) { }
    func makeCoordinator() -> Coordinator { Coordinator() }
    static func dismantleUIView(_ uiView: AttachmentView, coordinator: Coordinator) { coordinator.stop() }
    final class AttachmentView: UIView {
        var attach: ((UIWindow?) -> Void)?
        override func didMoveToWindow() { super.didMoveToWindow(); attach?(window) }
    }
    @MainActor final class Coordinator {
        private var curtain: UIWindow?
        private var observers: [NSObjectProtocol] = []
        private var inactive = false
        func attach(to source: UIWindow?) {
            guard let scene = source?.windowScene, curtain == nil else { return }
            let window = UIWindow(windowScene: scene)
            window.windowLevel = .alert + 1
            window.rootViewController = UIHostingController(rootView:
                ZStack {
                    Color(uiColor: .systemBackground).ignoresSafeArea()
                    VStack(spacing: 16) {
                        Image(systemName: "lock.shield.fill").font(.largeTitle)
                        Text("Jewel India").font(.title.bold())
                        Text("Sensitive workspace hidden while inactive or sharing your screen.").multilineTextAlignment(.center).foregroundStyle(.secondary)
                    }.padding(36)
                }.accessibilityAddTraits(.isModal))
            curtain = window
            inactive = UIApplication.shared.applicationState != .active
            let center = NotificationCenter.default
            observers = [
                center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.inactive = true; self?.update() } },
                center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.inactive = false; self?.update() } },
                center.addObserver(forName: UIScreen.capturedDidChangeNotification, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.update() } }
            ]
            update()
        }
        private func update() {
            guard let curtain else { return }
            curtain.isHidden = !(inactive || curtain.windowScene?.screen.isCaptured == true)
        }
        func stop() { observers.forEach(NotificationCenter.default.removeObserver); observers = []; curtain?.isHidden = true; curtain = nil }
    }
}
