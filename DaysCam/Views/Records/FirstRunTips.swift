import Foundation

/// Which first-run hints the user has seen (PRD 2.0 FR-18.8, FR-22.3). App
/// level, not per record, with no reset UI.
///
/// Debug builds started with any `-UITest…` argument count every hint as
/// seen, so the hints do not cover what existing UI tests tap; add
/// `-UITestShowTips` to see them, starting unseen each launch.
final class FirstRunTips {
    /// The app's one instance.
    static let shared = makeShared()

    static let viewerCoachKey = "dayscam.tips.viewerCoachSeen"
    static let exportIntroKey = "dayscam.tips.exportIntroSeen"

    private let defaults: UserDefaults
    private let seenByDefault: Bool

    /// - Parameter seenByDefault: What a hint that was never marked counts as.
    init(defaults: UserDefaults = .standard, seenByDefault: Bool = false) {
        self.defaults = defaults
        self.seenByDefault = seenByDefault
    }

    private static func makeShared() -> FirstRunTips {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        let isUITest = arguments.contains { $0.hasPrefix("-UITest") }
        let showsTips = arguments.contains("-UITestShowTips")
        if showsTips {
            UserDefaults.standard.removeObject(forKey: Self.viewerCoachKey)
            UserDefaults.standard.removeObject(forKey: Self.exportIntroKey)
        }
        return FirstRunTips(defaults: .standard, seenByDefault: isUITest && !showsTips)
        #else
        return FirstRunTips()
        #endif
    }

    /// The viewer's pointer bubble has been dismissed.
    var viewerCoachSeen: Bool { seen(Self.viewerCoachKey) }
    /// The first-export comparison has been answered, or the batch preview seen.
    var exportIntroSeen: Bool { seen(Self.exportIntroKey) }

    func markViewerCoachSeen() { defaults.set(true, forKey: Self.viewerCoachKey) }

    /// Also called by the batch preview (FR-22.3: seeing it counts).
    func markExportIntroSeen() { defaults.set(true, forKey: Self.exportIntroKey) }

    private func seen(_ key: String) -> Bool {
        (defaults.object(forKey: key) as? Bool) ?? seenByDefault
    }
}
