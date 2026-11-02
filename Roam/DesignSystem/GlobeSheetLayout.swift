import SwiftUI

/// How far a card comes up over the globe.
enum GlobeSheetDetent: CaseIterable {
    case peek
    case half
    case full

    func height(in available: CGFloat, peek: CGFloat) -> CGFloat {
        switch self {
        case .peek: return peek
        case .half: return available * 0.5
        case .full: return available
        }
    }
}

/// A globe filling the screen behind a card that drags between peeking, half and full. Tapping the card's
/// header swaps between half and full; while it peeks only the header shows. Used by My Places.
struct GlobeSheetLayout<Globe: View, Header: View, Content: View>: View {
    @Binding var detent: GlobeSheetDetent
    var peekHeight: CGFloat = 112
    /// How much the floating tab bar covers the bottom of the screen, home indicator included (about 86 points
    /// on iOS 26, measured on the iPhone 17 simulator); 0 where the tab bar is hidden. The card always runs down
    /// behind the tab bar to the bottom of the screen; it never stops short above it.
    var bottomOverlap: CGFloat = 86
    var headerLabel: String
    var headerIdentifier: String
    var onRefresh: () async -> Void = {}
    /// Minimised, the card becomes a floating bubble over the map instead of a strip along the bottom.
    var floatsWhenPeeking = false
    /// A control that sits on the map just above the card, at the left; hidden once the card fills the screen.
    var mapAccessory: AnyView? = nil
    @ViewBuilder var globe: () -> Globe
    @ViewBuilder var header: () -> Header
    @ViewBuilder var content: () -> Content

    @GestureState private var dragOffset: CGFloat = 0
    @State private var headerHeight: CGFloat?
    @State private var snapping = false
    @State private var contentScrolled = false

    /// Minimised, the card is just its header, sitting on the tab bar.
    private var peek: CGFloat { headerHeight.map { $0 + bottomOverlap } ?? peekHeight }

