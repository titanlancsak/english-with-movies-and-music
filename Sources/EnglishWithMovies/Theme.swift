import SwiftUI

/// The app's look: a deep dark background lit by soft glows in the icon's colors
/// (indigo, violet, orange), translucent "glass" panels and gradient accents.
/// The Windows/Android version uses the same values (app-flutter/lib/ui/theme.dart).
enum Theme {
    static let background = Color(red: 0.035, green: 0.035, blue: 0.063)   // #09090F
    static let surface = Color.white.opacity(0.055)
    static let surfaceHover = Color.white.opacity(0.09)
    static let stroke = Color.white.opacity(0.09)
    static let textDim = Color.white.opacity(0.55)

    static let indigo = Color(red: 0.388, green: 0.400, blue: 0.945)       // #6366F1
    static let violet = Color(red: 0.659, green: 0.333, blue: 0.969)       // #A855F7
    static let orange = Color(red: 0.976, green: 0.451, blue: 0.086)       // #F97316
    static let pink = Color(red: 0.925, green: 0.282, blue: 0.600)         // #EC4899

    /// Buttons, highlights, the current word.
    static let brand = LinearGradient(colors: [indigo, violet], startPoint: .topLeading, endPoint: .bottomTrailing)
    /// Titles and "special" accents.
    static let warm = LinearGradient(colors: [violet, pink, orange], startPoint: .leading, endPoint: .trailing)

    static let corner: CGFloat = 16
}

/// The window background: dark, with three blurred glows.
struct AuroraBackground: View {
    var body: some View {
        ZStack {
            Theme.background
            GeometryReader { geometry in
                let size = geometry.size
                Circle()
                    .fill(Theme.indigo.opacity(0.32))
                    .frame(width: size.width * 0.7)
                    .blur(radius: 120)
                    .offset(x: -size.width * 0.25, y: -size.height * 0.35)
                Circle()
                    .fill(Theme.violet.opacity(0.22))
                    .frame(width: size.width * 0.55)
                    .blur(radius: 130)
                    .offset(x: size.width * 0.55, y: -size.height * 0.15)
                Circle()
                    .fill(Theme.orange.opacity(0.12))
                    .frame(width: size.width * 0.5)
                    .blur(radius: 140)
                    .offset(x: size.width * 0.2, y: size.height * 0.65)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

extension View {
    /// A translucent rounded panel with a hairline border.
    func glassCard(cornerRadius: CGFloat = Theme.corner, highlighted: Bool = false) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(highlighted ? Theme.surfaceHover : Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 1)
        )
    }

    /// Text filled with a gradient.
    func gradientForeground(_ gradient: LinearGradient = Theme.warm) -> some View {
        overlay(gradient).mask(self)
    }
}

/// Main action: gradient capsule.
struct PrimaryButtonStyle: ButtonStyle {
    var gradient: LinearGradient = Theme.brand
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .foregroundStyle(.white)
            .background(Capsule().fill(gradient))
            .shadow(color: Theme.violet.opacity(isEnabled ? 0.45 : 0), radius: 12, y: 4)
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Secondary action: glass capsule.
struct GlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverBody(configuration: configuration) { label, highlighted, isEnabled in
            label
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .foregroundStyle(.white.opacity(isEnabled ? 0.92 : 0.4))
                .background(Capsule().fill(highlighted ? Theme.surfaceHover : Theme.surface))
                .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
        }
    }
}

/// Round icon button on glass.
struct IconButtonStyle: ButtonStyle {
    var size: CGFloat = 32
    var tint: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        HoverBody(configuration: configuration) { label, highlighted, isEnabled in
            label
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(tint.opacity(isEnabled ? 1 : 0.35))
                .frame(width: size, height: size)
                .background(Circle().fill(highlighted ? Theme.surfaceHover : Theme.surface))
                .overlay(Circle().strokeBorder(Theme.stroke, lineWidth: 1))
        }
    }
}

/// Tracks hover for a button style (styles cannot hold state themselves).
private struct HoverBody<Content: View>: View {
    let configuration: ButtonStyleConfiguration
    let content: (ButtonStyleConfiguration.Label, Bool, Bool) -> Content
    @Environment(\.isEnabled) private var isEnabled
    @ViewState private var isHovered = false

    var body: some View {
        content(configuration.label, isHovered || configuration.isPressed, isEnabled)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Small rounded label, e.g. "noun", "CC", "3 para revisar".
struct Chip: View {
    let text: String
    var systemImage: String?
    var color: Color = .white

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage) }
            Text(text)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.14)))
    }
}

/// Small uppercase title above a section.
struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(1.4)
            .foregroundStyle(Theme.textDim)
    }
}
