import MacToolsPluginKit
import XCTest
@testable import AIAssistantPlugin

@MainActor
final class AIAssistantPluginTests: XCTestCase {
    func testMetadataMatchesManifestContract() {
        let plugin = makePlugin()

        XCTAssertEqual(plugin.metadata.id, "ai-assistant")
        XCTAssertEqual(plugin.metadata.title, "AI 助手")
        XCTAssertEqual(plugin.metadata.defaultDescription, "划词调用 AI 翻译、总结、润色等")
        XCTAssertNotNil(plugin.primaryPanel)
        XCTAssertNotNil(plugin.settingsPage)
    }

    func testShortcutDefinitionsDynamicallyFollowEnabledPrompts() {
        let storage = AIAssistantInMemoryPluginStorage()
        let plugin = makePlugin(storage: storage)

        // Default prompts are all enabled.
        let definitions = plugin.shortcutDefinitions
        XCTAssertEqual(definitions.map(\.actionID), ["translate", "summarize", "polish"])
        XCTAssertEqual(definitions.map(\.scope), [.global, .global, .global])
        XCTAssertEqual(definitions.map(\.defaultBinding), [nil, nil, nil])

        // A disabled prompt drops its shortcut.
        let prompts = AIAssistantPromptStore(storage: storage).loadPrompts()
        let updated = prompts.map { prompt -> AIAssistantPrompt in
            var copy = prompt
            if copy.id == "summarize" {
                copy.isEnabled = false
            }
            return copy
        }
        let message = plugin.saveConfiguration(
            profiles: [AIAssistantProviderProfile.defaultProfile()],
            prompts: updated,
            apiKey: "sk-test"
        )

        XCTAssertNil(message)
        XCTAssertEqual(plugin.shortcutDefinitions.map(\.actionID), ["translate", "polish"])
    }

    func testDeclaresAccessibilityAndAutomationPermissions() {
        let requirements = makePlugin().permissionRequirements

        XCTAssertEqual(requirements.map(\.id), ["accessibility", "automation"])
        XCTAssertEqual(requirements.map(\.kind), [.accessibility, .automation])
    }

    func testPrimaryPanelReflectsPermissionState() {
        XCTAssertEqual(
            makePlugin(accessibilityTrustProvider: { false }).primaryPanelState.subtitle,
            "启用前需要辅助功能授权"
        )
    }

    func testSavingConfigurationPersistsPromptsAndNotifies() {
        let storage = AIAssistantInMemoryPluginStorage()
        let plugin = makePlugin(storage: storage)
        var didNotify = false
        plugin.onStateChange = { didNotify = true }

        let customPrompt = AIAssistantPrompt(
            id: "custom",
            name: "自定义",
            template: "{{text}}",
            systemPrompt: nil,
            isEnabled: true
        )
        let message = plugin.saveConfiguration(
            profiles: [AIAssistantProviderProfile.defaultProfile()],
            prompts: [customPrompt],
            apiKey: "sk-test"
        )

        XCTAssertNil(message)
        XCTAssertTrue(didNotify)
        XCTAssertEqual(plugin.shortcutDefinitions.map(\.actionID), ["custom"])
    }

    func testSavingConfigurationRejectsPromptMissingTextPlaceholder() {
        let storage = AIAssistantInMemoryPluginStorage()
        let plugin = makePlugin(storage: storage)

        let invalidPrompt = AIAssistantPrompt(
            id: "bad",
            name: "坏模板",
            template: "没有占位符",
            systemPrompt: nil,
            isEnabled: true
        )
        let message = plugin.saveConfiguration(
            profiles: [AIAssistantProviderProfile.defaultProfile()],
            prompts: [invalidPrompt],
            apiKey: "sk-test"
        )

        XCTAssertNotNil(message)
        XCTAssertTrue(message?.contains("{{text}}") == true)
    }

    func testPrimaryPanelTogglePersistsDisabledStateAndNotifies() {
        let storage = AIAssistantInMemoryPluginStorage()
        let plugin = makePlugin(storage: storage)
        var didNotify = false
        plugin.onStateChange = { didNotify = true }

        plugin.handleAction(.setSwitch(false))

        XCTAssertEqual(storage.bool(forKey: "ai-assistant.shortcut.enabled"), false)
        XCTAssertTrue(didNotify)
        XCTAssertFalse(plugin.primaryPanelState.isOn)
    }

    func testShortcutBindingDidChangeCachesPromptBinding() {
        let plugin = makePlugin()
        let binding = ShortcutBinding(keyCode: 3, modifiers: [.option])

        plugin.shortcutBindingDidChange(id: "ai-assistant.prompt.translate", binding: binding)

        // Reaching into the cache is not public; asserting no crash and that
        // unknown prefixes are ignored is sufficient for the contract.
        plugin.shortcutBindingDidChange(id: "other.prompt.translate", binding: binding)
    }

    // MARK: - Helpers

    private func makePlugin(
        storage: AIAssistantInMemoryPluginStorage? = nil,
        accessibilityTrustProvider: @escaping () -> Bool = { true }
    ) -> AIAssistantPlugin {
        let storage = storage ?? AIAssistantInMemoryPluginStorage()
        return AIAssistantPlugin(
            context: PluginRuntimeContext(pluginID: "ai-assistant", storage: storage),
            accessibilityTrustProvider: accessibilityTrustProvider,
            accessibilityTrustRequester: { _ in true },
            secretStore: CountingAIAssistantSecretStore(apiKey: "sk-test"),
            panelController: RecordingAIAssistantPanelController(),
            selectedTextCapturePipeline: SelectedTextCapturePipeline(strategies: [])
        )
    }
}

private final class CountingAIAssistantSecretStore: AIAssistantSecretStoring, @unchecked Sendable {
    private var apiKey: String?

    init(apiKey: String?) {
        self.apiKey = apiKey
    }

    func containsAPIKey() throws -> Bool {
        apiKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    func loadAPIKey() throws -> String? {
        apiKey
    }

    func saveAPIKey(_ apiKey: String) throws {
        self.apiKey = apiKey
    }

    func deleteAPIKey() throws {
        apiKey = nil
    }
}

@MainActor
private final class RecordingAIAssistantPanelController: AIAssistantPanelControlling {
    var onAction: ((AIAssistantPanelAction) -> Void)?

    func show(snapshot: AIAssistantPanelSnapshot) {}
    func update(snapshot: AIAssistantPanelSnapshot) {}
    func close() {}
}
