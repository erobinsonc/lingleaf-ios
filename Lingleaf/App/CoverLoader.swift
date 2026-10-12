import ImageIO
import LingleafCore
import UIKit

/// Book covers over HTTPS through `URLSessionFetcher` (so HTTPS only and size-capped),
/// decoded as small thumbnails and kept in memory for the session. Any failure returns
/// nil and the drawn cover stays.
actor CoverLoader {
    /// Largest cover image accepted; Gutenberg's medium covers are about 20–60 KB.
    static let maxBytes = 2 * 1024 * 1024

    private let http: HttpFetcher
    // Sized by bytes, not entries: a few dozen small thumbnails at most.
    private let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 8 * 1024 * 1024
        return cache
    }()

    init(http: HttpFetcher = URLSessionFetcher(maxBytes: CoverLoader.maxBytes)) {
        self.http = http
    }

    func load(_ url: URL) async -> UIImage? {
        let key = url.absoluteString as NSString
        if let image = cache.object(forKey: key) { return image }
        guard let response = try? await http.get(url.absoluteString), response.status == 200,
              let image = Self.thumbnail(response.body), let cgImage = image.cgImage else { return nil }
        cache.setObject(image, forKey: key, cost: cgImage.bytesPerRow * cgImage.height)
        return image
    }

    /// Reads the size first, refuses huge images and decodes a downsampled copy, so a small
    /// file that claims enormous dimensions can't exhaust memory. Nil when it isn't an image.
    static func thumbnail(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              GutenbergClient.coverSample(width: width, height: height) != nil else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: GutenbergClient.coverThumbnailHeight
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}
