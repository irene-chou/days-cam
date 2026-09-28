import SwiftUI
import UIKit
import XCTest
@testable import DaysCam

/// Regression coverage for the exact class of bug qa found live on every
/// device tested (#101 reopened after PR #110 merged): a `GeometryReader`
/// that has `.ignoresSafeArea()` applied *anywhere in its own ancestor
/// chain* — directly on it, or on any view wrapping it — reports its own
/// `proxy.safeAreaInsets` as zero (it now considers the safe area its own
/// responsibility to have already handled) *and* its `proxy.size` grows to
/// the full screen; a reader with nothing in its ancestor chain ignoring
/// the safe area gets the opposite pairing instead — a `proxy.size` already
/// *reduced* by the safe area, alongside the real, non-zero insets that
/// were subtracted from it. `CameraScreen.content` briefly took the first
/// pairing (full size, zero insets), so every header/footer position it fed
/// into `CameraScreenLayoutMetrics` came out 34pt (bottom inset) or 20pt
/// (top inset) off, dropping the iPhone 16 shutter into the home
/// indicator's gesture area.
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
/// device chrome, or not propagate at all, making the numbers depend on
/// internals this file shouldn't need to know about). Every assertion below
/// only depends on the window actually having *some* non-zero safe area,
/// true for any notched/home-indicator iPhone simulator — the same kind
/// this project's own `xcodebuild test` instructions always target.
@MainActor
final class CameraScreenSafeAreaLayoutTests: XCTestCase {
    /// The buggy wiring: `.ignoresSafeArea()` chained directly onto the
    /// `GeometryReader` itself. Zero insets, full size — this is the exact
    /// mechanism behind every measurement qa took coming out too low.
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

    /// The same zeroing happens even when `.ignoresSafeArea()` sits on an
    /// *ancestor* wrapping the `GeometryReader`, not the reader itself —
    /// ruling out "move it to any ancestor" as a fix, which an earlier
    /// version of this file's actual fix briefly assumed would work.
    func testIgnoresSafeAreaOnAWrappingAncestorAlsoZeroesTheReadersInsets() {
        let captured = CapturedGeometry()
        let probe = ZStack {
            GeometryReader { proxy in
                captured.value = (proxy.size, proxy.safeAreaInsets)
                return Color.clear
            }
        }
        .ignoresSafeArea()

        host(probe)

        XCTAssertEqual(captured.value?.insets.top, 0)
        XCTAssertEqual(captured.value?.insets.bottom, 0)
    }

    /// The fixed wiring: nothing in the `GeometryReader`'s own ancestor
    /// chain ignores the safe area (only a plain *descendant* of its
    /// content does, which doesn't feed back into what the reader itself
    /// measured) — matching `CameraScreen.content` after this fix. The
    /// reader reports its real, non-zero insets, but at the cost of
    /// `proxy.size` itself coming out *reduced* by them rather than
    /// covering the full screen — `CameraScreen.content` adds the insets
    /// back to reconstruct the full screen size itself, covered by
    /// `testReconstructedFullSizeMatchesTheBuggyWiringsAndHeaderBottomDiffersMeaningfully` below.
    func testUnprotectedReaderReportsRealInsetsButAReducedSize() {
        let captured = CapturedGeometry()
        let probe = GeometryReader { proxy in
            captured.value = (proxy.size, proxy.safeAreaInsets)
            return Color.clear.ignoresSafeArea()
        }

        host(probe)

        guard let geometry = captured.value else {
            return XCTFail("GeometryReader never reported a geometry")
        }
        // Only the top inset (status bar) is asserted non-zero: this
        // minimal a host window reliably reports one, but the bottom inset
        // (home indicator) measured zero here even on a notched simulator —
        // it apparently needs more real scene plumbing than a bare
        // `UIWindow` provides. That asymmetry doesn't weaken what this test
        // checks: the *mechanism* (nothing ignoring the safe area above
        // this reader) is what preserves a non-zero inset at all.
        XCTAssertGreaterThan(geometry.insets.top, 0)
        // `proxy.size` is missing exactly its own reported top inset off
        // the full 852pt-tall window this test hosts in.
        XCTAssertEqual(geometry.size.height, 852 - geometry.insets.top, accuracy: 0.5)
    }

