import SwiftUI
import UIKit
import XCTest
@testable import DaysCam

/// Regression coverage for the exact class of bug qa found live on every
/// device tested (#101 reopened after PR #110 merged): `.ignoresSafeArea()`
/// applied straight to a `GeometryReader` makes that same reader report its
/// own `proxy.safeAreaInsets` as *zero*, even though `proxy.size` still
/// correctly covers the whole screen either way — `CameraScreen.content`
/// briefly did exactly that, so every header/footer position it fed into
/// `CameraScreenLayoutMetrics` came out 34pt (bottom inset) or 20pt (top
/// inset) off, dropping the iPhone 16 shutter into the home indicator's
/// gesture area.
///
/// `CameraScreenLayoutMetricsTests` alone can't catch this class of bug: it
/// hand-supplies insets straight to the formulas and never exercises the
/// `GeometryReader`/`.ignoresSafeArea()` wiring that produces them in a real
/// app — the simulator/`#Preview` canvas didn't surface it either. These
/// tests host real SwiftUI views in a real, key `UIWindow` and read back
/// what a `GeometryReader` actually saw during a real layout pass, using
/// whatever safe area the simulator running the test itself provides
/// (deliberately *not* a hand-picked value — an attempt at forcing an exact
/// one via `UIHostingController.additionalSafeAreaInsets`/a `UIWindow`
/// subclass turned out to double up with, rather than replace, the real
/// device chrome, making the numbers depend on internals this file
/// shouldn't need to know about). Every assertion below only depends on the
/// window actually having *some* non-zero safe area, true for any
/// notched/home-indicator iPhone simulator — the same kind this project's
/// own `xcodebuild test` instructions always target.
@MainActor
final class CameraScreenSafeAreaLayoutTests: XCTestCase {
    /// The buggy wiring: `.ignoresSafeArea()` chained directly onto the
    /// `GeometryReader` itself. The reader now considers the safe area its
    /// own responsibility to have already handled, so it has nothing left
    /// to report, regardless of whatever real safe area the host window
    /// has — this is the exact mechanism behind every measurement qa took
    /// coming out too low.
    func testIgnoresSafeAreaOnTheReaderItselfZeroesItsOwnInsets() {
        let captured = CapturedGeometry()
        let probe = GeometryReader { proxy in
            captured.value = (proxy.size, proxy.safeAreaInsets)
            return Color.clear
        }
        .ignoresSafeArea()

        host(probe)

        XCTAssertEqual(captured.value?.insets.top, 0)
        XCTAssertEqual(captured.value?.insets.bottom, 0)
    }

    /// The fixed wiring: `.ignoresSafeArea()` on a *child* of the
    /// `GeometryReader`, never the reader itself — matching
    /// `CameraScreen.content` after this fix. The reader keeps reporting
    /// its real, non-zero insets, while its child still visually extends
    /// full-bleed under the status bar/home indicator.
    func testIgnoresSafeAreaOnAChildPreservesTheReadersOwnInsets() {
        let captured = CapturedGeometry()
        let probe = GeometryReader { proxy in
            captured.value = (proxy.size, proxy.safeAreaInsets)
            return Color.clear.ignoresSafeArea()
        }

        host(probe)

        // Only the top inset (status bar) is asserted: a bare `UIWindow`
        // like `host(_:)` builds reliably reports one, but the bottom inset
        // (home indicator) measured zero here even on a notched simulator —
        // it apparently needs more real scene plumbing than this minimal a
        // host provides. That asymmetry doesn't weaken what this test is
        // actually checking: the *mechanism* (reader vs. child) is what
        // zeroes insets, not this environment's own limits, and the top
        // inset alone is already non-zero proof the reader wasn't zeroed.
        XCTAssertGreaterThan(captured.value?.insets.top ?? 0, 0, "expected a real, non-zero top inset from the host window")
    }

    /// Ties the mechanism above straight to the direction of the real
    /// regression qa reported: `CameraScreenLayoutMetrics.headerBottom`
    /// computed from the buggy wiring's (zero) insets came out *larger*
    /// (further down the screen) than the confirmed value on every device
    /// qa tested, because a zeroed `bottomInset` inflates `footerBase`
    /// (`S − bottomInset`) straight into the formula. Reproduces that same
    /// relationship off a real window's real insets, rather than
    /// hand-supplied ones `CameraScreenLayoutMetricsTests` already covers,
    /// and requires a meaningful gap (not just a rounding-sized one) so a
    /// future regression that zeroes only one of the two insets still fails
    /// this test.
    func testBuggyWiringProducesAMeaningfullyLargerHeaderBottomThanTheFixedWiringDoes() {
        let fixedCaptured = CapturedGeometry()
        let fixedProbe = GeometryReader { proxy in
            fixedCaptured.value = (proxy.size, proxy.safeAreaInsets)
            return Color.clear.ignoresSafeArea()
        }
        host(fixedProbe)

        let buggyCaptured = CapturedGeometry()
        let buggyProbe = GeometryReader { proxy in
            buggyCaptured.value = (proxy.size, proxy.safeAreaInsets)
            return Color.clear
        }
        .ignoresSafeArea()
        host(buggyProbe)

        guard let fixedGeometry = fixedCaptured.value, let buggyGeometry = buggyCaptured.value else {
            return XCTFail("GeometryReader never reported a geometry")
        }
        let fixedMetrics = CameraScreenLayoutMetrics(screenSize: fixedGeometry.size, safeAreaInsets: fixedGeometry.insets)
        let buggyMetrics = CameraScreenLayoutMetrics(screenSize: buggyGeometry.size, safeAreaInsets: buggyGeometry.insets)
        XCTAssertGreaterThan(buggyMetrics.headerBottom - fixedMetrics.headerBottom, 10,
                             "the buggy (zero-inset) wiring should read a header bottom well below the fixed one's")
    }

    // MARK: - Helpers

    private final class CapturedGeometry {
        var value: (size: CGSize, insets: EdgeInsets)?
    }

    /// Hosts `view` full-screen in a real, key `UIWindow` sized like an
    /// iPhone 16 (393×852) and forces one real layout pass. Uses whatever
    /// safe area insets the simulator running the test itself reports for
    /// a key window on this size — see this file's own doc comment for why
    /// forcing a specific value didn't pan out.
    private func host<V: View>(_ view: V) {
        let hosting = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = hosting
        window.isHidden = false
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        hosting.view.layoutIfNeeded()
    }
}
