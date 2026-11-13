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
        guard maxPixel > 0, maxBytes > 0 else { throw Failure.tooLarge }
        guard let imageSource = CGImageSourceCreateWithData(source as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            throw Failure.unreadable
        }
        var pixel = min(maxPixel, Limits.photoLongestSide)
        let byteLimit = min(maxBytes, Limits.photoMaxBytes)
        while pixel >= 1 {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                // Applies the EXIF orientation so the pixels are upright with no orientation tag.
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: pixel,
                kCGImageSourceShouldCacheImmediately: true,
            ]
            guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary),
                  let image = eightBit(thumbnail) else { throw Failure.unreadable }
            for quality in [0.82, 0.7, 0.6, 0.5] {
                if let data = encode(image, quality: quality), data.count <= byteLimit {
                    return Processed(data: data, width: image.width, height: image.height)
                }
            }
            pixel = pixel * 3 / 4
        }
        throw Failure.tooLarge
    }

    /// Recheck durable bytes before upload: a missing/corrupt file must never become ready.
    static func preparedJPEG(_ data: Data) throws -> Processed {
        guard !data.isEmpty, data.count <= Limits.photoMaxBytes else { throw Failure.tooLarge }
        // ImageIO decodes truncated files leniently; a kept upload must be complete (status and EOI).
        guard data.suffix(2) == Data([0xff, 0xd9]),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetStatus(source) == .statusComplete,
              CGImageSourceGetType(source) as String? == UTType.jpeg.identifier,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw Failure.unreadable }
        guard image.width > 0, image.height > 0, max(image.width, image.height) <= Limits.photoLongestSide else { throw Failure.tooLarge }
        let properties = properties(of: data)
        guard properties[kCGImagePropertyGPSDictionary as String] == nil,
              (properties[kCGImagePropertyOrientation as String] as? Int ?? 1) == 1 else { throw Failure.unreadable }
        guard try stripMetadataSegments(data) == data else { throw Failure.unreadable }
        return Processed(data: data, width: image.width, height: image.height)
    }

    /// 10-bit and HDR photos (iPhone HEIC) decode to images the JPEG encoder can't write.
    /// Redraw those into 8 bits per channel, keeping a standard RGB color space (else Display P3).
    private static func eightBit(_ image: CGImage) -> CGImage? {
        if image.bitsPerComponent == 8, image.bitsPerPixel == 32 || image.bitsPerPixel == 24,
           image.colorSpace?.model == .rgb, !(image.colorSpace.map(CGColorSpaceUsesExtendedRange) ?? false) { return image }
        let space = image.colorSpace.flatMap { space in
            space.model == .rgb && !CGColorSpaceUsesExtendedRange(space) && !CGColorSpaceUsesITUR_2100TF(space) && space.supportsOutput ? space : nil
        } ?? CGColorSpace(name: CGColorSpace.displayP3)!
        guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }

    /// Re-encodes without copying any source properties, so EXIF/GPS/TIFF metadata is dropped.
    private static func encode(_ image: CGImage, quality: Double) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return try? stripMetadataSegments(output as Data)
    }

    /// ImageIO can add default metadata and private segments (for example Apple's APP10 "AROT"
    /// decode index on large images). Keep only the APPn segments the server inspector accepts
    /// (APP0 JFIF/JFXX, APP2 ICC profile, APP14 Adobe) and drop comments, retaining JPEG coding
    /// tables. Entropy-coded bytes stay intact.
    static func stripMetadataSegments(_ data: Data) throws -> Data {
        let bytes = [UInt8](data)
        guard bytes.count >= 4, bytes[0] == 0xff, bytes[1] == 0xd8 else { throw Failure.unreadable }
        var result = Data(bytes.prefix(2))
        var offset = 2
        while offset < bytes.count {
            let start = offset
            guard bytes[offset] == 0xff else { throw Failure.unreadable }
            while offset < bytes.count, bytes[offset] == 0xff { offset += 1 }
            guard offset < bytes.count else { throw Failure.unreadable }
            let marker = bytes[offset]
            offset += 1
            if marker == 0xda || marker == 0xd9 {
                result.append(contentsOf: bytes[start...])
                return result
            }
            if marker == 0x01 || (0xd0...0xd7).contains(marker) {
                result.append(contentsOf: bytes[start..<offset])
                continue
            }
            guard offset + 2 <= bytes.count else { throw Failure.unreadable }
            let length = Int(bytes[offset]) * 256 + Int(bytes[offset + 1])
            guard length >= 2, offset + length <= bytes.count else { throw Failure.unreadable }
            let payload = bytes[(offset + 2)..<(offset + length)]
            offset += length
            if marker == 0xfe || ((0xe0...0xef).contains(marker) && !isAllowedAppSegment(marker, payload)) { continue }
            result.append(contentsOf: bytes[start..<offset])
        }
        throw Failure.unreadable
    }

    /// Mirrors `supabase/functions/prepare-media/inspector.ts`; any other APPn is rejected there.
    private static func isAllowedAppSegment(_ marker: UInt8, _ payload: ArraySlice<UInt8>) -> Bool {
        func starts(_ tag: String) -> Bool { payload.starts(with: Array(tag.utf8)) }
        switch marker {
        case 0xe0: return starts("JFIF\0") || starts("JFXX\0")
        case 0xe2: return starts("ICC_PROFILE\0")
        case 0xee: return starts("Adobe")
        default: return false
        }
    }

    /// Metadata dictionaries of an encoded image (used by tests to prove GPS is gone).
    static func properties(of data: Data) -> [String: Any] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else { return [:] }
        return properties
    }
}
