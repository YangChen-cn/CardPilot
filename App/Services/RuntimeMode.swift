import Foundation

enum RuntimeMode {
    static var isDemo: Bool { ProcessInfo.processInfo.arguments.contains("--demo") }
    static var isTesting: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
        ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil
    }
    static var isEphemeral: Bool { isDemo || isTesting }
}
