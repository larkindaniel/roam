import SwiftUI

struct FriendAreaRows: View {
    let area: FriendVisitArea
    let activity: [FriendAreaActivity]
    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("Friends who’ve been").font(.roamTitle(.title3)).accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(activity) { item in
                    SocialNavigationRow(title: item.member.displayName, symbol: "person", subtitle: subtitle(item), member: item.member) {
                        // Opens their profile.
                        router.push(.member(item.member.id))
                    }
                    .accessibilityIdentifier("area-friend-\(item.member.handle)")
                    if item.id != activity.last?.id { RowSeparator() }
                }
            }
            .roamCard(padding: Theme.Spacing.m)
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier("area-friends")
    }

    private func subtitle(_ item: FriendAreaActivity) -> String {
        if area.cityName != nil {
            return item.placeCount == 1 ? "1 place" : "\(item.placeCount) places"
        }
        let names = item.cities.map(\.name).uniqued()
        let first = Array(names.prefix(2)).formatted(.list(type: .and))
        let remaining = names.count - 2
        return remaining > 0 ? "\(first) · +\(remaining) more" : first
    }
}
