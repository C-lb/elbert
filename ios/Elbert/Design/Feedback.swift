import SwiftUI
import UIKit

// MARK: - Haptics

/// Every action gets a response. On iOS a press has no hover, so the haptic is what
/// confirms the tap landed.
@MainActor
enum Haptics {
    enum Impact {
        case light, medium, heavy, soft, rigid

        var style: UIImpactFeedbackGenerator.FeedbackStyle {
            switch self {
            case .light: .light
            case .medium: .medium
            case .heavy: .heavy
            case .soft: .soft
            case .rigid: .rigid
            }
        }
    }

    /// A control was pressed.
    static func impact(_ impact: Impact = .light) {
        let generator = UIImpactFeedbackGenerator(style: impact.style)
        generator.prepare()
        generator.impactOccurred()
    }

    /// A value in a picker or segmented control changed.
    static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }

    /// An operation resolved. Pair with a visible message, never on its own.
    static func notify(_ role: SemanticRole) {
        let type: UINotificationFeedbackGenerator.FeedbackType = switch role {
        case .success: .success
        case .warning, .info: .warning
        case .danger: .error
        }
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }
}

// MARK: - Loaders

/// Ring spinner. For a button or a small inline action.
///
/// Sized off a type role so it matches the text it sits beside, roughly 1.15em by default,
/// never twice the cap height of the words next to it. Under reduced motion it breathes on
/// opacity instead of turning, because a reduced-motion user still needs to see a wait.
struct RingSpinner: View {
    var role: TypeRole = .caption
    var scale: CGFloat = 1.15
    var lineWidth: CGFloat = 2

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animating = false

    private var side: CGFloat { role.size * scale }

    var body: some View {
        Circle()
            .trim(from: 0, to: reduceMotion ? 1 : 0.72)
            .stroke(currentStyle, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .frame(width: side, height: side)
            .rotationEffect(.degrees(animating && !reduceMotion ? 360 : 0))
            .opacity(reduceMotion && animating ? 0.35 : 1)
            .animation(
                reduceMotion
                    ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                    : .linear(duration: 0.75).repeatForever(autoreverses: false),
                value: animating
            )
            .onAppear { animating = true }
            .accessibilityLabel("Loading")
    }

    private var currentStyle: some ShapeStyle { .foreground }
}

/// Skeleton. For content whose shape is already known and is arriving.
struct SkeletonBlock: View {
    var width: CGFloat?
    var height: CGFloat = 14
    var cornerRadius: CGFloat = Radius.sm

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shifted = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Theme.surface2)
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            .opacity(shifted ? 0.55 : 1)
            .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: shifted)
            .onAppear { if !reduceMotion { shifted = true } }
            .accessibilityHidden(true)
    }
}

// MARK: - Toast

/// A toast is a neutral surface with a coloured icon, so it reads without flooding the
/// screen with colour. Success and info auto-dismiss. Warning and danger persist until
/// acknowledged, because an error the user never saw is an error that did not report.
struct Toast: Identifiable, Equatable {
    let id = UUID()
    let role: SemanticRole
    let message: String

    var autoDismisses: Bool {
        switch role {
        case .success, .info: true
        case .warning, .danger: false
        }
    }

    var icon: Icon {
        switch role {
        case .success: .confirm
        case .info: .synced
        case .warning, .danger: .dismiss
        }
    }

    static func success(_ message: String) -> Toast { Toast(role: .success, message: message) }
    static func info(_ message: String) -> Toast { Toast(role: .info, message: message) }
    static func warning(_ message: String) -> Toast { Toast(role: .warning, message: message) }
    static func error(_ message: String) -> Toast { Toast(role: .danger, message: message) }
}

@MainActor
@Observable
final class ToastCentre {
    var current: Toast?

    private var dismissTask: Task<Void, Never>?

    func show(_ toast: Toast) {
        dismissTask?.cancel()
        current = toast
        Haptics.notify(toast.role)
        guard toast.autoDismisses else { return }
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        current = nil
    }
}

struct ToastView: View {
    let toast: Toast
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: Space.s3) {
            HouseIcon(icon: toast.icon, filled: toast.icon.hasDistinctFill, role: .body)
                .foregroundStyle(toast.role.base)

            Text(toast.message)
                .typeRole(.body)
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            if !toast.autoDismisses {
                Button(action: onDismiss) {
                    HouseIcon(icon: .dismiss, role: .caption)
                }
                .buttonStyle(HouseButtonStyle(tier: .icon, size: .small))
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(.vertical, Space.s3)
        .padding(.horizontal, Space.s4)
        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 1)
        )
        .houseShadow(.pop)
        .zIndex(ZLayer.toast)
    }
}

private struct ToastHost: ViewModifier {
    @Bindable var centre: ToastCentre

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let toast = centre.current {
                    ToastView(toast: toast) { centre.dismiss() }
                        .padding(.horizontal, Space.s4)
                        .padding(.bottom, Space.s5)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy(duration: 0.22), value: centre.current)
    }
}

extension View {
    func houseToast(_ centre: ToastCentre) -> some View {
        modifier(ToastHost(centre: centre))
    }
}

// MARK: - Semantic banner

/// A full-width notice. Semantic soft tint plus a hairline ring plus an icon and text.
/// No left stripe, ever.
struct HouseBanner: View {
    let role: SemanticRole
    let message: String
    var icon: Icon = .synced

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
            HouseIcon(icon: icon, filled: icon.hasDistinctFill, role: .body)
                .foregroundStyle(role.base)
            Text(message)
                .typeRole(.body)
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s3)
        .background(role.soft, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(role.line, lineWidth: 1)
        )
    }
}
