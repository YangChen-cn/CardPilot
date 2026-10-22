import Foundation

actor SyncFolderAccess {
    private var accessedURL: URL?
    private var started = false

    func select(_ url: URL) throws -> Data {
        let started = url.startAccessingSecurityScopedResource()
        do {
            let bookmark = try url.bookmarkData(options: Self.creationOptions, includingResourceValuesForKeys: nil, relativeTo: nil)
            stop(); accessedURL = url; self.started = started
            return bookmark
        } catch {
            if started { url.stopAccessingSecurityScopedResource() }
            throw error
        }
    }

    func restore(_ data: Data) throws -> (URL, Data?) {
        var stale = false
        let url = try URL(resolvingBookmarkData: data, options: Self.resolutionOptions, relativeTo: nil, bookmarkDataIsStale: &stale)
        let bookmark = try select(url)
        return (url, stale ? bookmark : nil)
    }

    func stop() {
        if started { accessedURL?.stopAccessingSecurityScopedResource() }
        accessedURL = nil; started = false
    }

    private static var creationOptions: URL.BookmarkCreationOptions {
        #if os(macOS)
        .withSecurityScope
        #else
        .minimalBookmark
        #endif
    }
    private static var resolutionOptions: URL.BookmarkResolutionOptions {
        #if os(macOS)
        .withSecurityScope
        #else
        []
        #endif
    }
}
