import CoreGraphics

/// Presentation bounds for the exact bundled HSBC marketing canvas. Original bytes and
/// custom artwork stay intact; both the catalog and already-saved cards use this viewport.
enum CardImageContentLayout {
    static func image(_ image: CGImage, sourceDigest: String) -> CGImage {
        guard sourceDigest == "0a5d027bbf93e8b0cca878d42e8f8a0c25153ebd19d39da24b2cd1b798a9ec64" else { return image }
        // The 1600×900 source places the entire card at (440, 224), size 720×453.
        let sx = CGFloat(image.width) / 1600, sy = CGFloat(image.height) / 900
        let rect = CGRect(x: 440 * sx, y: 224 * sy, width: 720 * sx, height: 453 * sy).integral
        return image.cropping(to: rect) ?? image
    }
}