    var body: some View {
        GeometryReader { proxy in
            let available = proxy.size.height
            let peekHeight = peek
            // Fully up, the card stops below the floating buttons at the top of the screen.
            let top = available - Self.topClearance
            let height = min(max(min(detent.height(in: available, peek: peekHeight), top) - dragOffset, peekHeight), top)
            let floating = isFloating
            ZStack(alignment: .bottom) {
                // The card floats with a margin all round, so the map fills the whole screen behind it.
                globe().ignoresSafeArea()
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    if let mapAccessory, detent != .full {
                        mapAccessory
                            .padding(.leading, Theme.Spacing.l)
                            .transition(.opacity)
                    }
                    card(height: height, available: available)
                }
            }
            .frame(width: proxy.size.width, height: available, alignment: .bottom)
        }
        .background(Color.black.ignoresSafeArea())
        // With no tab bar below, the card runs down to the bottom of the screen.
        .ignoresSafeArea(edges: .bottom)
    }

    /// The rounding of current iPhone screens (about 62 points on the iPhone 17 and 16 Pro).
    private let displayCornerRadius: CGFloat = 62
    private static var topClearance: CGFloat { 26 }

    private var isFloating: Bool { floatsWhenPeeking && detent == .peek && dragOffset == 0 }

    /// Like Apple Maps: the minimised bubble floats with a wide margin and is most see-through; halfway up it has
    /// a narrow margin and less glass; fully up it is solid and runs to the edges of the screen.
    private var sideMargin: CGFloat {
        switch detent {
        case .peek: return floatsWhenPeeking ? Theme.Spacing.l : Theme.Spacing.s
        case .half: return Theme.Spacing.s
        case .full: return 0
        }
    }

    private var bottomMargin: CGFloat {
        switch detent {
        case .peek: return floatsWhenPeeking ? Theme.Spacing.xl + Theme.Spacing.s : Theme.Spacing.s
        case .half: return Theme.Spacing.s
        case .full: return 0
        }
    }

    private var glassOpacity: Double {
        switch detent {
        case .peek: return 0.5
        case .half: return 0.78
        case .full: return 1
        }
    }

    private func card(height: CGFloat, available: CGFloat) -> some View {
        let floating = isFloating
        // Rounded like the screen itself: the bubble is pill-shaped, the card's top corners echo the display's.
        let top: CGFloat = floating ? 32 : 38
        // Down at the bottom of the screen, the lower corners follow the display's own rounded corners.
        let bottom: CGFloat = floating ? 32 : max(displayCornerRadius - bottomMargin, 0)
        let shape = UnevenRoundedRectangle(topLeadingRadius: top, bottomLeadingRadius: bottom,
                                           bottomTrailingRadius: bottom, topTrailingRadius: top, style: .continuous)
        return VStack(spacing: 0) {
            // The grabber, title and buttons stay put; the rest scrolls beneath them.
            handle(available: available)
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) { content() }
                    .padding(.horizontal, Theme.Spacing.l)
                    .padding(.top, Theme.Spacing.s)
                    // Clear of the tab bar floating over the bottom of the card.
                    .padding(.bottom, Theme.Spacing.xxl + bottomOverlap)
            }
            // Scrolling drives the card: pull down past the top to lower it, scroll up from halfway to raise it.
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { old, new in
                contentScrolled = new > 2
                guard !snapping, detent != .peek else { return }
                if new < -70 {
                    snap(to: detent == .full ? .half : .peek)
                } else if detent == .half, new > 30, new > old {
                    snap(to: .full)
                }
            }
            // Content fades out as it scrolls up under the header instead of being cut off at a hard edge.
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: contentScrolled ? 20 : 0)
                    Rectangle()
                }
            }
            .scrollDisabled(detent == .peek)
            .opacity(detent == .peek && dragOffset == 0 ? 0 : 1)
            .frame(height: floating ? 0 : nil)
        }
        .frame(height: floating ? nil : height - bottomMargin, alignment: .top)
        .frame(maxWidth: .infinity)
        .clipShape(shape)
        .background {
            ZStack {
                shape.fill(.ultraThinMaterial)
                shape.fill(Roam.paperRaised.opacity(glassOpacity))
            }
            .shadow(color: .black.opacity(0.22), radius: 16)
        }
        .padding(.horizontal, sideMargin)
        .padding(.bottom, bottomMargin)
        .animation(.spring(duration: 0.35), value: detent)
    }

    private var grabber: some View {
        Capsule().fill(Roam.rule).frame(width: 36, height: 5).padding(.top, 6).frame(maxWidth: .infinity)
    }

    /// Moves the card once per scroll gesture, so a long pull doesn't drop it two steps.
    private func snap(to next: GlobeSheetDetent) {
        snapping = true
        setDetent(next)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            snapping = false
        }
    }

    private func handle(available: CGFloat) -> some View {
        // As a floating bubble it's just the header, snug around it; as a card it has a grabber on top.
        VStack(spacing: 2) {
            if !isFloating { grabber }
            header()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, isFloating ? Theme.Spacing.xs : 0)
        .padding(.bottom, isFloating ? 0 : Theme.Spacing.s)
        // The minimised height is measured while the header sits here.
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
        .contentShape(Rectangle())
        .onTapGesture { setDetent(detent == .half ? .full : .half) }
        .gesture(
            DragGesture(minimumDistance: 4)
                .updating($dragOffset) { value, offset, _ in offset = value.translation.height }
                .onEnded { value in
                    let target = detent.height(in: available, peek: peek) - value.predictedEndTranslation.height
                    setDetent(GlobeSheetDetent.allCases.min {
                        abs($0.height(in: available, peek: peek) - target) < abs($1.height(in: available, peek: peek) - target)
                    } ?? .half)
                }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(headerLabel)
        .accessibilityHint(detent == .full ? "Shows the map" : "Minimizes the map")
        .accessibilityAction(named: detent == .full ? "Show the map" : "Minimize the map") { setDetent(detent == .half ? .full : .half) }
        .accessibilityIdentifier(headerIdentifier)
    }

    private func setDetent(_ next: GlobeSheetDetent) {
        if UIAccessibility.isReduceMotionEnabled {
            detent = next
        } else {
            withAnimation(.spring(duration: 0.35)) { detent = next }
        }
    }
}

/// Shows which way tapping a card's header moves it.
struct GlobeSheetChevron: View {
    let detent: GlobeSheetDetent

    var body: some View {
        Image(systemName: detent == .full ? "chevron.down" : "chevron.up")
            .font(.footnote.weight(.bold)).foregroundStyle(Roam.inkMuted).accessibilityHidden(true)
    }
}
