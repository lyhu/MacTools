import Foundation
import MacToolsPluginKit

/// A prompt template bound to a stable ID that doubles as its shortcut action ID.
struct AIAssistantPrompt: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var name: String
    var template: String
    var systemPrompt: String?
    var isEnabled: Bool

    var normalizedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// The outcome of processing a selected text through one prompt template.
struct AIProcessResult: Equatable, Sendable {
    var providerTitle: String
    var text: String
    var reasoningText: String?
    var sourceText: String
    var promptName: String
}

enum AIAssistantPanelPhase: Equatable, Sendable {
    case idle
    case capturing
    case processing
    case success
    case error(AIAssistantPanelError)
}

enum AIAssistantPanelError: Equatable, Sendable {
    case missingSelection
    case missingConfiguration
    case missingPrompt
    case permissionRequired
    case requestFailed(String)

    var message: String {
        message()
    }

    func message(localization: PluginLocalization = PluginLocalization(bundle: .main)) -> String {
        switch self {
        case .missingSelection:
            return localization.string("panelError.missingSelection", defaultValue: "未找到选中文本")
        case .missingConfiguration:
            return localization.string("panelError.missingConfiguration", defaultValue: "请先配置 AI 服务")
        case .missingPrompt:
            return localization.string("panelError.missingPrompt", defaultValue: "未找到对应处理模板")
        case .permissionRequired:
            return localization.string("panelError.permissionRequired", defaultValue: "需要辅助功能授权")
        case let .requestFailed(message):
            return message
        }
    }
}

struct AIAssistantPanelSnapshot: Equatable, Sendable {
    var phase: AIAssistantPanelPhase
    var sourceText: String?
    var result: AIProcessResult?
    var errorMessage: String?

    static let idle = AIAssistantPanelSnapshot(
        phase: .idle,
        sourceText: nil,
        result: nil,
        errorMessage: nil
    )
}

enum AIAssistantPanelAction: Equatable, Sendable {
    case retry
    case close
    case copyResult
    case openSettings
}
