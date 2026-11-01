import Foundation

/// The camera's 疊字預覽 switch (PRD 2.0 FR-20.9): app level, not per record,
/// on by default, also for users upgrading from before it existed.
///
/// Debug builds started with any `-UITest…` argument start from the default
/// (on) once per launch, so a test that turns it off does not leak into the
/// next; `-UITestKeepOverlayPreview` keeps what is stored (to check it
/// survives a relaunch) and `-UITestOverlayPreviewOff` starts off.
struct OverlayPreviewSetting {
    static let key = "dayscam.camera.overlayPreviewOn"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Whether the viewfinder draws the record's overlay; `true` until the
    /// user turns it off.
    var isOn: Bool {
        (defaults.object(forKey: Self.key) as? Bool) ?? true
    }

    func set(_ isOn: Bool) {
        defaults.set(isOn, forKey: Self.key)
    }

    /// Applies the `-UITest…` arguments to the standard defaults, once per
    /// process; a no-op in release builds.
    static func applyUITestArguments() {
        #if DEBUG
        _ = uiTestReset
        #endif
    }

    #if DEBUG
    private static let uiTestReset: Void = {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains(where: { $0.hasPrefix("-UITest") }),
              !arguments.contains("-UITestKeepOverlayPreview") else { return }
        if arguments.contains("-UITestOverlayPreviewOff") {
            UserDefaults.standard.set(false, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }()
    #endif
}
