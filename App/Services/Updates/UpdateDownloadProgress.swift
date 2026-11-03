import Foundation

/// URLSession invokes this immutable delegate on its delegate queue. Mutable UI
/// state is never shared here; the @Sendable callback hops to MainActor.
final class UpdateDownloadProgress: NSObject, URLSessionDownloadDelegate, Sendable {
    let expectedSize: Int64
    let report: @Sendable (Double) -> Void
    init(expectedSize: Int64, report: @escaping @Sendable (Double) -> Void) {
        self.expectedSize = expectedSize
        self.report = report
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        let allowed = request.url.map { $0.scheme == "https" && $0.user == nil && $0.password == nil
            && ["github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com"].contains($0.host ?? "") } ?? false
        completionHandler(allowed ? request : nil)
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > expectedSize { downloadTask.cancel(); return }
        report(min(0.99, Double(totalBytesWritten) / Double(max(1, expectedSize))))
    }
}
