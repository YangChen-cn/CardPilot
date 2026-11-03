import Foundation

enum AppUpdateError: LocalizedError {
    case request(Int), invalidDownload, checksum, missingChecksum
    var errorDescription: String? {
        switch self {
        case .request(let code): "GitHub 暂时无法访问（\(code)），请稍后再试。"
        case .invalidDownload: "安装包不完整，请重新下载。"
        case .checksum: "安装包校验失败，请重新下载。"
        case .missingChecksum: "此版本缺少校验值，请从发布页面下载安装。"
        }
    }
}
