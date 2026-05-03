import Foundation

/// One animal welfare org that Furwall deep-links to. Money never flows
/// through the app — clicking Donate just opens the org's own donate page in
/// the user's browser. Furwall is a referrer, not a payment intermediary.
struct Charity: Identifiable, Equatable {
    let id: String          // stable key used by DonationTracker
    let name: String
    let mission: String     // one-sentence summary; sentence case, period
    let donateURL: URL
}

enum Charities {
    /// The three orgs Furwall recommends. Selection criteria: 4-star Charity
    /// Navigator, ≥85% to programs, public Candid Platinum/Gold seal,
    /// stable evergreen donate URL, no recent overhead/exec-comp criticism.
    /// One cat-specific, one broader shelter network, one upstream
    /// (spay/neuter access) for prevention complement.
    static let curated: [Charity] = [
        Charity(
            id: "alleycat",
            name: "Alley Cat Allies",
            mission: "Protects community cats through trap-neuter-return.",
            donateURL: URL(string: "https://www.alleycat.org/donate/")!
        ),
        Charity(
            id: "bestfriends",
            name: "Best Friends Animal Society",
            mission: "Leads the no-kill movement for shelter dogs and cats.",
            donateURL: URL(string: "https://bestfriends.org/donate")!
        ),
        Charity(
            id: "petsmart",
            name: "PetSmart Charities",
            mission: "Funds spay/neuter access and veterinary care.",
            donateURL: URL(string: "https://petsmartcharities.org/donate")!
        ),
    ]
}
