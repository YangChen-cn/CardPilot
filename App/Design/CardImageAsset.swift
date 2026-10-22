import CoreGraphics

struct CardImageAsset: Sendable {
    let image: CGImage
    var aspectRatio: CGFloat { CGFloat(image.width) / CGFloat(image.height) }
}
