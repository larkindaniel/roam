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
    var headerLabel: String
    var headerIdentifier: String
    var onRefresh: () async -> Void = {}
    @ViewBuilder var globe: () -> Globe
    @ViewBuilder var header: () -> Header
    @ViewBuilder var content: () -> Content

    @GestureState private var dragOffset: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let available = proxy.size.height
            let height = min(max(detent.height(in: available, peek: peekHeight) - dragOffset, peekHeight), available)
            ZStack(alignment: .bottom) {
                globe()
                    .frame(height: max(available - height + proxy.safeAreaInsets.top + 28, 0))
                    .frame(maxHeight: .infinity, alignment: .top)
                    .ignoresSafeArea(edges: .top)
                card(height: height, available: available)
            }
        }
        .background(Color.black.ignoresSafeArea())
    }

    private func card(height: CGFloat, available: CGFloat) -> some View {
        VStack(spacing: 0) {
            handle(available: available)
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) { content() }
                    .padding(.horizontal, Theme.Spacing.l)
                    .padding(.top, Theme.Spacing.s)
                    .padding(.bottom, Theme.Spacing.xxl)
            }
            .refreshable { await onRefresh() }
            .opacity(detent == .peek && dragOffset == 0 ? 0 : 1)
        }
        .frame(height: height, alignment: .top)
        .frame(maxWidth: .infinity)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24, style: .continuous)
                .fill(Roam.paper)
                .shadow(color: .black.opacity(0.25), radius: 12, y: -2)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func handle(available: CGFloat) -> some View {
        VStack(spacing: Theme.Spacing.s) {
            Capsule().fill(Roam.rule).frame(width: 36, height: 5).padding(.top, Theme.Spacing.s)
            header()
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.bottom, Theme.Spacing.s)
        .contentShape(Rectangle())
        .onTapGesture { setDetent(detent == .half ? .full : .half) }
        .gesture(
            DragGesture(minimumDistance: 4)
                .updating($dragOffset) { value, offset, _ in offset = value.translation.height }
                .onEnded { value in
                    let target = detent.height(in: available, peek: peekHeight) - value.predictedEndTranslation.height
                    setDetent(GlobeSheetDetent.allCases.min {
                        abs($0.height(in: available, peek: peekHeight) - target) < abs($1.height(in: available, peek: peekHeight) - target)
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
