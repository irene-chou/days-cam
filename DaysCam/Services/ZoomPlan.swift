import CoreGraphics

/// The lens layout of a capture device, as far as zoom is concerned.
///
/// A virtual device (triple, dual wide) starts at its widest lens, so its
/// `videoZoomFactor` 1.0 is the ultra-wide, not the main camera. Everything the
/// app shows is the "display" factor, where 1× is always the main camera; this
/// is the one place that tells the two apart (issue #279).
struct ZoomLens: Equatable {
    /// Whether the device's widest lens is an ultra-wide.
    var hasUltraWide = false
    /// `virtualDeviceSwitchOverVideoZoomFactors`: the device zoom at which each
    /// lens after the first takes over. Empty for a single-lens device.
    var switchOverFactors: [CGFloat] = []

    /// The device `videoZoomFactor` that shows as 1×: where the main camera
    /// takes over from the ultra-wide, else 1.0 (the main camera is the widest).
    var baseDeviceFactor: CGFloat {
        hasUltraWide ? (switchOverFactors.first ?? 2) : 1
    }

    /// Whether going from device factor `from` to `to` passes a lens
    /// switch-over: one lies after the lower factor, up to and including the
    /// higher.
    func crossesSwitchOver(from: CGFloat, to: CGFloat) -> Bool {
        let low = min(from, to), high = max(from, to)
        return switchOverFactors.contains { $0 > low && $0 <= high }
    }

    /// Display factor to device `videoZoomFactor`.
    func deviceFactor(forDisplay display: CGFloat) -> CGFloat { display * baseDeviceFactor }

    /// Device `videoZoomFactor` to display factor.
    func displayFactor(forDevice device: CGFloat) -> CGFloat { device / baseDeviceFactor }
}

/// One quick-zoom button's target, as a display factor.
struct ZoomPreset: Equatable, Identifiable {
    let displayFactor: CGFloat

    var id: CGFloat { displayFactor }
}

/// What a camera offers for zoom: its display range and the quick-zoom presets.
struct ZoomPlan: Equatable {
    let range: ZoomRange
    /// Ascending display factors.
    let presets: [ZoomPreset]

    /// The plan for a device with `lens` whose available device zoom spans
    /// `minAvailable`…`maxAvailable`.
    ///
    /// `offersCropPresets` is false for the front camera, which only offers 1×.
    /// Back cameras offer: the ultra-wide (when there is one), 1×, 2× always
    /// (the main camera cropped, when it is within range), and each telephoto
    /// at its own factor.
    static func make(lens: ZoomLens,
                     minAvailable: CGFloat,
                     maxAvailable: CGFloat,
                     offersCropPresets: Bool) -> ZoomPlan {
        let base = lens.baseDeviceFactor
        let range = CameraService.zoomRange(minAvailable: minAvailable, maxAvailable: maxAvailable, base: base)
        guard offersCropPresets else {
            return ZoomPlan(range: range, presets: [ZoomPreset(displayFactor: 1)])
        }
        var factors: [CGFloat] = []
        if lens.hasUltraWide, range.minimum < 1 { factors.append(rounded(range.minimum)) }
        factors.append(1)
        if range.maximum >= 2 { factors.append(2) }
        let telephotoSwitchOvers = lens.hasUltraWide ? Array(lens.switchOverFactors.dropFirst()) : lens.switchOverFactors
        for switchOver in telephotoSwitchOvers {
            let display = rounded(lens.displayFactor(forDevice: switchOver))
            if display > 1, display <= range.maximum { factors.append(display) }
        }
        let unique = Array(Set(factors)).sorted()
        return ZoomPlan(range: range, presets: unique.map { ZoomPreset(displayFactor: $0) })
    }

    /// To one decimal, so 0.5 and 3 are exactly those and never 0.4999 or 3.0001.
    private static func rounded(_ factor: CGFloat) -> CGFloat {
        (factor * 10).rounded() / 10
    }
}
