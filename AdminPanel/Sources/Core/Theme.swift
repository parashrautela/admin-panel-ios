import SwiftUI

// Tailwind palette used by the web admin panel, mapped 1:1 so screens match.
extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }

    static let gray50 = Color(hex: 0xF9FAFB)
    static let gray100 = Color(hex: 0xF3F4F6)
    static let gray200 = Color(hex: 0xE5E7EB)
    static let gray300 = Color(hex: 0xD1D5DB)
    static let gray400 = Color(hex: 0x9CA3AF)
    static let gray500 = Color(hex: 0x6B7280)
    static let gray600 = Color(hex: 0x4B5563)
    static let gray700 = Color(hex: 0x374151)
    static let gray900 = Color(hex: 0x111827)

    static let blue100 = Color(hex: 0xDBEAFE)
    static let blue600 = Color(hex: 0x2563EB)
    static let blue700 = Color(hex: 0x1D4ED8)
    static let blue900 = Color(hex: 0x1E3A8A)

    static let yellow100 = Color(hex: 0xFEF9C3)
    static let yellow900 = Color(hex: 0x713F12)

    static let red100 = Color(hex: 0xFEE2E2)
    static let red500 = Color(hex: 0xEF4444)
    static let red900 = Color(hex: 0x7F1D1D)

    // Dark navy login panel (Figma redesign, 2026-09-10). Approximated from
    // a PNG export, not exact design tokens — nudge these if the real
    // Figma file becomes reachable later.
    static let loginNavyTop = Color(hex: 0x090C16)
    static let loginNavyBottom = Color(hex: 0x1B3D74)
    static let loginMutedText = Color(hex: 0xA7B0C4)
    static let loginButtonFill = Color(hex: 0x8B93A6)
}

// Card container matching the web's `rounded-lg shadow-sm border border-gray-100`.
struct WebCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray100, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

extension View {
    func webCard() -> some View { modifier(WebCard()) }
}
