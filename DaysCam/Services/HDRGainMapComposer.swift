import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Spike #587: keeps the capture's HDR gain map through crop and overlay.
/// Foundation/CoreImage only so it can also be compiled as a Mac script.
enum HDRGainMapComposer {

    /// The gain map of `source` (a captured HEIF), already rotated to the
    /// displayed orientation, or nil when the photo carries none.
    static func gainMap(of source: Data) -> CIImage? {
        CIImage(data: source, options: [.auxiliaryHDRGainMap: true, .applyOrientationProperty: true, .colorSpace: NSNull()])
    }

    /// Writes `baked` (SDR, P3, already cropped to `window` of the oriented
    /// source) as a HEIF carrying the source's gain map cropped to the same
    /// window. `overlayCoverage` is an alpha-only image at the baked size
    /// where the overlay was drawn; the gain there is forced to none.
    static func compose(source: Data,
                        baked: CGImage,
                        window: CGRect,
                        overlayCoverage: CGImage?,
                        context: CIContext = CIContext()) -> Data? {
        guard let gain = gainMap(of: source),
              let sourceSize = orientedSize(of: source) else { return nil }
        // Gain map pixels per source pixel (1/2 on this hardware, not assumed).
        let scaleX = gain.extent.width / sourceSize.width
        let scaleY = gain.extent.height / sourceSize.height
        // CIImage has a bottom-left origin; the window is top-left.
        let flippedY = sourceSize.height - window.maxY
        let gainWindow = CGRect(x: window.minX * scaleX, y: flippedY * scaleY,
                                width: window.width * scaleX, height: window.height * scaleY).integral
        let cropped = gain.cropped(to: gainWindow)
            .transformed(by: CGAffineTransform(translationX: -gainWindow.minX, y: -gainWindow.minY))
        let width = Int(cropped.extent.width), height = Int(cropped.extent.height)

        // Gain values are data, not colour: moved as raw 8-bit gray with no
        // colour conversion (a CI blend would gamma-shift them).
        var pixels = [UInt8](repeating: 0, count: width * height)
        context.render(cropped, toBitmap: &pixels, rowBytes: width,
                       bounds: CGRect(x: 0, y: 0, width: width, height: height),
                       format: .L8, colorSpace: nil)

        if let overlayCoverage {
            var alpha = [UInt8](repeating: 0, count: width * height)
            let drawn = alpha.withUnsafeMutableBytes { buffer -> Bool in
                guard let coverageContext = CGContext(data: buffer.baseAddress, width: width, height: height,
                                                      bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                                      bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue) else { return false }
                coverageContext.interpolationQuality = .medium
                coverageContext.draw(overlayCoverage, in: CGRect(x: 0, y: 0, width: width, height: height))
                return true
            }
            guard drawn else { return nil }
            // Under the overlay the gain falls to 0 (no boost), in proportion to coverage.
            for index in 0..<pixels.count where alpha[index] != 0 {
                pixels[index] = UInt8(Int(pixels[index]) * (255 - Int(alpha[index])) / 255)
            }
        }

        guard let source = CGImageSourceCreateWithData(source as CFData, nil),
              var auxInfo = CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, kCGImageAuxiliaryDataTypeHDRGainMap) as? [String: Any],
              var properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let output = CFDataCreateMutable(nil, 0),
              let destination = CGImageDestinationCreateWithData(output, UTType.heic.identifier as CFString, 1, nil)
        else { return nil }
        auxInfo[kCGImageAuxiliaryDataInfoData as String] = Data(pixels)
        auxInfo[kCGImageAuxiliaryDataInfoDataDescription as String] = [
            "Width": width, "Height": height, "BytesPerRow": width,
            "PixelFormat": (auxInfo[kCGImageAuxiliaryDataInfoDataDescription as String] as? [String: Any])?["PixelFormat"] ?? 1278226488,
        ] as [String: Any]
        // The picture is upright after baking, and its size is no longer the capture's.
        properties[kCGImagePropertyOrientation as String] = 1
        for key in [kCGImagePropertyPixelWidth, kCGImagePropertyPixelHeight, kCGImagePropertyTIFFDictionary] {
            properties[key as String] = nil
        }
        if var tiff = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])?[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
            tiff[kCGImagePropertyTIFFOrientation as String] = 1
            properties[kCGImagePropertyTIFFDictionary as String] = tiff
        }
        CGImageDestinationAddImage(destination, baked, properties as CFDictionary)
        CGImageDestinationAddAuxiliaryDataInfo(destination, kCGImageAuxiliaryDataTypeHDRGainMap, auxInfo as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    private static func orientedSize(of data: Data) -> CGSize? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? CGFloat,
              let h = props[kCGImagePropertyPixelHeight] as? CGFloat else { return nil }
        let orientation = (props[kCGImagePropertyOrientation] as? UInt32) ?? 1
        return orientation >= 5 ? CGSize(width: h, height: w) : CGSize(width: w, height: h)
    }
}
