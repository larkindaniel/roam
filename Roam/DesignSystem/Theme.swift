import SwiftUI
import UIKit

/// Roam visual tokens: system typography, an accessible teal accent and sentiment colours
/// that are always paired with icons or text.
enum Theme {
    static let accent = Color.accentColor

    // Light-mode sentiment text reaches at least 5.4:1 on its own fill and on white (M8 audit).
    static let liked = dynamic(light: UIColor(red: 0.08, green: 0.42, blue: 0.23, alpha: 1), dark: UIColor(red: 0.42, green: 0.82, blue: 0.56, alpha: 1))
    static let fine = dynamic(light: UIColor(red: 0.52, green: 0.33, blue: 0.00, alpha: 1), dark: UIColor(red: 0.96, green: 0.76, blue: 0.33, alpha: 1))
    static let disliked = dynamic(light: UIColor(red: 0.66, green: 0.15, blue: 0.13, alpha: 1), dark: UIColor(red: 0.98, green: 0.52, blue: 0.47, alpha: 1))

    static let likedFill = dynamic(light: UIColor(red: 0.85, green: 0.94, blue: 0.88, alpha: 1), dark: UIColor(red: 0.13, green: 0.27, blue: 0.18, alpha: 1))
    static let fineFill = dynamic(light: UIColor(red: 0.99, green: 0.93, blue: 0.78, alpha: 1), dark: UIColor(red: 0.30, green: 0.24, blue: 0.10, alpha: 1))
    static let dislikedFill = dynamic(light: UIColor(red: 0.98, green: 0.87, blue: 0.85, alpha: 1), dark: UIColor(red: 0.33, green: 0.14, blue: 0.13, alpha: 1))

    /// Secondary text. The system secondary label gray is about 3.5:1 on white, below the 4.5:1
    /// that small text needs (M8 audit); this reaches about 6.3:1 on white and 5.7:1 on grouped canvas.
    static let secondaryText = dynamic(light: UIColor(red: 0.37, green: 0.37, blue: 0.39, alpha: 1),
                                       dark: UIColor(red: 0.70, green: 0.70, blue: 0.73, alpha: 1))

    static let canvas = Color(uiColor: .systemBackground)
    static let groupedCanvas = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let raisedCard = Color(uiColor: .systemBackground)
    static let hairline = Color(uiColor: .separator)
    static let subtleFill = Color(uiColor: .tertiarySystemFill)
    static let accentFill = dynamic(light: UIColor(red: 0.88, green: 0.95, blue: 0.94, alpha: 1), dark: UIColor(red: 0.08, green: 0.24, blue: 0.23, alpha: 1))
    static let wantAccent = dynamic(light: UIColor(red: 0.23, green: 0.33, blue: 0.62, alpha: 1), dark: UIColor(red: 0.62, green: 0.71, blue: 0.98, alpha: 1))

    static func color(for sentiment: Sentiment) -> Color {
        switch sentiment {
        case .liked: return liked
        case .fine: return fine
        case .disliked: return disliked
        }
    }

    static func fill(for sentiment: Sentiment) -> Color {
        switch sentiment {
        case .liked: return likedFill
        case .fine: return fineFill
        case .disliked: return dislikedFill
        }
    }

    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    static let cornerRadius: CGFloat = 14
    static let minimumHitTarget: CGFloat = 44
}

extension Font {
    /// Large serif heading used for place names and modal titles (system New York).
    static func roamDisplay(_ style: Font.TextStyle = .largeTitle) -> Font {
        .system(style, design: .serif).weight(.bold)
    }

    static func roamTitle(_ style: Font.TextStyle = .title2) -> Font {
        .system(style, design: .serif).weight(.semibold)
    }
}

/// Primary filled call to action.
struct PrimaryButtonStyle: ButtonStyle {
    /// Destructive final actions pass `Theme.disliked`.
    var fill: Color = Theme.accent
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.horizontal, Theme.Spacing.l)
            .foregroundStyle(.white)
            .background(Capsule().fill(isEnabled ? fill : Color.gray.opacity(0.45)))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .contentShape(Capsule())
    }
}

/// Outlined secondary action.
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.horizontal, Theme.Spacing.l)
            .foregroundStyle(isEnabled ? Theme.accent : .secondary)
            .background(Capsule().strokeBorder(isEnabled ? Theme.accent : Color.gray.opacity(0.4), lineWidth: 1.5))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
    }
}

/// Compact pill used for chips and inline actions; keeps a 44-point hit target and never
/// truncates or wraps its label mid-word.
struct PillButtonStyle: ButtonStyle {
    var isSelected = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(isSelected ? Color.white : Theme.accent)
            .background(Capsule().fill(isSelected ? Theme.accent : Theme.accentFill))
            .overlay(Capsule().strokeBorder(Theme.accent.opacity(isSelected ? 0 : 0.25)))
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
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).strokeBorder(Theme.hairline.opacity(0.5)))
    }
}

extension View {
    /// Identifies a whole screen for UI tests without overwriting child identifiers
    /// (a bare identifier on a container propagates to every child).
    func screenIdentifier(_ identifier: String) -> some View {
        accessibilityElement(children: .contain).accessibilityIdentifier(identifier)
    }
}
