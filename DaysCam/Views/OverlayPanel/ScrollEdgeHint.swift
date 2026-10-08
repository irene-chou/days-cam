import SwiftUI

/// Where a vertical scroll view is, as far as the "more below" hint needs
/// (TASK-58b): whether it scrolls at all, and whether there is more above or
/// below the visible part.
struct ScrollEdgeState: Equatable {
    var contentHeight: CGFloat = 0
    var containerHeight: CGFloat = 0
    var offsetY: CGFloat = 0
    var insetTop: CGFloat = 0
    var insetBottom: CGFloat = 0

    /// Slack for rounding, in points.
    private static let tolerance: CGFloat = 1

    /// Whether the content is taller than the visible area.
    var canScroll: Bool {
        contentHeight > containerHeight + Self.tolerance
    }

    /// Whether the scroll view has been scrolled away from the top.
    var showsTopFade: Bool {
        canScroll && offsetY > -insetTop + Self.tolerance
    }

    /// Whether there is more content below the visible part.
    var showsBottomFade: Bool {
        canScroll && offsetY + containerHeight < contentHeight + insetBottom - Self.tolerance
    }
}

private struct ScrollEdgeHint: ViewModifier {
    /// Height of the fade at each edge.
    static let fadeHeight: CGFloat = 24

    /// Space kept clear above the top fade, for content pinned at the top of
    /// the scroll view (the style tab's sub-tab row).
    let topInset: CGFloat
    /// Changing this flashes the scroll indicator once (only if it scrolls).
    let flashTrigger: AnyHashable

    @State private var state = ScrollEdgeState()

    func body(content: Content) -> some View {
        content
            .scrollIndicatorsFlash(onAppear: true)
            .scrollIndicatorsFlash(trigger: flashTrigger)
            .onScrollGeometryChange(for: ScrollEdgeState.self) { geometry in
                ScrollEdgeState(contentHeight: geometry.contentSize.height,
                                containerHeight: geometry.containerSize.height,
                                offsetY: geometry.contentOffset.y,
                                insetTop: geometry.contentInsets.top,
                                insetBottom: geometry.contentInsets.bottom)
            } action: { _, newState in
                state = newState
            }
            .overlay(alignment: .top) {
                fade(from: .top)
                    .opacity(state.showsTopFade ? 1 : 0)
                    .padding(.top, topInset)
            }
            .overlay(alignment: .bottom) {
                fade(from: .bottom)
                    .opacity(state.showsBottomFade ? 1 : 0)
            }
            .animation(.easeInOut(duration: 0.15), value: state.showsTopFade)
            .animation(.easeInOut(duration: 0.15), value: state.showsBottomFade)
    }

    /// A fade from the panel's own background at the edge to transparent
    /// toward the content; never takes taps.
    private func fade(from edge: VerticalEdge) -> some View {
        LinearGradient(colors: [CameraTheme.background, CameraTheme.background.opacity(0)],
                       startPoint: edge == .top ? .top : .bottom,
                       endPoint: edge == .top ? .bottom : .top)
            .frame(height: Self.fadeHeight)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

extension View {
    /// Hints that a vertical scroll view scrolls: a 24pt fade into the panel
    /// background at each edge that has more content beyond it, and one flash
    /// of the scroll indicator when the view appears or `flashTrigger`
    /// changes. Nothing shows when the content fits.
    func scrollEdgeHint(topInset: CGFloat = 0, flashTrigger: AnyHashable = 0) -> some View {
        modifier(ScrollEdgeHint(topInset: topInset, flashTrigger: flashTrigger))
    }
}
