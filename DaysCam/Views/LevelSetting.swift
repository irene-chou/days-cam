import Foundation

/// The camera's 水平儀 switch (#687): app level, not per record, off by
/// default like the system camera's.
///
/// Debug builds started with any `-UITest…` argument start from the default
/// (off) once per launch, so a test that turns it on does not leak into the
/// next; `-UITestKeepLevel` keeps what is stored.
struct LevelSetting {
    static let key = "dayscam.camera.levelOn"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Whether the viewfinder shows the level; `false` until the user turns
    /// it on.
    var isOn: Bool {
        (defaults.object(forKey: Self.key) as? Bool) ?? false
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
              !arguments.contains("-UITestKeepLevel") else { return }
        UserDefaults.standard.removeObject(forKey: key)
    }()
    #endif
}
