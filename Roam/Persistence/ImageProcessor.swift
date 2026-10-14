import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Prepares photos for upload (SPEC R10, D14): orientation normalized, all metadata (including
/// location) stripped by re-encoding, longest side ≤ 2,048 px and JPEG ≤ 3 MB.
enum ImageProcessor {
    struct Processed: Equatable, Sendable {
        let data: Data
        let width: Int
        let height: Int
    }

    enum Failure: Error, Equatable, LocalizedError {
        case unreadable
        case tooLarge

        var errorDescription: String? {
            switch self {
            case .unreadable: return "This photo couldn't be read. Try a different one."
            case .tooLarge: return "This photo can't be made small enough to upload."
            }
        }
    }

    static func prepare(_ source: Data, maxPixel: Int = Limits.photoLongestSide, maxBytes: Int = Limits.photoMaxBytes) throws -> Processed {
        guard let imageSource = CGImageSourceCreateWithData(source as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            throw Failure.unreadable
        }
        var pixel = maxPixel
        while pixel >= 512 {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                // Applies the EXIF orientation so the pixels are upright with no orientation tag.
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: pixel,
                kCGImageSourceShouldCacheImmediately: true,
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else { throw Failure.unreadable }
            for quality in [0.82, 0.7, 0.6, 0.5] {
                if let data = encode(image, quality: quality), data.count <= maxBytes {
                    return Processed(data: data, width: image.width, height: image.height)
                }
            }
            pixel = pixel * 3 / 4
        }
        throw Failure.tooLarge
    }

    /// Re-encodes without copying any source properties, so EXIF/GPS/TIFF metadata is dropped.
    private static func encode(_ image: CGImage, quality: Double) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// Metadata dictionaries of an encoded image (used by tests to prove GPS is gone).
    static func properties(of data: Data) -> [String: Any] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else { return [:] }
        return properties
    }
}
