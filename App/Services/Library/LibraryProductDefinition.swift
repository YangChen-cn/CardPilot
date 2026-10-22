import Foundation

struct LibraryProductDefinition: Decodable {
    let id: String
    let bankID: String
    let catalogResource: String
    let imageResource: String
    let baseRewardVerified: Bool
    let welcomePlans: [WelcomePlan]
}
