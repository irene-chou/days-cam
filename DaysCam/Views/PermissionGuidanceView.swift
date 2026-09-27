import SwiftUI
import UIKit

/// PRD S-5: covers the viewfinder area when camera permission is denied or
/// restricted (PRD §2.3). Pure presentation — `CameraScreen` decides when to
/// show it, based on `CameraService.permission.needsGuidance`.
///
/// The one screen that follows the system light/dark appearance instead of
/// `CameraTheme`'s fixed light theme (PRD 0.2 FR-14.1's sole exception,
/// human decision 2026-09-27). It cannot simply rely on inheriting
/// `Environment(\.colorScheme)` from the system, though: `CameraScreen`'s
/// root sets `.preferredColorScheme(.light)` (needed to force its own
/// `.alert`s light), and nesting `.preferredColorScheme(nil)` here to
/// cancel that back out does **not** work — verified in
/// `ColorSchemeEscapeTests` (PR #103 review, 2026-09-27) — `.preferredColorScheme`
/// does not behave like ordinary environment propagation across nested
/// calls within the same window/presentation, so a descendant's `nil`
/// cannot escape an ancestor's non-nil value. Instead, this view reads the
/// real system appearance itself via `UIScreen.main.traitCollection`
/// (`SystemAppearance`, below) — unaffected by any `overrideUserInterfaceStyle`
/// the app's own window carries — and applies it as an explicit
/// `Environment(\.colorScheme)` override, which *does* reliably win over an
/// ancestor's `.preferredColorScheme` for its own subtree.
struct PermissionGuidanceView: View {
    /// Pins the appearance instead of reading the live system value.
    /// `nil` (the production default, used by `CameraScreen`) means "track
    /// `SystemAppearance.current` live"; previews/tests pass an explicit
    /// value so they render deterministically regardless of the host
    /// Mac/simulator's own current appearance.
    var colorSchemeOverride: ColorScheme?

    @State private var liveSystemColorScheme: ColorScheme = SystemAppearance.current

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.fill")
                .font(.system(size: 32))
                .foregroundColor(CameraTheme.permissionInkSecondary)
            Text("需要相機權限")
                .font(.headline)
            Text("DaysCam 需要相機權限才能拍照並疊上天數。")
                .font(.subheadline)
                .foregroundColor(CameraTheme.permissionInkSecondary)
                .multilineTextAlignment(.center)
            Button("前往設定") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
            .buttonStyle(.borderedProminent)
            .tint(CameraTheme.active)
            .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CameraTheme.permissionBackground)
        .foregroundColor(CameraTheme.permissionInk)
        .environment(\.colorScheme, colorSchemeOverride ?? liveSystemColorScheme)
        .background(SystemAppearanceReader(colorScheme: $liveSystemColorScheme))
    }
}

/// The real system light/dark appearance, read from `UIScreen` rather than
/// this app's own window: `UIScreen.main.traitCollection` is not affected
/// by any `overrideUserInterfaceStyle` a window/view controller carries
/// (which is exactly what `.preferredColorScheme(.light)` sets on
/// `CameraScreen`'s window), so it reflects the setting in Settings /
/// Control Center / `xcrun simctl ui <id> appearance` regardless of what
/// the rest of this app forces.
private enum SystemAppearance {
    static var current: ColorScheme {
        UIScreen.main.traitCollection.userInterfaceStyle == .dark ? .dark : .light
    }
}

/// Bridges live changes to `SystemAppearance.current` into a SwiftUI
/// `Binding` via `traitCollectionDidChange`, the standard UIKit mechanism
/// for observing appearance changes — there's no equivalent SwiftUI-only
/// API that isn't itself subject to the same ancestor-override problem this
/// type exists to work around. Zero-sized and non-interactive: it exists
/// purely to host the callback, never to draw or receive touches.
private struct SystemAppearanceReader: UIViewControllerRepresentable {
    @Binding var colorScheme: ColorScheme

    func makeUIViewController(context: Context) -> ReaderViewController {
        let controller = ReaderViewController()
        controller.onChange = { colorScheme = $0 }
        return controller
    }

    func updateUIViewController(_ uiViewController: ReaderViewController, context: Context) {}

    final class ReaderViewController: UIViewController {
        var onChange: ((ColorScheme) -> Void)?

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
        }

        override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
            super.traitCollectionDidChange(previousTraitCollection)
            onChange?(SystemAppearance.current)
        }
    }
}

#Preview("Light") {
    ZStack {
        Color.gray
        PermissionGuidanceView(colorSchemeOverride: .light)
    }
}

#Preview("Dark") {
    ZStack {
        Color.gray
        PermissionGuidanceView(colorSchemeOverride: .dark)
    }
}
