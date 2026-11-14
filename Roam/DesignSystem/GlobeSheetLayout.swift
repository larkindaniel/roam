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
    /// How far the minimised bubble floats above the bottom of the screen.
    var floatingBottomMargin: CGFloat = Theme.Spacing.xl + Theme.Spacing.s
    var floatingSideMargin: CGFloat = Theme.Spacing.l
    /// A control that sits on the map just above the card, at the left; hidden once the card fills the screen.
    var mapAccessory: AnyView? = nil
    /// The same, at the right.
    var mapTrailingAccessory: AnyView? = nil
    /// Scrolled, the header gives way to a dark fade with just the name (used for a place's card).
    var collapsesHeaderOnScroll = false
    /// Minimised, a fixed bubble height (the tab bar's, on My Places) with the row centred in it.
    var floatingHeight: CGFloat? = nil
    /// How opaque the minimised bubble's glass is (raise it over a dark map, like the globe).
    var peekOpacity: Double = 0.35
    /// Tapping the header raises or lowers the card; off when the header holds a search field.
    var headerTapToggles = true
    /// Pushes the card below the screen (for bringing it up from the bottom as the screen appears).
    var cardHidden = false
    /// Sits over a map that belongs to the screen underneath (a place's card over its city's map): no backdrop of its own.
    var seeThrough = false
    /// Changing it scrolls the card's content back to the top (its tab's button tapped).
    var scrollToTopToken = 0
    @ViewBuilder var globe: () -> Globe
    @ViewBuilder var header: () -> Header
    @ViewBuilder var content: () -> Content

    /// How far the finger has moved the card; it settles back to 0 in the same animation that moves the card to its new
    /// height, so letting go never jumps.
    @State private var dragOffset: CGFloat = 0
    @State private var headerHeight: CGFloat?
    /// The header as it is when minimised, which sets the minimised height; kept apart so it can't move mid-drag.
    @State private var peekHeaderHeight: CGFloat?
    @State private var snapping = false
    @State private var contentScrolled = false
    @State private var scroll = ScrollPosition(edge: .top)

    /// Minimised, the card is just its header, sitting on the tab bar.
    private var peek: CGFloat { (peekHeaderHeight ?? headerHeight).map { $0 + bottomOverlap } ?? peekHeight }

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
                    if detent != .full, mapAccessory != nil || mapTrailingAccessory != nil {
                        HStack {
                            mapAccessory
                            Spacer()
                            mapTrailingAccessory
                        }
                        .padding(.horizontal, Theme.Spacing.l)
                        .transition(.opacity)
                    }
                    // Hidden, the card is taken out entirely (an offset card's scroll view could still catch touches).
                    if !cardHidden {
                        card(height: height, available: available)
                    }
                }
            }
            .frame(width: proxy.size.width, height: available, alignment: .bottom)
            .onChange(of: available, initial: true) { _, height in screenHeight = height }
        }
        .background(Color.black.opacity(seeThrough ? 0 : 1).ignoresSafeArea())
        // With no tab bar below, the card runs down to the bottom of the screen.
        .ignoresSafeArea(edges: .bottom)
    }

    /// The rounding of current iPhone screens (about 62 points on the iPhone 17 and 16 Pro).
    private let displayCornerRadius: CGFloat = 62
    private static var topClearance: CGFloat { 12 }
    private static var contentInset: CGFloat { 20 }

    private var isFloating: Bool { floatsWhenPeeking && detent == .peek && dragOffset == 0 }

    /// Like Apple Maps: the minimised bubble floats with a wide margin and is most see-through; halfway up it has
    /// a narrow margin and less glass; fully up it is solid and runs to the edges of the screen.
    private var sideMargin: CGFloat {
        switch detent {
        case .peek: return floatsWhenPeeking ? floatingSideMargin : Theme.Spacing.s
        case .half: return Theme.Spacing.s
        case .full: return 0
        }
    }

    private var bottomMargin: CGFloat {
        switch detent {
        case .peek: return floatsWhenPeeking ? floatingBottomMargin : Theme.Spacing.s
        case .half: return Theme.Spacing.s
        case .full: return 0
        }
    }

    private var glassOpacity: Double {
        switch detent {
        case .peek: return peekOpacity
        case .half: return 0.55
        case .full: return 1
        }
    }

    private func card(height: CGFloat, available: CGFloat) -> some View {
        let floating = isFloating
        // Rounded like the screen itself: the bubble is pill-shaped, the card's top corners echo the display's.
        let pill = floatingHeight.map { $0 / 2 } ?? 32
        let top: CGFloat = floating ? pill : 38
        // Down at the bottom of the screen, the lower corners follow the display's own rounded corners.
        let bottom: CGFloat = floating ? pill : max(displayCornerRadius - bottomMargin, 0)
        let shape = UnevenRoundedRectangle(topLeadingRadius: top, bottomLeadingRadius: bottom,
                                           bottomTrailingRadius: bottom, topTrailingRadius: top, style: .continuous)
        return Group {
            if collapsesHeaderOnScroll && !floating {
                // The content runs under the header; once scrolled, the header gives way to a dark fade with just the
                // name, small and centred.
                ZStack(alignment: .top) {
                    scroller(topInset: headerHeight ?? 0, fadesUnderHeader: false)
                    if contentScrolled && dragOffset == 0 {
                        ZStack(alignment: .top) {
                            LinearGradient(colors: [.black.opacity(0.6), .black.opacity(0.25), .clear], startPoint: .top, endPoint: .bottom)
                                .frame(height: 84)
                            Text(headerLabel)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .padding(.horizontal, Self.contentInset * 2)
                                .padding(.top, 14)
                        }
                        .allowsHitTesting(false)
                        .transition(.opacity)
                    } else {
                        // No band of its own: the header sits on the same even glass as the rest of the card.
                        handle(available: available)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: contentScrolled)
            } else {
                VStack(spacing: 0) {
                    // The grabber, title and buttons stay put; the rest scrolls beneath them.
                    handle(available: available)
                    scroller(topInset: 0, fadesUnderHeader: true)
                        .frame(height: floating ? 0 : nil)
                }
            }
        }
        .frame(height: floating ? nil : height - bottomMargin, alignment: .top)
        .frame(maxWidth: .infinity)
        .clipShape(shape)
        .background {
            // Lowered with no tint asked for, it's exactly the glass of the floating buttons over the map.
            if floating && peekOpacity == 0 {
                // Dark, like the toolbar buttons that sit over the globe.
                Color.clear.floatingBubble(shape).environment(\.colorScheme, .dark)
            } else {
                SheetGlass(shape: shape, tint: Roam.paper.opacity(glassOpacity), solid: detent == .full && dragOffset == 0)
            }
        }
        .padding(.horizontal, sideMargin)
        .padding(.bottom, bottomMargin)
    }

    private func scroller(topInset: CGFloat, fadesUnderHeader: Bool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) { content() }
                .environment(\.onGlass, detent != .full)
                .padding(.horizontal, Self.contentInset)
                .padding(.top, Theme.Spacing.s + topInset)
                // Clear of the tab bar floating over the bottom of the card.
                .padding(.bottom, Theme.Spacing.xxl + bottomOverlap)
        }
        .scrollPosition($scroll)
        .onChange(of: scrollToTopToken) { _, _ in withAnimation { scroll.scrollTo(edge: .top) } }
        // Fully up, pulling down past the top of the content lowers the card.
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, new in
            contentScrolled = new > 8
            guard !snapping, detent == .full, dragOffset == 0 else { return }
            if new < -60 { snap(to: .half) }
        }
        // Content fades out as it scrolls up under the header instead of being cut off at a hard edge.
        .mask {
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: fadesUnderHeader && contentScrolled ? 20 : 0)
                Rectangle()
            }
        }
        // Short of fully up, the content doesn't scroll: dragging anywhere on the card moves the card, as in Apple Maps.
        .scrollDisabled(detent != .full)
        .simultaneousGesture(cardDrag, isEnabled: detent != .full)
        .opacity(detent == .peek && dragOffset == 0 ? 0 : 1)
    }


    /// The screen height, for working out which position a released card is nearest.
    @State private var screenHeight: CGFloat = 0

    /// The card follows the finger freely; let go and it pops to the nearest of its three positions (minimised, halfway,
    /// fully up), carried on a little by a flick. Measured against the screen, not the card: the card moves under the
    /// finger, and measuring against it made the drag fight itself and shake.
    private var cardDrag: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .onChanged { value in
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { dragOffset = value.translation.height }
            }
            .onEnded { value in
                let top = screenHeight - Self.topClearance
                func height(_ position: GlobeSheetDetent) -> CGFloat { min(position.height(in: screenHeight, peek: peek), top) }
                // Where the card is now, plus a share of the flick so a quick swipe carries on to the next position.
                let released = height(detent) - value.translation.height
                let landing = released - (value.predictedEndTranslation.height - value.translation.height) * 0.5
                let next = GlobeSheetDetent.allCases.min { abs(height($0) - landing) < abs(height($1) - landing) } ?? .half
                settle(at: next)
            }
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
        Group {
            if isFloating, let floatingHeight {
                // A slim bubble: the row centred in it, the grabber tucked into the top edge.
                // No grabber on the slim bubble; it swipes up all the same.
                header()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .frame(height: floatingHeight)
            } else {
                VStack(spacing: 2) {
                    // The grabber shows even on the bubble, so it's clear it swipes up.
                    grabber
                    header()
                }
                // As a bubble, the same room below the header as the grabber takes above it, so the row sits centred.
                .padding(.bottom, isFloating ? 13 : Theme.Spacing.s)
            }
        }
        .frame(maxWidth: .infinity)
        // The same gap to the left of the title as there is above it.
        .padding(.horizontal, Self.contentInset)
        // The minimised height is measured while the header sits here.
        // The content's room under the header follows it always; the minimised height only takes it while minimised.
        // Never mid-drag: re-measuring as the card moves shifted the content under the finger.
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
            guard dragOffset == 0 else { return }
            headerHeight = height
            if detent == .peek { peekHeaderHeight = height }
        }
        .contentShape(Rectangle())
        .onTapGesture { if headerTapToggles { setDetent(detent == .half ? .full : .half) } }
        .gesture(cardDrag)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(headerLabel)
        .accessibilityHint(detent == .full ? "Shows the map" : "Minimizes the map")
        .accessibilityAction(named: detent == .full ? "Show the map" : "Minimize the map") { setDetent(detent == .half ? .full : .half) }
        .accessibilityIdentifier(headerIdentifier)
    }

    private func setDetent(_ next: GlobeSheetDetent) { settle(at: next) }

    /// Moves the card to a height and lets go of any drag in the same animation, with no bounce.
    private func settle(at next: GlobeSheetDetent) {
        if UIAccessibility.isReduceMotionEnabled {
            detent = next
            dragOffset = 0
        } else {
            withAnimation(.spring(duration: 0.32, bounce: 0)) {
                detent = next
                dragOffset = 0
            }
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

/// The card's surface: Liquid Glass tinted Apple's light grey on iOS 26 (frosted material before), solid once
/// the card fills the screen.
private struct SheetGlass<S: Shape>: View {
    let shape: S
    let tint: Color
    let solid: Bool

    var body: some View {
        Group {
            if solid {
                shape.fill(Roam.paper)
            } else if #available(iOS 26.0, *) {
                Color.clear.glassEffect(.regular.tint(tint), in: shape)
            } else {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(tint)
                }
            }
        }
        .shadow(color: .black.opacity(0.18), radius: 16)
    }
}