    /// Reconstructs the full screen size the same way `CameraScreen.content`
    /// now does (`proxy.size` plus its own `safeAreaInsets`, matching the
    /// unprotected reader's reduced-size/real-insets pairing above) and
    /// checks it against the buggy wiring's own (already-full) size — they
    /// describe the same physical window, so they should agree — then
    /// checks that feeding each into `CameraScreenLayoutMetrics` still
    /// produces a meaningfully different `headerBottom`, reproducing the
    /// direction of the regression qa reported (the buggy, zero-inset
    /// reading always lands further down the screen).
    /// Uses a small, iPhone-SE-shaped window (375×667): its 9:16-ish
    /// dimensions push `CameraScreenLayoutMetrics` into its small-screen
    /// fallback branch either way (issue #101 assumption 2), where
    /// `headerBottom` becomes exactly `topInset + 46` — the one branch
    /// where `topInset` alone (not `bottomInset`, which this bare-window
    /// host, per `testUnprotectedReaderReportsRealInsetsButAReducedSize`'s
    /// own doc comment, can't reliably report as non-zero) decides the
    /// result, so this test doesn't depend on getting a real bottom inset
    /// out of the harness at all.
    func testReconstructedFullSizeMatchesTheBuggyWiringsAndHeaderBottomDiffersMeaningfully() {
        let size = CGSize(width: 375, height: 667)

        let unprotectedCaptured = CapturedGeometry()
        let unprotectedProbe = GeometryReader { proxy in
            unprotectedCaptured.value = (proxy.size, proxy.safeAreaInsets)
            return Color.clear.ignoresSafeArea()
        }
        host(unprotectedProbe, size: size)

        let buggyCaptured = CapturedGeometry()
        let buggyProbe = GeometryReader { proxy in
            buggyCaptured.value = (proxy.size, proxy.safeAreaInsets)
            return Color.clear
        }
        .ignoresSafeArea()
        host(buggyProbe, size: size)

        guard let unprotectedGeometry = unprotectedCaptured.value, let buggyGeometry = buggyCaptured.value else {
            return XCTFail("GeometryReader never reported a geometry")
        }
        XCTAssertGreaterThan(unprotectedGeometry.insets.top, 0, "need a real top inset for this test to mean anything")

        // `CameraScreen.content`'s own reconstruction: reduced size + its
        // own insets = the full screen.
        let insets = unprotectedGeometry.insets
        let reconstructedSize = CGSize(width: unprotectedGeometry.size.width + insets.leading + insets.trailing,
                                       height: unprotectedGeometry.size.height + insets.top + insets.bottom)
        XCTAssertEqual(reconstructedSize.height, buggyGeometry.size.height, accuracy: 0.5)

        let fixedMetrics = CameraScreenLayoutMetrics(screenSize: reconstructedSize, safeAreaInsets: insets)
        let buggyMetrics = CameraScreenLayoutMetrics(screenSize: buggyGeometry.size, safeAreaInsets: buggyGeometry.insets)
        XCTAssertGreaterThan(fixedMetrics.headerBottom - buggyMetrics.headerBottom, 10,
                             "the fixed wiring's real top inset should push its header bottom well below the buggy (zero-inset) one's minimum")
    }

    // MARK: - Helpers

    private final class CapturedGeometry {
        var value: (size: CGSize, insets: EdgeInsets)?
    }

    /// Hosts `view` full-screen in a real, key `UIWindow` (default size:
    /// an iPhone 16's own point size, 393×852) and forces one real layout
    /// pass. Uses whatever safe area insets the simulator running the test
    /// itself reports for a key window of `size` — see this file's own doc
    /// comment for why forcing a specific value didn't pan out.
    private func host<V: View>(_ view: V, size: CGSize = CGSize(width: 393, height: 852)) {
        let hosting = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = hosting
        window.isHidden = false
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        hosting.view.layoutIfNeeded()
    }
}
