import ImageIO
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import Roam

/// Upload preparation must remove location/metadata, apply orientation and meet the actual
/// encoded limits the server inspector enforces.
final class M5ImageProcessorTests: XCTestCase {
    /// A JPEG carrying GPS, orientation and EXIF the way a camera photo would.
    private func cameraJPEG(width: Int, height: Int, orientation: Int, noise: Bool = false) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.systemRed.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
            if noise {
                var generator = SystemRandomNumberGenerator()
                for _ in 0..<(width * height / 40) {
                    UIColor(white: CGFloat.random(in: 0...1, using: &generator), alpha: 1).setFill()
                    context.fill(CGRect(x: Int.random(in: 0..<width, using: &generator), y: Int.random(in: 0..<height, using: &generator), width: 3, height: 3))
                }
            }
        }
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil))
        let properties: [CFString: Any] = [
            kCGImagePropertyOrientation: orientation,
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 38.7223, kCGImagePropertyGPSLatitudeRef: "N",
                                            kCGImagePropertyGPSLongitude: 9.1393, kCGImagePropertyGPSLongitudeRef: "W"],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "Taken at home"],
            kCGImageDestinationLossyCompressionQuality: 1.0,
        ]
        CGImageDestinationAddImage(destination, try XCTUnwrap(image.cgImage), properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func markers(_ data: Data) -> [UInt8] {
        let bytes = [UInt8](data)
        var found: [UInt8] = []
        var offset = 2
        while offset + 4 <= bytes.count, bytes[offset] == 0xff {
            let marker = bytes[offset + 1]
            found.append(marker)
            if marker == 0xda { break }
            offset += 2 + Int(bytes[offset + 2]) * 256 + Int(bytes[offset + 3])
        }
        return found
    }

    func testCameraMetadataIsRemovedAndOrientationIsApplied() throws {
        let source = try cameraJPEG(width: 400, height: 300, orientation: 6)
        XCTAssertNotNil(ImageProcessor.properties(of: source)[kCGImagePropertyGPSDictionary as String], "The fixture really carries GPS")
        let prepared = try ImageProcessor.prepare(source)
        XCTAssertEqual(prepared.width, 300, "Orientation 6 is applied to the pixels")
        XCTAssertEqual(prepared.height, 400)
        let properties = ImageProcessor.properties(of: prepared.data)
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary as String], "Location is stripped")
        XCTAssertEqual(properties[kCGImagePropertyOrientation as String] as? Int ?? 1, 1, "No orientation tag remains")
        let segments = markers(prepared.data)
        XCTAssertFalse(segments.contains(0xe1), "No EXIF/XMP APP1 segment is uploaded")
        XCTAssertFalse(segments.contains(0xed), "No IPTC APP13 segment is uploaded")
        XCTAssertFalse(segments.contains(0xfe), "No JPEG comment is uploaded")
        XCTAssertEqual(try ImageProcessor.preparedJPEG(prepared.data), prepared, "Prepared bytes pass the pre-upload recheck unchanged")
    }

    func testLargePhotoIsBoundedByActualPixelsAndEncodedBytes() throws {
        let source = try cameraJPEG(width: 4_000, height: 3_000, orientation: 1, noise: true)
        let prepared = try ImageProcessor.prepare(source)
        XCTAssertLessThanOrEqual(max(prepared.width, prepared.height), Limits.photoLongestSide)
        XCTAssertLessThanOrEqual(prepared.data.count, Limits.photoMaxBytes)
        let image = try XCTUnwrap(UIImage(data: prepared.data)?.cgImage)
        XCTAssertEqual(image.width, prepared.width, "Reported dimensions are the encoded image's real dimensions")
        XCTAssertEqual(image.height, prepared.height)
    }

    func testImpossibleByteLimitFailsHonestly() throws {
        let source = try cameraJPEG(width: 64, height: 64, orientation: 1)
        XCTAssertThrowsError(try ImageProcessor.prepare(source, maxBytes: 100)) { error in
            XCTAssertEqual(error as? ImageProcessor.Failure, .tooLarge)
        }
    }

    func testUnreadableAndMetadataBearingBytesNeverPassThePreUploadCheck() throws {
        XCTAssertThrowsError(try ImageProcessor.prepare(Data("not an image".utf8)))
        XCTAssertThrowsError(try ImageProcessor.preparedJPEG(Data("not an image".utf8)))
        XCTAssertThrowsError(try ImageProcessor.preparedJPEG(try cameraJPEG(width: 32, height: 32, orientation: 1)),
                             "Bytes with GPS/EXIF are rejected before any upload")
        let prepared = try ImageProcessor.prepare(try cameraJPEG(width: 32, height: 32, orientation: 1))
        XCTAssertThrowsError(try ImageProcessor.preparedJPEG(prepared.data.prefix(prepared.data.count / 2)), "Truncated bytes are rejected")
        XCTAssertThrowsError(try ImageProcessor.preparedJPEG(Data()))
    }
}
