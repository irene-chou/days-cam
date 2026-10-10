import SwiftUI

/// Pins an SF Symbol to its Latin-script variant (TASK-100, #409).
///
/// Some symbols with letters in them — `character.textbox`,
/// `character.square.fill`, `textformat.size` — carry localized variants
/// that the system picks from the view's locale. Since TASK-95 (#398) the
/// app only declares 繁體中文, so those symbols switched to their Chinese
/// glyphs; the design wants the original Latin ones. Applying this to the
/// `Image` alone pins only the symbol — the rest of the screen (date
/// pickers, system buttons) keeps the app's Chinese locale (100.4).
private struct LatinSymbolModifier: ViewModifier {
    static let latin = Locale(identifier: "en")

    func body(content: Content) -> some View {
        content.environment(\.locale, Self.latin)
    }
}

extension View {
    /// Renders this symbol image in its Latin-script variant regardless of
    /// the app's locale; apply to the `Image(systemName:)` itself, never to a
    /// whole screen.
    func latinSymbol() -> some View {
        modifier(LatinSymbolModifier())
    }
}
