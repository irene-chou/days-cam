import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins

/// Shifts a photo cooler or warmer by one of the five `ColorTone` steps,
/// before any text is printed on it (#589).
///
/// Each step is a white-balance shift (`CITemperatureAndTint`) plus, on the
/// warm side, a touch of `CIVibrance`. Vibrance rather than saturation is what
/// keeps skin and red objects from turning: it lifts the muted colors and
/// leaves the already saturated ones alone. The numbers in `parameters` are
/// first-pass constants meant to be tuned against device photos.
enum ColorToneRenderer {
    /// How one tone step processes the photo.
    struct Parameters: Equatable {
        /// The `targetNeutral` temperature, in kelvin, against a 6500 K
        /// neutral. Below 6500 reads warmer, above reads cooler: measured on
        /// a gray photo, not the other way round as "compensating for a bluer
        /// light" would suggest.
        let targetTemperature: Float
        /// `CIVibrance` amount; 0 leaves saturation alone.
        let vibrance: Float
    }

    /// The neutral every target temperature is measured against.
    static let neutralTemperature: Float = 6500

    /// Every tone except `.standard`, which is never processed.
    static let parameters: [ColorTone: Parameters] = [
        .cool2: Parameters(targetTemperature: 8200, vibrance: 0),
        .cool1: Parameters(targetTemperature: 7300, vibrance: 0),
        .warm1: Parameters(targetTemperature: 5700, vibrance: 0.08),
        .warm2: Parameters(targetTemperature: 5000, vibrance: 0.15)
    ]

    /// One context for every photo; intermediates are not cached because each
    /// photo is processed once.
    private static let context = CIContext(options: [.cacheIntermediates: false])

    /// Returns `image` shifted to `tone`, in the input's color space (sRGB or
    /// Display P3) at 8 bits per component and the same pixel size.
    ///
    /// `.standard` returns `image` itself, untouched and without going through
    /// Core Image. Returns nil only if Core Image cannot render the result.
    static func apply(_ tone: ColorTone, to image: CGImage) -> CGImage? {
        guard let parameters = parameters[tone] else { return image }

        let input = CIImage(cgImage: image)
        let temperature = CIFilter.temperatureAndTint()
        temperature.inputImage = input
        temperature.neutral = CIVector(x: CGFloat(neutralTemperature), y: 0)
        temperature.targetNeutral = CIVector(x: CGFloat(parameters.targetTemperature), y: 0)
        var output = temperature.outputImage
        if parameters.vibrance != 0 {
            let vibrance = CIFilter.vibrance()
            vibrance.inputImage = output
            vibrance.amount = parameters.vibrance
            output = vibrance.outputImage
        }
        guard let output else { return nil }

        let colorSpace = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
            ?? CGColorSpace(name: CGColorSpace.sRGB)
        guard let colorSpace else { return nil }
        return context.createCGImage(output, from: input.extent, format: .RGBA8, colorSpace: colorSpace)
    }
}
