import SwiftUI

/// Full-bleed backdrop. Intercom uses a flat cream canvas with no decorative gradients or blobs,
/// so the admin uses the canvas colour. The type name is kept so existing screens still compile.
struct LiquidBackground: View {
    var body: some View {
        Color.canvas.ignoresSafeArea()
    }
}

#Preview {
    LiquidBackground()
}
