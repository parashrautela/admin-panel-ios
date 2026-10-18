import SwiftUI

// Intercom-inspired admin palette (see DESIGN.md in the web admin repo).
// Cream canvas, white floating cards, charcoal primary, hairline borders, no shadows.
// Fin Orange is the Fin AI brand colour and is deliberately not used here.
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

    // Surfaces
    static let canvas = Color(hex: 0xF5F1EC)
    static let surface1 = Color(hex: 0xFFFFFF)
    static let surface2 = Color(hex: 0xEBE7E1)
    static let hairline = Color(hex: 0xD3CEC6)
    static let hairlineSoft = Color(hex: 0xEBE7E1)

    // Text
    static let ink = Color(hex: 0x111111)
    static let inkMuted = Color(hex: 0x626260)
    static let inkSubtle = Color(hex: 0x7B7B78)
    static let inkTertiary = Color(hex: 0x9C9FA5)
    static let onPrimary = Color(hex: 0xFFFFFF)

    // Status (text uses darker derivations of the report palette for contrast)
    static let success = Color(hex: 0x0A7A33)
    static let successBg = Color(hex: 0xE7F8EC)
    static let warning = Color(hex: 0x8A5A00)
    static let warningBg = Color(hex: 0xFDF3DC)
    static let danger = Color(hex: 0xC41C1C)
    static let dangerBg = Color(hex: 0xFBE9E9)
    static let info = Color(hex: 0x0B4FA3)
    static let infoBg = Color(hex: 0xE6F1FF)

    // Legacy names used by existing screens. Prefer the Intercom names above in new code.
    static let gray50 = surface1
    static let gray100 = hairlineSoft
    static let gray200 = hairline
    static let gray300 = hairline
    static let gray400 = inkTertiary
    static let gray500 = inkSubtle
    static let gray600 = inkMuted
    static let gray700 = inkMuted
    static let gray900 = ink
    static let blue100 = infoBg
    static let blue900 = info
    static let yellow100 = warningBg
    static let yellow900 = warning
    static let red100 = dangerBg
    static let red500 = danger
    static let red900 = danger

    // Login tokens. The navy login is being replaced by the light Intercom login.
    static let loginNavyTop = Color(hex: 0x090C16)
    static let loginNavyBottom = Color(hex: 0x1B3D74)
    static let loginMutedText = Color(hex: 0xA7B0C4)
    static let loginButtonFill = Color(hex: 0x8B93A6)
}

// Floating white card: 12pt radius, hairline border, no shadow.
struct WebCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.surface1)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.hairline, lineWidth: 1)
            )
    }
}

extension View {
    func webCard() -> some View { modifier(WebCard()) }
}

// Button chrome shared by the admin screens: one 44pt height, an 8pt radius (DESIGN.md
// rounded.md), and a single weight. Primary is charcoal; secondary is white with a hairline.
struct AdminButtonChrome: ViewModifier {
    var primary: Bool

    func body(content: Content) -> some View {
        content
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(primary ? .onPrimary : .ink)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(primary ? Color.ink : Color.surface1, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                if !primary {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.hairline, lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
    }
}

extension View {
    func adminButtonChrome(primary: Bool = false) -> some View { modifier(AdminButtonChrome(primary: primary)) }
}
