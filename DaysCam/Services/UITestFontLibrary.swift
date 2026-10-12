#if DEBUG
import Combine
import Foundation

/// A font library for UI tests only (TASK-150), chosen by launch arguments in
/// debug builds: `-UITestFontSeed` marks every third downloadable font as
/// downloaded (so the list has downloaded rows drawn in their own names), and
/// `-UITestFontProgress` also shows one more font downloading, its progress
/// moving every 0.25s. Nothing touches the file system or the network.
@MainActor
final class UITestFontLibrary: FontShellControlling {
    let objectWillChange = ObservableObjectPublisher()
    let weightDownloadDidFinish = PassthroughSubject<FontDownloadID, Never>()

    private var seeded: Set<OverlayFontID> = []
    private var downloadingFont: OverlayFontID?
    private var progress = 0.0
    private var timer: Timer?

    /// The library the launch arguments ask for, or `nil` for the real one.
    static func fromLaunchArguments(_ arguments: [String]) -> UITestFontLibrary? {
        let seed = arguments.contains("-UITestFontSeed")
        let moving = arguments.contains("-UITestFontProgress")
        guard seed || moving else { return nil }
        return UITestFontLibrary(seedsFonts: seed, movesProgress: moving)
    }

    private init(seedsFonts: Bool, movesProgress: Bool) {
        let candidates = OverlayFontID.allCases.filter { $0 != .pingFang }
        if seedsFonts {
            seeded = Set(candidates.enumerated().filter { $0.offset % 3 == 0 }.map(\.element))
        }
        if movesProgress {
            downloadingFont = candidates.filter { !seeded.contains($0) }.dropFirst(5).first
            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.advance() }
            }
        }
    }

    private func advance() {
        objectWillChange.send()
        progress += 0.02
        if progress > 1 { progress = 0 }
    }

    func state(for fontID: OverlayFontID) -> FontState {
        if fontID == .pingFang || seeded.contains(fontID) { return .available }
        if fontID == downloadingFont { return .downloading(progress: progress) }
        return .notDownloaded
    }
    func cancel(_ fontID: OverlayFontID) {}
    func delete(_ fontID: OverlayFontID) -> Bool { false }
    func download(_ fontID: OverlayFontID) -> Bool { false }
    func prepare(_ fontID: OverlayFontID) async {}
    func prepare(_ fontID: OverlayFontID, weightID: String?) async {}
    func prepareAtLaunch(priority: OverlayFontID?) async {}
    func prepareAtLaunch(priority: OverlayFontID?, weightID: String?) async {}
    func cancelAllDownloads() {}
}
#endif
