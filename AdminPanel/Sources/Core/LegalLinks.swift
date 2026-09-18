import SafariServices
import SwiftUI

/// The public pages the sign-in screen points at. App Review looks for these
/// to be reachable from inside the app, before signing in.
enum LegalLinks {
    static let terms = URL(string: "https://jewelindia.shop/terms-conditions")!
    static let privacy = URL(string: "https://jewelindia.shop/privacy-policy")!
    static let support = URL(string: "https://jewelindia.shop/support")!
}

/// A page opened over the app rather than in Safari.
struct InAppBrowser: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.dismissButtonStyle = .close
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

struct BrowserPage: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
