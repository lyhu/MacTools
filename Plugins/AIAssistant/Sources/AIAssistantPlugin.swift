import AppKit
import Foundation
import SwiftUI
import MacToolsPluginKit

public final class AIAssistantPluginFactory: NSObject, MacToolsPluginBundleFactory {
    public static func makeProvider(context: PluginRuntimeContext) throws -> any PluginProvider {
        AIAssistantPluginProvider(context: context)
    }
}

@MainActor
private struct AIAssistantPluginProvider: PluginProvider {
    let context: PluginRuntimeContext

    func makePlugins() -> [any MacToolsPlugin] {
        [AIAssistantPlugin(context: context)]
    }
}

@MainActor
final class AIAssistantPlugin:
    MacToolsPlugin,
    PluginPrimaryPanel,
    PluginSettingsPresenting,
    PluginShortcutBindingChangeHandling
{
    private enum APIKeyState: Equatable {
        case unknown
        case present
        case missing
        case error(String)
    }

    let metadata: PluginMetadata

    let primaryPanelDescriptor = PluginPrimaryPanelDescriptor(
        controlStyle: .switch,
        menuActionBehavior: .keepPresented
    )

    var onStateChange: (() -> Void)?
    var requestPermissionGuidance: ((String) -> Void)?
    var shortcutBindingResolver: ((String) -> ShortcutBinding?)?
    var requestSettingsPresentation: (() -> Void)?

    private let storage: PluginStorage
    private let accessibilityTrustProvider: () -> Bool
    private let accessibilityTrustRequester: (Bool) -> Bool
    private let secretStore: any AIAssistantSecretStoring
    private let panelController: any AIAssistantPanelControlling
    private let selectedTextCapturePipeline: SelectedTextCapturePipeline
    private let providerFactoryOverride: AIAssistantProviderFactory?
    private let providerProfileStore: AIAssistantProviderProfileStore
    private let promptStore: AIAssistantPromptStore
    private let localization: PluginLocalization
    private var providerProfiles: [AIAssistantProviderProfile]
    private var prompts: [AIAssistantPrompt]
    private var cachedAPIKey: String?
    private var didLoadAPIKey = false
    private var apiKeyState: APIKeyState
    private var coordinator: AIAssistantCoordinator?
    /// Caches shortcut bindings so a deleted prompt's shortcut can be restored on recreate.
    private var cachedPromptBindings: [String: ShortcutBinding] = [:]

    init(
        context: PluginRuntimeContext = PluginRuntimeContext(pluginID: AIAssistantConstants.pluginID),
        accessibilityTrustProvider: @escaping () -> Bool = AccessibilityCheck.isTrusted,
        accessibilityTrustRequester: @escaping (Bool) -> Bool = AccessibilityCheck.requestTrust,
        secretStore: any AIAssistantSecretStoring = AIAssistantSecretStore(),
        panelController: (any AIAssistantPanelControlling)? = nil,
        selectedTextCapturePipeline: SelectedTextCapturePipeline? = nil,
        providerFactoryOverride: AIAssistantProviderFactory? = nil,
        localization: PluginLocalization? = nil
    ) {
        let localization = localization ?? PluginLocalization(bundle: context.resourceBundle)
        self.localization = localization
        self.metadata = PluginMetadata(
            id: AIAssistantConstants.pluginID,
            title: localization.string("metadata.title", defaultValue: "AI 助手"),
            iconName: "sparkles",
            iconTint: Color(nsColor: .systemPurple),
            order: 58,
            defaultDescription: localization.string(
                "metadata.description",
                defaultValue: "划词调用 AI 翻译、总结、润色等"
            )
        )
        self.storage = context.storage
        self.accessibilityTrustProvider = accessibilityTrustProvider
        self.accessibilityTrustRequester = accessibilityTrustRequester
        self.secretStore = secretStore
        self.panelController = panelController ?? AIAssistantPanelController(localization: localization)
        self.selectedTextCapturePipeline = selectedTextCapturePipeline ?? .live(localization: localization)
        self.providerFactoryOverride = providerFactoryOverride
        let providerProfileStore = AIAssistantProviderProfileStore(storage: context.storage, localization: localization)
        self.providerProfileStore = providerProfileStore
        self.providerProfiles = providerProfileStore.loadProfiles()
        self.promptStore = AIAssistantPromptStore(storage: context.storage, localization: localization)
        self.prompts = promptStore.loadPrompts()
        self.cachedAPIKey = nil
        self.apiKeyState = .unknown
        self.panelController.onAction = { [weak self] action in
            self?.handlePanelAction(action)
        }
    }

    var primaryPanelState: PluginPanelState {
        PluginPanelState(
            subtitle: panelSubtitle,
            isOn: isShortcutEnabled,
            isExpanded: false,
            isEnabled: true,
            isVisible: true,
            detail: nil,
            errorMessage: nil
        )
    }

    var permissionRequirements: [PluginPermissionRequirement] {
        [
            PluginPermissionRequirement(
                id: AIAssistantConstants.PermissionID.accessibility,
                kind: .accessibility,
                title: localization.string("permission.accessibility.title", defaultValue: "辅助功能授权"),
                description: localization.string(
                    "permission.accessibility.description",
                    defaultValue: "划词处理需要读取当前选中文本。"
                )
            ),
            PluginPermissionRequirement(
                id: AIAssistantConstants.PermissionID.automation,
                kind: .automation,
                title: localization.string("permission.automation.title", defaultValue: "自动化授权"),
                description: localization.string(
                    "permission.automation.description",
                    defaultValue: "浏览器划词可能需要允许 MacTools 控制当前浏览器。"
                )
            ),
        ]
    }

    var shortcutDefinitions: [PluginShortcutDefinition] {
        prompts
            .filter(\.isEnabled)
            .map { prompt in
                PluginShortcutDefinition(
                    id: Self.shortcutID(for: prompt.id),
                    title: prompt.normalizedName,
                    description: localization.format(
                        "shortcut.prompt.descriptionFormat",
                        defaultValue: "用「%@」处理当前选中文本。",
                        prompt.normalizedName
                    ),
                    actionID: prompt.id,
                    scope: .global,
                    defaultBinding: nil,
                    isRequired: false
                )
            }
    }

    var settingsPage: PluginSettingsPage? {
        .form(description: metadata.defaultDescription, sections: [
            PluginSettingsSection(
                id: "ai-assistant-settings",
                title: localization.string("settings.title", defaultValue: "AI 助手设置"),
                systemImage: "sparkles",
                presentation: .edgeToEdge
            ) { [weak self] _ in
                if let self {
                    AIAssistantSettingsView(
                        profiles: self.providerProfiles,
                        prompts: self.prompts,
                        apiKey: self.cachedAPIKey ?? "",
                        localization: self.localization,
                        onSave: { [weak self] profiles, prompts, apiKey in
                            self?.saveConfiguration(profiles: profiles, prompts: prompts, apiKey: apiKey)
                        },
                        onMakeNewPrompt: { [weak self] existing in
                            self?.promptStore.makeNewPrompt(existing: existing)
                                ?? AIAssistantPrompt(
                                    id: UUID().uuidString,
                                    name: "新模板",
                                    template: "{{text}}",
                                    systemPrompt: nil,
                                    isEnabled: false
                                )
                        }
                    )
                }
            }
        ])
    }

    func handleAction(_ action: PluginPanelAction) {
        guard case let .setSwitch(isEnabled) = action else {
            return
        }

        storage.set(isEnabled, forKey: AIAssistantConstants.StorageKey.shortcutEnabled)
        onStateChange?()
    }

    func permissionState(for permissionID: String) -> PluginPermissionState {
        switch permissionID {
        case AIAssistantConstants.PermissionID.accessibility:
            let isGranted = accessibilityTrustProvider()
            return PluginPermissionState(
                isGranted: isGranted,
                footnote: isGranted
                    ? nil
                    : localization.string(
                        "permission.accessibility.footnote",
                        defaultValue: "前往系统设置 → 隐私与安全性 → 辅助功能，授权 MacTools。"
                    )
            )
        case AIAssistantConstants.PermissionID.automation:
            return PluginPermissionState(
                isGranted: true,
                footnote: localization.string(
                    "permission.automation.footnote",
                    defaultValue: "macOS 会在首次控制浏览器时请求自动化授权。"
                ),
                statusText: localization.string("permission.automation.status", defaultValue: "按需确认"),
                statusSystemImage: "sparkles",
                statusTone: .neutral
            )
        default:
            return PluginPermissionState(isGranted: true, footnote: nil)
        }
    }

    func handlePermissionAction(id: String) {
        switch id {
        case AIAssistantConstants.PermissionID.accessibility:
            _ = accessibilityTrustRequester(true)
            onStateChange?()
        case AIAssistantConstants.PermissionID.automation:
            requestPermissionGuidance?(AIAssistantConstants.PermissionID.automation)
            onStateChange?()
        default:
            return
        }
    }

    func handleSettingsAction(_ action: PluginSettingsAction) {}

    func deactivate(reason: PluginDeactivationReason) {
        guard reason.requiresStateCleanup else {
            return
        }

        if let coordinator {
            coordinator.close()
        } else {
            panelController.close()
        }
        coordinator = nil
    }

    func handleShortcutAction(id: String) {
        guard isShortcutEnabled else {
            return
        }

        guard let prompt = prompts.first(where: { $0.id == id }) else {
            return
        }

        let coordinator = coordinator ?? makeCoordinator()
        self.coordinator = coordinator
        coordinator.startProcessing(prompt: prompt)
    }

    func shortcutBindingDidChange(id: String, binding: ShortcutBinding?) {
        // `id` is the shortcut definition id (prefix + prompt id). Store by prompt id so a
        // recreated prompt with the same ID can restore its previous binding.
        guard id.hasPrefix(Self.shortcutIDPrefix) else { return }
        let promptID = String(id.dropFirst(Self.shortcutIDPrefix.count))

        if let binding {
            cachedPromptBindings[promptID] = binding
        } else {
            cachedPromptBindings.removeValue(forKey: promptID)
        }
    }

    // MARK: - Helpers

    private static let shortcutIDPrefix = "ai-assistant.prompt."

    private static func shortcutID(for promptID: String) -> String {
        "\(shortcutIDPrefix)\(promptID)"
    }

    private var isShortcutEnabled: Bool {
        guard storage.object(forKey: AIAssistantConstants.StorageKey.shortcutEnabled) != nil else {
            return AIAssistantConstants.Defaults.shortcutEnabled
        }

        return storage.bool(forKey: AIAssistantConstants.StorageKey.shortcutEnabled)
    }

    private var panelSubtitle: String {
        if !isShortcutEnabled {
            return localization.string("panel.subtitle.shortcutPaused", defaultValue: "快捷键已暂停")
        }
        if !accessibilityTrustProvider() {
            return localization.string("panel.subtitle.permissionRequired", defaultValue: "启用前需要辅助功能授权")
        }
        if enabledValidProfiles.isEmpty {
            return localization.string("panel.subtitle.needsProvider", defaultValue: "需要配置 AI 服务")
        }

        switch apiKeyState {
        case .missing, .error:
            return localization.string("panel.subtitle.needsProvider", defaultValue: "需要配置 AI 服务")
        case .unknown, .present:
            return localization.string("panel.subtitle.ready", defaultValue: "按下模板快捷键处理选中文本")
        }
    }

    private var enabledValidProfiles: [AIAssistantProviderProfile] {
        providerProfiles.filter { $0.isEnabled && $0.validationError == nil }
    }

    private func handlePanelAction(_ action: AIAssistantPanelAction) {
        if action == .openSettings {
            requestSettingsPresentation?()
            return
        }

        if action == .close {
            if let coordinator {
                coordinator.close()
            } else {
                panelController.close()
            }
            return
        }

        guard let coordinator else { return }
        coordinator.handle(action)
    }

    private func makeCoordinator() -> AIAssistantCoordinator {
        AIAssistantCoordinator(
            selectedTextCapturePipeline: selectedTextCapturePipeline,
            providerFactory: providerFactoryOverride ?? { [weak self] in
                guard let self else {
                    return .failure(AIAssistantProviderError(
                        message: PluginLocalization(bundle: .main).string(
                            "panelError.missingProvider",
                            defaultValue: "请先配置 AI 服务"
                        )
                    ))
                }
                return self.resolveProvider()
            },
            panelController: panelController,
            localization: localization
        )
    }

    private func resolveProvider() -> Result<ResolvedAIProvider, AIAssistantProviderError> {
        guard let profile = enabledValidProfiles.first else {
            return .failure(AIAssistantProviderError(
                message: localization.string("panelError.missingProvider", defaultValue: "请先配置 AI 服务")
            ))
        }

        do {
            let apiKey = try loadAPIKey()
            guard let trimmedKey = Self.normalizedAPIKey(apiKey) else {
                return .failure(AIAssistantProviderError(
                    message: localization.string("panelError.missingAPIKey", defaultValue: "请配置 API Key")
                ))
            }

            return .success(
                ResolvedAIProvider(
                    title: profile.normalizedName,
                    client: OpenAICompatibleClient(localization: localization),
                    configuration: profile.configuration,
                    apiKey: trimmedKey
                )
            )
        } catch {
            return .failure(AIAssistantProviderError(message: userFacingMessage(for: error)))
        }
    }

    private func loadAPIKey() throws -> String? {
        if didLoadAPIKey {
            return cachedAPIKey
        }

        let key = try secretStore.loadAPIKey()
        cachedAPIKey = key
        didLoadAPIKey = true
        apiKeyState = Self.hasNonEmptyAPIKey(key) ? .present : .missing
        return key
    }

    func saveConfiguration(
        profiles: [AIAssistantProviderProfile],
        prompts: [AIAssistantPrompt],
        apiKey: String
    ) -> String? {
        guard profiles.contains(where: \.isEnabled) else {
            return localization.string("settings.error.noEnabledProvider", defaultValue: "至少启用一个 AI 服务。")
        }

        for profile in profiles where profile.isEnabled {
            if let validationError = profile.validationError {
                let title = profile.normalizedName.isEmpty
                    ? localization.string("settings.provider.fallbackName", defaultValue: "AI 服务")
                    : profile.normalizedName
                return localization.format(
                    "settings.error.providerValidationFormat",
                    defaultValue: "%@：%@",
                    title,
                    validationError.errorDescription(localization: localization)
                )
            }
        }

        for prompt in prompts where prompt.isEnabled {
            if !prompt.template.contains("{{text}}") {
                return localization.format(
                    "settings.error.promptValidationFormat",
                    defaultValue: "%@：提示词必须包含 {{text}}。",
                    prompt.normalizedName.isEmpty
                        ? localization.string("settings.prompt.fallbackName", defaultValue: "处理模板")
                        : prompt.normalizedName
                )
            }
        }

        do {
            if let normalizedAPIKey = Self.normalizedAPIKey(apiKey) {
                try secretStore.saveAPIKey(normalizedAPIKey)
                cachedAPIKey = normalizedAPIKey
                didLoadAPIKey = true
            }

            try providerProfileStore.saveProfiles(profiles)
            try promptStore.savePrompts(prompts)
            providerProfiles = providerProfileStore.loadProfiles()
            self.prompts = promptStore.loadPrompts()
            apiKeyState = .present
            if let coordinator {
                coordinator.close()
            } else {
                panelController.close()
            }
            coordinator = nil
            onStateChange?()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func userFacingMessage(for error: Error) -> String {
        if let error = error as? OpenAICompatibleClientError {
            return error.errorDescription(localization: localization)
        }
        if let error = error as? OpenAICompatibleConfigurationError {
            return error.errorDescription(localization: localization)
        }
        if let error = error as? PromptRendererError {
            return error.errorDescription(localization: localization)
        }
        if let error = error as? AIAssistantSecretStoreError {
            return error.errorDescription(localization: localization)
        }
        if let error = error as? AIAssistantProviderProfileValidationError {
            return error.errorDescription(localization: localization)
        }
        return error.localizedDescription
    }

    private static func hasNonEmptyAPIKey(_ apiKey: String?) -> Bool {
        apiKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private static func normalizedAPIKey(_ apiKey: String?) -> String? {
        let trimmedKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedKey.isEmpty ? nil : trimmedKey
    }
}
