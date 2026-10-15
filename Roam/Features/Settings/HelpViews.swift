import SwiftUI

/// About & help pages. The ranking page describes Roam's actual scoring (`roam-category-v1`);
/// privacy, terms and support describe what this build really does, without invented links.
struct HelpView: View {
    let topic: HelpTopic

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        Text(section.title).font(.roamTitle(.title3)).accessibilityAddTraits(.isHeader)
                        ForEach(section.paragraphs, id: \.self) { paragraph in
                            Text(paragraph).font(.body).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .roamCard()
                }
            }
            .padding()
        }
        .background(Theme.groupedCanvas)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .screenIdentifier("help-\(topic.rawValue)")
    }

    private var title: String {
        switch topic {
        case .ranking: return "How Roam works"
        case .privacy: return "Privacy"
        case .terms: return "Terms of use"
        case .support: return "Support"
        }
    }

    private struct HelpSection {
        let title: String
        let paragraphs: [String]
    }

    private var sections: [HelpSection] {
        switch topic {
        case .ranking:
            return [
                HelpSection(title: "Seven separate rankings", paragraphs: [
                    "Food & Drink, Outdoors, Day Trips, Culture, Nightlife, Activities and Stays are ranked separately. A place is only ever compared with your own places in the same category.",
                    "No one else's ratings change your scores.",
                ]),
                HelpSection(title: "How a score is set", paragraphs: [
                    "When you log a place you say whether you liked it, thought it was fine or didn't like it, then compare it with places you gave the same answer. Each comparison halves the remaining range, so a long list needs only a few choices.",
                    "Scores come from where a place sits: liked places score 6.7 to 10.0, fine places 3.4 to 6.6, and places you didn't like 0.0 to 3.3. Your first liked place is 8.4; with two it's 10.0 and 6.7. Scores move as your list grows, and other categories never change.",
                ]),
                HelpSection(title: "Ties, Skip and Undo", paragraphs: [
                    "Too tough means the two places are a tie: tied places share one score and rank, and more places in a tie don't change its score.",
                    "Skip stops comparing and places it approximately, without making it a tie. You can rank again any time. Undo steps back through choices before you save.",
                ]),
                HelpSection(title: "What gets posted", paragraphs: [
                    "Finishing a ranking, a new visit or Rank again posts automatically to your profile and your followers' feeds. Posts show the score at the time you posted, labelled \"Score when posted\".",
                    "Editing a note, photos or date later updates that post without re-posting it. Removing a post keeps your ranking and visit; removing a ranking keeps your visits, notes and photos.",
                ]),
                HelpSection(title: "Travel counts", paragraphs: [
                    "Your globe, countries, cities and New this year count places you've logged a visit to, whether or not they're still ranked. Saved places and your home city don't count.",
                    "New this year counts each place once, in the year of its earliest known visit. Visits with an unknown date aren't counted.",
                ]),
            ]
        case .privacy:
            return [
                HelpSection(title: "What other members see", paragraphs: [
                    "Signed-in members can see your profile, rankings and scores, Want to Go list, posts, public notes, visit photos, travel counts and who you follow. Blocked members see none of it.",
                ]),
                HelpSection(title: "What stays private", paragraphs: [
                    "Private notes, your email address and sign-in details, your settings, your reports, who you've blocked or muted, and unsaved drafts are only visible to you. Drafts and caches stay on this device until you save, discard or sign out.",
                    "Photos have location and other metadata removed on your device before upload.",
                ]),
                HelpSection(title: "Location", paragraphs: [
                    "Roam asks for your location only to sort or search near you. Everything works without it, including your globe.",
                ]),
                HelpSection(title: "Deleting your account", paragraphs: [
                    "Deleting your account hides your profile at once and then permanently deletes your rankings, visits, notes, photos, follows, likes, comments and posts. Text you've already shared outside Roam can't be recalled.",
                ]),
            ]
        case .terms:
            return [
                HelpSection(title: "Using Roam", paragraphs: [
                    "Share your own experiences honestly. Don't post spam, harassment, other people's private information or content you don't have the right to share.",
                    "Members can report places, posts, comments, photos and members. Reports are stored for review. Repeated or serious misuse may lead to content or accounts being removed.",
                ]),
                HelpSection(title: "Your content", paragraphs: [
                    "You keep ownership of what you post. Posting it lets other signed-in members view it in Roam until you remove it or delete your account.",
                ]),
            ]
        case .support:
            return [
                HelpSection(title: "Reporting a problem", paragraphs: [
                    "Use Report on a place, post, comment, photo or profile. Your reports and their status are in Settings › Your reports. A report shows as reviewed only after someone has actually reviewed it.",
                ]),
                HelpSection(title: "Account help", paragraphs: [
                    "Email accounts can get a password reset code from Settings › Account. Accounts that use Sign in with Apple are managed through Apple.",
                ]),
            ]
        }
    }
}
