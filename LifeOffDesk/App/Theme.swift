import SwiftUI

/// Brand tokens from docs/BRAND-GUIDE.md. Light theme only for the MVP.
enum Theme {
    static let canvas = Color(hex: 0xF8F6EF)
    static let ink = Color(hex: 0x283A31)
    static let primary = Color(hex: 0x46785B)
    static let secondaryInk = Color(hex: 0x69776D)
    static let surface = Color(hex: 0xFFFFFF)
    static let border = Color(hex: 0xD9DED4)
    static let danger = Color(hex: 0xA13D36)
    /// Revealed ground under the fog; a light tint of primary so explored area reads as "opened".
    static let revealedGround = Color(hex: 0xE6EDE2)

    static let corner: CGFloat = 20
    static let inset: CGFloat = 16
    static let minTarget: CGFloat = 44
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.canvas)
            .frame(maxWidth: .infinity, minHeight: Theme.minTarget)
            .padding(.vertical, 4)
            .background(Theme.primary.opacity(configuration.isPressed ? 0.8 : 1),
                        in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, minHeight: Theme.minTarget)
            .padding(.vertical, 4)
            .background(Theme.surface.opacity(configuration.isPressed ? 0.7 : 1),
                        in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).stroke(Theme.border))
    }
}

struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Theme.inset)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.border))
    }
}

extension View {
    func card() -> some View { modifier(CardBackground()) }
}
