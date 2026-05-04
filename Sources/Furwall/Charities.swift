import Foundation

/// One animal welfare org that Furwall deep-links to. Money never flows
/// through the app — clicking Donate just opens the org's own donate page in
/// the user's browser. Furwall is a referrer, not a payment intermediary.
struct Charity: Identifiable, Equatable {
    let id: String          // stable key used by DonationTracker + Cloudflare worker
    let name: LocalizedStringResource
    let mission: LocalizedStringResource     // one-sentence summary; sentence case, period
    let donateURL: URL
}

enum Charities {
    /// Curated list for the user's current region, with US as fallback.
    /// One org per locale unless explicitly hedged (FR ships two — SPA +
    /// 30 Millions d'Amis — both RUP/FRUP, hedged across each).
    ///
    /// `name` and `mission` are `LocalizedStringResource` so SwiftUI's
    /// `Text(...)` resolves them via `Localizable.xcstrings` at render time.
    /// English literals here are the source-language values that Xcode's
    /// build-time extractor writes into the catalog as keys; translations
    /// are added by editing the catalog, no code changes needed.
    /// Each org is re-vetted every release.
    static var curated: [Charity] {
        forRegion(Locale.current.region?.identifier)
    }

    static func forRegion(_ region: String?) -> [Charity] {
        switch region {
        case "GB": return gb
        case "AU": return au
        case "CA": return ca
        case "IE": return ie
        case "NZ": return nz
        case "DE": return de
        case "FR": return fr
        case "JP": return jp
        default:   return us
        }
    }

    private static let us: [Charity] = [
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

    private static let gb: [Charity] = [
        Charity(
            id: "cats-protection",
            name: "Cats Protection",
            mission: "Rescues, rehomes, and protects cats across the UK.",
            donateURL: URL(string: "https://www.cats.org.uk/donate")!
        ),
    ]

    private static let au: [Charity] = [
        Charity(
            id: "cat-protection-nsw",
            name: "Cat Protection Society of NSW",
            mission: "Rehomes homeless cats and kittens across Sydney.",
            donateURL: URL(string: "https://catprotection.org.au/donations-page/donate-now/")!
        ),
    ]

    private static let ca: [Charity] = [
        Charity(
            id: "toronto-cat-rescue",
            name: "Toronto Cat Rescue",
            mission: "Rescues abandoned, sick, and injured cats across the GTA.",
            donateURL: URL(string: "https://www.torontocatrescue.ca/donate")!
        ),
    ]

    private static let ie: [Charity] = [
        Charity(
            id: "nspca",
            name: "National SPCA",
            mission: "Rescues, rehabilitates, and rehomes Ireland's neglected animals nationwide.",
            donateURL: URL(string: "https://nspca.ie/donate/")!
        ),
    ]

    private static let nz: [Charity] = [
        Charity(
            id: "spca-nz",
            name: "SPCA New Zealand",
            mission: "Rescues, rehabilitates, and rehomes cats across New Zealand.",
            donateURL: URL(string: "https://www.spca.nz/donate/donate-now")!
        ),
    ]

    private static let de: [Charity] = [
        Charity(
            id: "tierschutzbund",
            name: "Deutscher Tierschutzbund",
            mission: "Backs Germany's largest network of animal shelters and cat rescues.",
            donateURL: URL(string: "https://www.tierschutzbund.de/helfen/spenden/jetzt-spenden/")!
        ),
    ]

    private static let fr: [Charity] = [
        Charity(
            id: "spa-france",
            name: "La SPA",
            mission: "Runs France's national network of cat and dog refuges.",
            donateURL: URL(string: "https://www.la-spa.fr/agir-avec-la-spa/soutenir-la-spa/donner-a-la-spa/")!
        ),
        Charity(
            id: "30-millions",
            name: "Fondation 30 Millions d'Amis",
            mission: "Lobbies for animal-welfare law and funds community-cat sterilization.",
            donateURL: URL(string: "https://don.30millionsdamis.fr/netful-presentation-association/site/30ma/defaut/fr/don/index.html")!
        ),
    ]

    private static let jp: [Charity] = [
        Charity(
            id: "jspca",
            name: "Japan SPCA",
            mission: "Funds free spay/neuter for stray cats across Japan.",
            donateURL: URL(string: "https://jspca.or.jp/kihu.html")!
        ),
    ]
}
