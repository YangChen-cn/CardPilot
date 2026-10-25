import Foundation
import CryptoKit
import ImageIO

/// Shared, bounded decoding cache. Original files remain unchanged in SwiftData.
actor CardImageStore {
    static let shared = CardImageStore()
    private var images: [String: CardImageAsset] = [:]
    private var order: [String] = []

    func image(for data: Data) throws -> CardImageAsset? {
        try Task.checkCancellation()
        let key = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        if let image = images[key] { return image }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1200,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        try Task.checkCancellation()
        let asset = CardImageAsset(image: image)
        images[key] = asset
        order.append(key)
        if order.count > 12 { images.removeValue(forKey: order.removeFirst()) }
        return asset
    }
}
