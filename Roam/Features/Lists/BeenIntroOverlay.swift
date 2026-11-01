import SwiftUI

/// One-time teaching card for the Been list after setup, followed by a Log coachmark.
struct BeenIntroCard: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            ZStack {
                RoundedRectangle(cornerRadius: 18).fill(Theme.accentFill).frame(width: 150, height: 150)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array([("1", 92), ("2", 84), ("3", 67)].enumerated()), id: \.offset) { _, row in
                        HStack(spacing: 8) {
                            Text(row.0).font(.headline.monospacedDigit())
                            Capsule().fill(Theme.accent.opacity(0.35)).frame(width: 46, height: 8)
                            Text(Score(tenths: row.1).formatted).font(.caption.bold()).foregroundStyle(Theme.liked)
                        }
                    }
                }
            }
            .accessibilityHidden(true)
            Text("Welcome to My Places").font(.roamDisplay(.title)).accessibilityAddTraits(.isHeader)
            Text("Keep your wishlist, the places you've been and your trips together here.")
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.secondaryText)
            Button("Let's go", action: onContinue)
                .buttonStyle(PrimaryButtonStyle(compact: true))
                .accessibilityIdentifier("been-intro-continue")
        }
        .padding(Theme.Spacing.xl)
        .background(RoundedRectangle(cornerRadius: 24).fill(Theme.raisedCard))
        .padding(Theme.Spacing.xl)
        .screenIdentifier("been-intro")
    }
}

/// Points at Search: find a place, then Log it.
struct LogCoachmark: View {
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(Roam.onInk).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Log your first place").font(.headline).foregroundStyle(Roam.onInk)
                Text("Tap + Log a place and find somewhere you've been.").font(.subheadline).foregroundStyle(Roam.onInk)
            }
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark").font(.footnote.bold()).foregroundStyle(Roam.onInk).frame(width: 44, height: 44)
            }
            .accessibilityLabel("Dismiss tip")
        }
        .padding(Theme.Spacing.m)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.accent))
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.bottom, Theme.Spacing.s)
        .screenIdentifier("log-coachmark")
    }
}
