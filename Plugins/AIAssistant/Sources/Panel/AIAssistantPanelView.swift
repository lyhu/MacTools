import SwiftUI
import MacToolsPluginKit

@MainActor
final class AIAssistantPanelModel: ObservableObject {
    @Published var snapshot: AIAssistantPanelSnapshot = .idle
}

struct AIAssistantPanelHostView: View {
    @ObservedObject var model: AIAssistantPanelModel
    let localization: PluginLocalization
    let onAction: (AIAssistantPanelAction) -> Void

    var body: some View {
        AIAssistantPanelView(snapshot: model.snapshot, localization: localization, onAction: onAction)
    }
}

struct AIAssistantPanelView: View {
    let snapshot: AIAssistantPanelSnapshot
    let localization: PluginLocalization
    let onAction: (AIAssistantPanelAction) -> Void

    @State private var showReasoning = false

    init(
        snapshot: AIAssistantPanelSnapshot,
        localization: PluginLocalization = PluginLocalization(bundle: .main),
        onAction: @escaping (AIAssistantPanelAction) -> Void
    ) {
        self.snapshot = snapshot
        self.localization = localization
        self.onAction = onAction
    }

    var body: some View {
        VStack(spacing: 8) {
            sourceSection
            if let errorMessage, snapshot.phase != .success {
                tipCard(errorMessage)
            }
            resultSection
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 606, height: 380, alignment: .top)
    }

    private var errorMessage: String? {
        switch snapshot.phase {
        case let .error(error):
            return error.message(localization: localization)
        default:
            return snapshot.errorMessage
        }
    }

    private var sourceSection: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                if trimmedSourceText.isEmpty {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.accentColor.opacity(0.65))
                        .frame(width: 2.5, height: 18)
                        .padding(.leading, 11)
                        .padding(.top, 11)
                } else {
                    ScrollView {
                        Text(trimmedSourceText)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(.horizontal, 12)
                            .padding(.top, 10)
                            .padding(.bottom, 8)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(height: 86)
        .background(panelCardColor, in: RoundedRectangle(cornerRadius: 8))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var resultSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                switch snapshot.phase {
                case .idle, .capturing:
                    statusText(localization.string("panel.status.capturing", defaultValue: "正在读取选中文本..."))
                case .processing:
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        statusText(localization.string("panel.status.processing", defaultValue: "正在处理..."))
                    }
                case .success:
                    successContent
                case .error:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollIndicators(.never)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var successContent: some View {
        if let result = snapshot.result {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.purple)
                    Text(result.promptName)
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Button {
                        onAction(.copyResult)
                    } label: {
                        Label(
                            localization.string("panel.result.copy", defaultValue: "复制"),
                            systemImage: "doc.on.doc"
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(result.text.isEmpty)
                }

                if let reasoning = result.reasoningText, !reasoning.isEmpty {
                    DisclosureGroup(isExpanded: $showReasoning) {
                        Text(reasoning)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(.top, 4)
                    } label: {
                        Label(
                            localization.string("panel.reasoning.title", defaultValue: "思考过程"),
                            systemImage: "brain"
                        )
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    }
                }

                Text(result.text)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(panelCardColor, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func statusText(_ text: String) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
    }

    private func tipCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "lightbulb")
                    .font(.system(size: 15, weight: .semibold))
                    .symbolRenderingMode(.multicolor)
                Text(localization.string("panel.tip.title", defaultValue: "提示"))
                    .font(.system(size: 14, weight: .semibold))
            }
            Text(message)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.primary)
                .lineLimit(2)
            HStack(spacing: 8) {
                Button {
                    onAction(.retry)
                } label: {
                    Label(localization.string("panel.retryHelp", defaultValue: "重试"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    onAction(.openSettings)
                } label: {
                    Label(
                        localization.string("panel.tip.actionTitle", defaultValue: "如何解决"),
                        systemImage: "questionmark.bubble"
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.accentColor)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(panelCardColor, in: RoundedRectangle(cornerRadius: 8))
    }

    private var trimmedSourceText: String {
        snapshot.sourceText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var panelCardColor: Color {
        Color(nsColor: .controlBackgroundColor).opacity(0.72)
    }
}
