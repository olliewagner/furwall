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
    /// The two orgs Furwall recommends. Selection criteria: 4-star Charity
    /// Navigator, ≥85% to programs, public Candid Platinum/Gold seal,
    /// stable evergreen donate URL, no recent overhead/exec-comp criticism.
    /// One cat-specific (TNR), one upstream (spay/neuter + access to vet
    /// care) — a tight curated pair beats a third with operational concerns.
    /// Each org is re-vetted every release.
    static let curated: [Charity] = [
        Charity(
            id: "alleycat",
            name: "Alley Cat Allies",
            mission: "Protects community cats through trap-neuter-return.",
            donateURL: URL(string: "https://www.alleycat.org/donate/")!
        ),
        Charity(
            id: "petsmart",
            name: "PetSmart Charities",
            mission: "Funds spay/neuter access and veterinary care.",
            donateURL: URL(string: "https://petsmartcharities.org/donate")!
        ),
    ]
}
