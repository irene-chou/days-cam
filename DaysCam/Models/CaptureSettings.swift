import Foundation

/// The aspect ratio the shutter crops to (PRD 0.2 FR-7.7, FR-5.7′).
///
/// The sensor always delivers a 4:3 image (PRD 0.2 §6); `ImageCropper` center
/// -crops it down to whichever of these three ratios is selected before the
/// overlay is baked in.
enum CaptureAspectRatio: String, Codable, CaseIterable, Equatable {
    case threeByFour
    case oneByOne
    case nineBySixteen

    /// This ratio's short side divided by its long side, e.g. `0.75` for
    /// 3:4. Used by `ImageCropper` to decide which side of the 4:3 original
    /// needs to shrink.
    var shortToLongRatio: Double {
        switch self {
        case .threeByFour: return 3.0 / 4.0
        case .oneByOne: return 1.0
        case .nineBySixteen: return 9.0 / 16.0
        }
    }
}

/// Flash setting cycled by the toolbar's flash button (PRD 0.2 FR-7.4).
enum FlashMode: String, Codable, CaseIterable, Equatable {
    case off
    case auto
    case on

    /// What one tap moves to: 關 → 自動 → 開 → 關 (PRD 0.2 FR-7.4).
    var next: FlashMode {
        switch self {
        case .off: return .auto
        case .auto: return .on
        case .on: return .off
        }
    }
}

/// Timer setting cycled by the toolbar's timer button (PRD 0.2 FR-7.5).
///
/// The raw value is the countdown length in seconds, which is also what the
/// countdown UI (TASK-21) needs to seed its tick count.
enum TimerSetting: Int, Codable, CaseIterable, Equatable {
    case off = 0
    case threeSeconds = 3
    case tenSeconds = 10

    /// What one tap moves to: 關 → 3 秒 → 10 秒 → 關 (PRD 0.2 FR-7.5).
    var next: TimerSetting {
        switch self {
        case .off: return .threeSeconds
        case .threeSeconds: return .tenSeconds
        case .tenSeconds: return .off
        }
    }
}

/// Colour tone of the captured photo, five steps from cool to warm.
///
/// `.standard` means no processing: the photo is exactly what the sensor
/// delivered. The two cool and two warm steps shift the white balance
/// towards blue or orange; the baking itself lives outside this model.
enum ColorTone: String, Codable, CaseIterable, Equatable {
    case cool2
    case cool1
    case standard
    case warm1
    case warm2

    /// The tone a fresh install starts with: no processing.
    static let `default`: ColorTone = .standard

    /// Signed distance from `.standard`: -2 for `.cool2` up to 2 for
    /// `.warm2`. Meant as an index for baking and UI, not as a display name.
    var step: Int {
        switch self {
        case .cool2: return -2
        case .cool1: return -1
        case .standard: return 0
        case .warm1: return 1
        case .warm2: return 2
        }
    }
}
