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
    /// How much the floating tab bar covers the bottom of the layout (about 52 points on iOS 26, measured on
    /// the iPhone 17 simulator); 0 where the tab bar is hidden.
    var bottomOverlap: CGFloat = 52
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

    /// Minimised, the card is just its header, sitting on the tab bar.
    private var peek: CGFloat { headerHeight.map { $0 + bottomOverlap } ?? peekHeight }

    var body: some View {
        GeometryReader { proxy in
            let available = proxy.size.height
            let peekHeight = peek
            let height = min(max(detent.height(in: available, peek: peekHeight) - dragOffset, peekHeight), available)
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
    }

    private var isFloating: Bool { floatsWhenPeeking && detent == .peek && dragOffset == 0 }
    /// Minimised (or being dragged), the header shows in the grab area; opened up it scrolls with the content.
    private var headerPinned: Bool { detent == .peek || dragOffset != 0 }

    private func card(height: CGFloat, available: CGFloat) -> some View {
        let floating = isFloating
        return VStack(spacing: 0) {
            handle(available: available)
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    // Opened up, the title scrolls away with everything else; only the grabber stays put.
                    if !headerPinned { header() }
                    content()
                }
                    .padding(.horizontal, Theme.Spacing.l)
                    .padding(.top, Theme.Spacing.s)
                    .padding(.bottom, Theme.Spacing.xxl)
            }
            .refreshable { await onRefresh() }
            .opacity(detent == .peek && dragOffset == 0 ? 0 : 1)
            .frame(height: floating ? 0 : nil)
        }
        .frame(height: floating ? nil : height - Theme.Spacing.s, alignment: .top)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: floating ? 28 : 26, style: .continuous)
                .fill(Roam.paper)
                .shadow(color: .black.opacity(0.22), radius: 12, y: floating ? 4 : -1)
        }
        .clipShape(RoundedRectangle(cornerRadius: floating ? 28 : 26, style: .continuous))
        // Room round the card so the map or globe shows past its edges.
        .padding(.horizontal, floating ? Theme.Spacing.l : Theme.Spacing.s)
        .padding(.bottom, Theme.Spacing.s)
    }

    private func handle(available: CGFloat) -> some View {
        // As a floating bubble it's just the header, snug around it; as a card it has a grabber on top.
        VStack(spacing: Theme.Spacing.s) {
            if !isFloating {
                Capsule().fill(Roam.rule).frame(width: 36, height: 5).padding(.top, Theme.Spacing.s)
            }
            if headerPinned { header() }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, isFloating ? Theme.Spacing.xs : 0)
        .padding(.bottom, isFloating ? 0 : Theme.Spacing.s)
        // The minimised height is measured while the header sits here.
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { if headerPinned { headerHeight = $0 } }
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
