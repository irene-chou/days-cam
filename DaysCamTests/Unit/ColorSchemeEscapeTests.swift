import SwiftUI
import XCTest
@testable import DaysCam

/// PR #103 review (2026-09-27) doubted that `PermissionGuidanceView`'s
/// `.preferredColorScheme(nil)` (applied in `CameraScreen`, on the node
/// wrapping `PermissionGuidanceView()`) actually cancels the app root's
/// `.preferredColorScheme(.light)` for that subtree — general SwiftUI
/// folklore says `.preferredColorScheme` bubbles to the nearest enclosing
/// *presentation* (here, the app's one window) rather than behaving like a
/// normal environment value a descendant can locally override back to
/// "unset" with `nil`.
///
/// Confirmed empirically here: **the review's suspicion was right.**
/// `.preferredColorScheme(nil)` does *not* escape an ancestor's forced
/// `.light` — `PermissionGuidanceView` would have stayed light on every
/// device regardless of the system's actual appearance. `CameraScreen`
/// switched to an explicit `Environment(\.colorScheme)` override instead
/// (read from `UIScreen.main.traitCollection`, which is *not* affected by
/// the app's own `overrideUserInterfaceStyle`), which this file also
/// verifies does correctly escape.
///
/// All three tests build the same shape `CameraScreen` actually uses (an
/// ancestor applying `.preferredColorScheme(.light)` to a subtree that
/// contains a nested view trying to opt back out) inside a real
/// `UIHostingController`/`UIWindow`, with the window's own trait
/// environment forced to `.dark` (standing in for "the system is in Dark
/// Mode") — the same layering `CameraScreen` sits in on a real device. A
/// `ColorSchemeSpy` sits *inside* the opting-out descendant itself, not
/// beside it, and reports every value it observes (not just the first) —
/// both details mattered: an earlier version of this file put the spy
/// outside the descendant's scope (always read the window's own base
/// environment, no matter what either modifier did) and only sampled once
/// via `onAppear` (too early — `.preferredColorScheme`'s effect on the
/// window isn't visible yet at that point). Either mistake alone made every
/// case "pass" for the wrong reason; `testDescendantWithNoOverride...`
/// below is a negative control that would have caught the first one.
@MainActor
final class ColorSchemeEscapeTests: XCTestCase {
    /// Hosts `tree` in a real window forced to `.dark` (simulating system
    /// Dark Mode with no app-level override) and returns the last value a
    /// `ColorSchemeSpy` somewhere inside it reported.
    private func resolvedColorScheme(makeTree: (@escaping (ColorScheme) -> Void) -> some View) -> ColorScheme? {
        var resolved: ColorScheme?
        let tree = makeTree { scheme in resolved = scheme }

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        window.overrideUserInterfaceStyle = .dark
        let hosting = UIHostingController(rootView: tree)
        window.rootViewController = hosting
        window.makeKeyAndVisible()
        hosting.view.layoutIfNeeded()

        // `.preferredColorScheme`'s effect on the window isn't visible
        // synchronously within the first `onAppear` pass — pump the run
        // loop for a bit and let `ColorSchemeSpy`'s `onChange` catch any
        // later update, rather than trusting only the very first
        // `onAppear` callback.
        let deadline = Date().addingTimeInterval(0.6)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        return resolved
    }

    func testDescendantWithNoOverrideStaysAtTheAncestorsForcedLight() {
        // Baseline/negative control: with no override at all, the
        // ancestor's `.light` should reach a plain descendant — confirms
        // the harness genuinely reads through the ancestor/descendant
        // structure, so the other two tests' results can be trusted.
        let resolved = resolvedColorScheme { onResolve in
            AncestorForcingLight {
                ColorSchemeSpy(onResolve: onResolve)
            }
        }
        XCTAssertEqual(resolved, .light)
    }

    func testPreferredColorSchemeNilDoesNotEscapeAnAncestorsForcedLight() {
        // This is the PR #103 review's exact concern, confirmed: the
        // descendant stays at the ancestor's forced `.light` — the window's
        // real `.dark` environment never reaches it. If this ever starts
        // failing (e.g. after an Xcode/SDK upgrade making `nil` behave like
        // ordinary environment propagation), `CameraScreen` could switch
        // back to the simpler `.preferredColorScheme(nil)` again.
        let resolved = resolvedColorScheme { onResolve in
            AncestorForcingLight {
                DescendantOptingOutViaPreferredColorScheme(onResolve: onResolve)
            }
        }
        XCTAssertEqual(resolved, .light)
    }

    func testEnvironmentColorSchemeOverrideEscapesAnAncestorsForcedPreferredColorScheme() {
        // The fix `CameraScreen`/`PermissionGuidanceView` actually ship: a
        // descendant explicitly setting `Environment(\.colorScheme)` (not
        // `.preferredColorScheme`) wins for its own subtree no matter what
        // an ancestor's `.preferredColorScheme` did.
        let resolved = resolvedColorScheme { onResolve in
            AncestorForcingLight {
                DescendantOptingOutViaEnvironmentOverride(colorScheme: .dark, onResolve: onResolve)
            }
        }
        XCTAssertEqual(resolved, .dark)
    }
}

/// Stands in for `CameraScreen.body`'s `.preferredColorScheme(.light)` —
/// applied to a view that *contains* `content`, exactly like
/// `content.preferredColorScheme(.light)` wraps the tree
/// `PermissionGuidanceView()` sits inside.
private struct AncestorForcingLight<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack { content }
            .preferredColorScheme(.light)
    }
}

/// Stands in for the pre-fix `PermissionGuidanceView().preferredColorScheme(nil)`
/// call site in `CameraScreen`: the spy that reports its resolved
/// `Environment(\.colorScheme)` sits *inside* the `nil`-scoped view, not
/// beside it.
private struct DescendantOptingOutViaPreferredColorScheme: View {
    let onResolve: (ColorScheme) -> Void

    var body: some View {
        ColorSchemeSpy(onResolve: onResolve)
            .preferredColorScheme(nil)
    }
}

/// Stands in for the shipped fix: a descendant setting
/// `Environment(\.colorScheme)` directly with a value it read itself (in
/// production, via `UIScreen.main.traitCollection` — not exercised here,
/// this test only checks that an explicit override escapes the ancestor).
private struct DescendantOptingOutViaEnvironmentOverride: View {
    let colorScheme: ColorScheme
    let onResolve: (ColorScheme) -> Void

    var body: some View {
        ColorSchemeSpy(onResolve: onResolve)
            .environment(\.colorScheme, colorScheme)
    }
}

/// Reads `Environment(\.colorScheme)` at the point it's inserted and
/// reports every value it observes, since a `@Environment` value can't be
/// read directly from outside a `View`'s `body`.
private struct ColorSchemeSpy: View {
    @Environment(\.colorScheme) private var colorScheme
    let onResolve: (ColorScheme) -> Void

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .onAppear { onResolve(colorScheme) }
            .onChange(of: colorScheme) { onResolve($0) }
    }
}
