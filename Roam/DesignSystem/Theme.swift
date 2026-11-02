import SwiftUI
import UIKit

/// Roam design tokens: ink on Apple's neutral greys (the grouped background with white cards, as in Maps and
/// Settings). Photos and place-state colours are the only colour.
enum Roam {
    static let paper = dynamic(light: 0xF2F2F7, dark: 0x000000)
    static let paperRaised = dynamic(light: 0xFFFFFF, dark: 0x1C1C1E)
    static let ink = dynamic(light: 0x111111, dark: 0xF2F2F7)
    static let inkMuted = dynamic(light: 0x6C6C70, dark: 0x98989F)
    static let inkFaint = dynamic(light: 0x8E8E93, dark: 0x636366)
    static let rule = dynamic(light: 0xD1D1D6, dark: 0x38383A)
    static let fill = dynamic(light: 0xE5E5EA, dark: 0x2C2C2E)
    static let onInk = dynamic(light: 0xF2F2F7, dark: 0x000000)
    static let signal = dynamic(light: 0xB3261E, dark: 0xFF8A80)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? uiColor(dark) : uiColor(light) })
    }

    private static func uiColor(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// App-facing names for the Roam tokens. Sentiment is carried by icons and words, never colour.
enum Theme {
    static let accent = Roam.ink
    static let liked = Roam.ink
    static let fine = Roam.ink
    /// Errors and destructive actions; sentiment itself is drawn in ink.
    static let disliked = Roam.signal
    static let destructive = Roam.signal

    static let likedFill = Roam.fill
    static let fineFill = Roam.fill
    static let dislikedFill = Roam.fill

    static let secondaryText = Roam.inkMuted

    static let canvas = Roam.paper
    static let groupedCanvas = Roam.paper
    static let card = Roam.paperRaised
    static let raisedCard = Roam.paperRaised
    static let hairline = Roam.rule
    static let subtleFill = Roam.fill
    static let accentFill = Roam.fill
    static let wantAccent = Roam.ink

    static func color(for sentiment: Sentiment) -> Color { Roam.ink }

    static func fill(for sentiment: Sentiment) -> Color { Roam.fill }

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    static let cornerRadius: CGFloat = 16
    static let minimumHitTarget: CGFloat = 44
}

extension Font {
    /// Rounded display face used for place names and modal titles.
    static func roamDisplay(_ style: Font.TextStyle = .largeTitle) -> Font {
        .system(style, design: .rounded).weight(.bold)
    }

    static func roamTitle(_ style: Font.TextStyle = .title2) -> Font {
        .system(style, design: .rounded).weight(.bold)
    }
}

/// Primary filled call to action.
struct PrimaryButtonStyle: ButtonStyle {
    /// Destructive final actions pass `Theme.destructive`.
    var fill: Color = Roam.ink
    var compact = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: compact ? nil : .infinity, minHeight: 50)
            .padding(.horizontal, Theme.Spacing.xl)
            .foregroundStyle(isEnabled ? Roam.onInk : Roam.inkMuted)
            .background(Capsule().fill(isEnabled ? fill : Roam.fill))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .contentShape(Capsule())
    }
}

/// Outlined secondary action.
struct SecondaryButtonStyle: ButtonStyle {
    var compact = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: compact ? nil : .infinity, minHeight: 50)
            .padding(.horizontal, Theme.Spacing.xl)
            .foregroundStyle(isEnabled ? Roam.ink : Roam.inkFaint)
            .background(Capsule().fill(Roam.fill))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
    }
}

/// Compact pill used for chips and inline actions; keeps a 44-point hit target and never
/// truncates or wraps its label mid-word.
struct PillButtonStyle: ButtonStyle {
    var isSelected = false
    /// A place-state colour (planned blue, been-there green) for actions that move a place into that state.
    var tint: Color?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(isSelected ? (tint == nil ? Roam.onInk : .white) : (tint ?? Roam.ink))
            .background(Capsule().fill(isSelected ? (tint ?? Roam.ink) : (tint?.opacity(0.14) ?? Roam.fill)))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .frame(minHeight: Theme.minimumHitTarget)
            .contentShape(Rectangle())
    }
}

/// Icon + title for pills (a plain HStack; `Label` drops its title under fixed sizing).
struct PillLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
            Text(title)
        }
    }
}

extension View {
    /// Rounded card surface used across lists, sheets and detail sections.
    func roamCard(padding: CGFloat = Theme.Spacing.l) -> some View {
        self.padding(padding)
            .background(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).fill(Theme.raisedCard))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).strokeBorder(Theme.hairline))
    }
}

/// A quiet text action beneath a page's main button.
struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Roam.ink)
            .frame(maxWidth: .infinity, minHeight: Theme.minimumHitTarget)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

extension View {
    /// The shared look for every sheet: paper behind, with lists and forms showing through.
    func roamSheetStyle() -> some View {
        scrollContentBackground(.hidden)
            .background(Roam.paper)
            .presentationBackground(Roam.paper)
    }
}

/// A titled block of content. Every page section uses this, so headings and spacing match.
struct RoamSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text(title).font(.roamTitle(.title3)).foregroundStyle(Roam.ink).accessibilityAddTraits(.isHeader)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    /// Identifies a whole screen for UI tests without overwriting child identifiers
    /// (a bare identifier on a container propagates to every child).
    func screenIdentifier(_ identifier: String) -> some View {
        accessibilityElement(children: .contain).accessibilityIdentifier(identifier)
    }
}
