import SwiftUI

extension View {
    @ViewBuilder
    func nanZipGlassCard(cornerRadius: CGFloat = 16) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            self.glassEffect(
                .regular.tint(Color.accentColor.opacity(0.055)),
                in: shape
            )
        } else {
            self
                .background(.regularMaterial)
                .clipShape(shape)
                .overlay {
                    shape.stroke(.separator.opacity(0.32), lineWidth: 1)
                }
        }
    }
}

struct NanZipGlassContainer<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    init(spacing: CGFloat = 12, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    @ViewBuilder
    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing, content: content)
        } else {
            content()
        }
    }
}

struct NanZipProminentButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    init(action: @escaping () -> Void, @ViewBuilder label: @escaping () -> Label) {
        self.action = action
        self.label = label
    }

    @ViewBuilder
    var body: some View {
        if #available(macOS 26.0, *) {
            Button(action: action, label: label)
                .buttonStyle(.glassProminent)
                .controlSize(.large)
        } else {
            Button(action: action, label: label)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
    }
}

struct NanZipGlassButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    init(action: @escaping () -> Void, @ViewBuilder label: @escaping () -> Label) {
        self.action = action
        self.label = label
    }

    @ViewBuilder
    var body: some View {
        if #available(macOS 26.0, *) {
            Button(action: action, label: label)
                .buttonStyle(.glass)
        } else {
            Button(action: action, label: label)
                .buttonStyle(.bordered)
        }
    }
}
