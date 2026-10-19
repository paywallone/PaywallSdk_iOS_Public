import PaywallSDK
import SwiftUI

// MARK: - Layout

/// Grouped-form section: small header above, card body, optional footer (iOS Settings look).
struct FormSection<Content: View>: View {
    let title: String
    var footer: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
            VStack(alignment: .leading, spacing: 14) { content }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
            if let footer {
                Text(footer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            }
        }
    }
}

/// Collapsible group inside a section; `summary` is shown on the right while closed.
struct Collapsible<Content: View>: View {
    let title: String
    var summary: String?
    var systemImage: String?
    @ViewBuilder let content: Content
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { withAnimation(.easeInOut(duration: 0.2)) { open.toggle() } } label: {
                HStack(spacing: 10) {
                    if let systemImage {
                        Image(systemName: systemImage).foregroundStyle(Color.accentColor).frame(width: 22)
                    }
                    Text(title).foregroundStyle(.primary)
                    Spacer()
                    if let summary, !open {
                        Text(summary).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Chevron(open: open)
                }
                .font(.subheadline)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open { content }
        }
    }
}

/// Small disclosure for technical details (code, JSON).
struct DetailDisclosure<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { withAnimation(.easeInOut(duration: 0.2)) { open.toggle() } } label: {
                HStack(spacing: 4) {
                    Text(title)
                    Chevron(open: open)
                    Spacer()
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open { content }
        }
    }
}

struct Chevron: View {
    let open: Bool

    var body: some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tertiary)
            .rotationEffect(.degrees(open ? 90 : 0))
    }
}

struct Hint: View {
    let text: String

    var body: some View {
        Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Inputs

extension View {
    /// Shared input look for text fields and the SDK secure fields.
    func inputBackground() -> some View {
        padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(.tertiarySystemFill)))
    }
}

/// Labelled text field.
struct Field: View {
    let label: String
    @Binding var text: String
    var placeholder: String?
    var keyboard: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(placeholder ?? label, text: $text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .inputBackground()
        }
    }
}

/// Label + SDK secure field (the value is never readable) + live info line.
struct SecureFieldFrame<Content: View>: View {
    let label: String
    var info: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            content.frame(height: 44).inputBackground()
            if let info { Text(info).font(.caption2).foregroundStyle(.secondary) }
        }
    }
}

/// Style for the SDK secure fields, so they match `inputBackground()`.
@MainActor func plainSecureField(_ field: PaywallSecureTextField) {
    field.borderStyle = .none
    field.fieldBackgroundColor = .clear
    field.font = .preferredFont(forTextStyle: .body)
}

struct Mono: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, design: .monospaced))
            .textSelection(.enabled)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(.tertiarySystemFill)))
    }
}

// MARK: - Status

enum StatusKind {
    case success, action, failed, idle

    var color: Color {
        switch self {
        case .success: return .green
        case .action: return .orange
        case .failed: return .red
        case .idle: return .secondary
        }
    }

    var icon: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .action: return "exclamationmark.triangle.fill"
        case .failed: return "xmark.octagon.fill"
        case .idle: return "circle"
        }
    }
}

extension ActionState {
    var kind: StatusKind {
        if success { return .success }
        if actionRequired { return .action }
        if error != nil { return .failed }
        return .idle
    }

    var hasResult: Bool { response != nil || error != nil }
}

struct StatusPill: View {
    let text: String
    let kind: StatusKind

    var body: some View {
        Label(text, systemImage: kind.icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(kind.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(kind.color.opacity(0.14)))
    }
}

/// "Ne yapılmalı?" box.
struct GuidanceBox: View {
    let guidance: Guidance

    private var kind: StatusKind {
        switch guidance.tone {
        case .success: return .success
        case .action: return .action
        case .error: return .failed
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(guidance.title, systemImage: kind.icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(kind.color)
            if !guidance.meaning.isEmpty {
                Text(guidance.meaning).font(.footnote)
            }
            if !guidance.nextSteps.isEmpty {
                Text("Ne yapılmalı?").font(.footnote.weight(.semibold)).padding(.top, 2)
                ForEach(guidance.nextSteps, id: \.self) { step in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•")
                        Text(step)
                    }
                    .font(.footnote)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(kind.color.opacity(0.1)))
    }
}

// MARK: - Actions

/// Full-width button showing the SDK function it calls, and below it the result of the last call.
struct ActionRow: View {
    /// SDK call, e.g. `providers.masterpass.getCardList()`.
    let function: String
    /// What it does, in plain words.
    let label: String
    @ObservedObject var action: ActionState
    var enabled = true
    var prominent = true
    let perform: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: perform) {
                HStack(spacing: 10) {
                    if action.loading { ProgressView().controlSize(.small) }
                    VStack(spacing: 2) {
                        Text(function)
                            .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(label).font(.caption).opacity(0.85)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 40)
            }
            .modifier(ActionButtonStyle(prominent: prominent))
            .disabled(!enabled || action.loading)
            ResultView(action: action)
        }
    }
}

private struct ActionButtonStyle: ViewModifier {
    let prominent: Bool

    func body(content: Content) -> some View {
        if prominent {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

/// Guidance (or plain error) + collapsible merchant code and raw response.
struct ResultView: View {
    @ObservedObject var action: ActionState

    var body: some View {
        if action.hasResult {
            VStack(alignment: .leading, spacing: 8) {
                if let guidance = action.guidance {
                    GuidanceBox(guidance: guidance)
                } else if let error = action.error {
                    Label(error, systemImage: StatusKind.failed.icon).font(.footnote).foregroundStyle(.red)
                }
                if action.code != nil || action.response != nil {
                    DetailDisclosure(title: "Kod ve ham cevap") {
                        VStack(alignment: .leading, spacing: 8) {
                            if let code = action.code {
                                Text("Merchant kodu").font(.caption.weight(.semibold))
                                Mono(text: code)
                            }
                            if let response = action.response {
                                Text("SdkResponse").font(.caption.weight(.semibold))
                                Mono(text: response.jsonString(pretty: true))
                            }
                        }
                    }
                }
            }
        }
    }
}
