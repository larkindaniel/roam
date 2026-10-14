import SwiftUI

/// S18 own profile root.
struct ProfileRootView: View {
    @Environment(SessionStore.self) private var session

    @Environment(AppRouter.self) private var router

    var body: some View {
        Group {
            if let userID = session.userID {
                ProfileView(userID: userID)
            } else {
                ProgressView()
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { router.push(.settings) } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("Settings")
                    .accessibilityIdentifier("open-settings")
            }
        }
    }
}

struct ProfileView: View {
    let userID: UUID

    @Environment(AppServices.self) private var services
    @Environment(AppRouter.self) private var router
    @State private var profile: LoadPhase<PublicProfile> = .idle
    @State private var travel: TravelProfile?
    @State private var travelError: String?

    private var year: Int { Calendar.current.component(.year, from: Date()) }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.l) {
                switch profile {
                case .idle, .loading:
                    SkeletonList(rows: 3).padding()
                case .failed(let message):
                    InlineRetryView(message: message) { Task { await load() } }.padding()
                case .loaded(let value):
                    header(value)
                    globeCard(value)
                }
            }
            .padding(.bottom, Theme.Spacing.xl)
        }
        .background(Theme.groupedCanvas)
        .navigationTitle(profile.value?.member.displayName ?? "Profile")
        .navigationBarTitleDisplayMode(.inline)
        .task { if profile.value == nil { await load() } }
        .refreshable { await load() }
        .screenIdentifier("profile-root")
    }

    private func load() async {
        if profile.value == nil { profile = .loading }
        do {
            let loaded = try await services.profiles.publicProfile(userID: userID)
            profile = .loaded(loaded)
        } catch {
            if profile.value == nil { profile = .failed(error.roamMessage) }
        }
        do {
            travel = try await services.travel.travelProfile(userID: userID, year: year)
            travelError = nil
        } catch {
            travelError = error.roamMessage
        }
    }

    private func header(_ value: PublicProfile) -> some View {
        VStack(spacing: Theme.Spacing.s) {
            AvatarView(member: value.member, size: 88)
            Text(value.member.displayName).font(.roamTitle(.title))
                .multilineTextAlignment(.center)
            Text("@\(value.member.handle)").font(.subheadline).foregroundStyle(.secondary)
            if !value.bio.isEmpty {
                Text(value.bio).font(.body).multilineTextAlignment(.center).padding(.horizontal)
            }
            if let home = value.homeCityName {
                Label("Home: \(home)", systemImage: "house").font(.footnote).foregroundStyle(.secondary)
            }
            HStack(spacing: Theme.Spacing.xl) {
                stat(value.followerCount, "Followers")
                stat(value.followingCount, "Following")
                stat(value.rankedCount, "Ranked")
                stat(value.wantCount, "Want to Go")
            }
            .padding(.top, Theme.Spacing.s)
        }
        .padding(.top, Theme.Spacing.l)
        .padding(.horizontal)
    }

    private func stat(_ count: Int, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(count)").font(.headline).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func globeCard(_ value: PublicProfile) -> some View {
        Button {
            router.push(.globe(userID))
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                GlobeMapView(pins: travel?.pins ?? [], shadedCountryCodes: Set(travel?.countries.map(\.countryCode) ?? []),
                             style: .globe, interactive: false)
                    .frame(height: 230)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(value.countryCount) \(value.countryCount == 1 ? "country" : "countries") · \(value.cityCount) \(value.cityCount == 1 ? "city" : "cities")")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(travelError ?? "All-time places visited")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.left.and.arrow.down.right").foregroundStyle(Theme.accent)
                }
                .padding(Theme.Spacing.m)
            }
            .background(Theme.raisedCard)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).strokeBorder(Theme.hairline.opacity(0.5)))
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
        .accessibilityLabel("Travel globe: \(value.countryCount) countries, \(value.cityCount) cities. Opens the full globe.")
        .accessibilityIdentifier("mini-globe")
    }
}
