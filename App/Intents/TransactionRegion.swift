import AppIntents

enum TransactionRegion: String, AppEnum {
    case hongKong = "HK"
    case mainlandChina = "CN"
    case macao = "MO"
    case other = "other"
    case unspecified = ""

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "交易地区")
    static let caseDisplayRepresentations: [TransactionRegion: DisplayRepresentation] = [
        .hongKong: "香港",
        .mainlandChina: "中国内地",
        .macao: "澳门",
        .other: "其他地区",
        .unspecified: "未指定"
    ]

    var isOverseas: Bool { self == .mainlandChina || self == .macao || self == .other }
}
