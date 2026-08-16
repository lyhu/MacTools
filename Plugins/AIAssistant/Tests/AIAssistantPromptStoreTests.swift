import Foundation
import XCTest
@testable import AIAssistantPlugin

@MainActor
final class AIAssistantPromptStoreTests: XCTestCase {
    func testLoadPromptsReturnsDefaultPromptsWhenStorageIsEmpty() {
        let storage = AIAssistantInMemoryPluginStorage()
        let store = AIAssistantPromptStore(storage: storage)

        let prompts = store.loadPrompts()

        XCTAssertEqual(prompts.count, 3)
        XCTAssertEqual(prompts.map(\.id), ["translate", "summarize", "polish"])
        XCTAssertTrue(prompts.allSatisfy(\.isEnabled))
        XCTAssertTrue(prompts.allSatisfy { $0.template.contains("{{text}}") })
    }

    func testSavePromptsRoundTripsJSON() throws {
        let storage = AIAssistantInMemoryPluginStorage()
        let store = AIAssistantPromptStore(storage: storage)
        let prompt = AIAssistantPrompt(
            id: "custom",
            name: "自定义",
            template: "处理：{{text}}",
            systemPrompt: "你是助手",
            isEnabled: true
        )

        try store.savePrompts([prompt])

        let reloaded = store.loadPrompts()
        XCTAssertEqual(reloaded.count, 1)
        XCTAssertEqual(reloaded[0].id, "custom")
        XCTAssertEqual(reloaded[0].name, "自定义")
        XCTAssertEqual(reloaded[0].template, "处理：{{text}}")
        XCTAssertEqual(reloaded[0].systemPrompt, "你是助手")
        XCTAssertTrue(reloaded[0].isEnabled)
    }

    func testMakeNewPromptUsesUniqueNameAndStartsDisabled() {
        let storage = AIAssistantInMemoryPluginStorage()
        let store = AIAssistantPromptStore(storage: storage)
        let existing = [
            AIAssistantPrompt(id: "a", name: "新模板 2", template: "{{text}}", systemPrompt: nil, isEnabled: true),
            AIAssistantPrompt(id: "b", name: "新模板 3", template: "{{text}}", systemPrompt: nil, isEnabled: true),
        ]

        let prompt = store.makeNewPrompt(existing: existing)

        XCTAssertEqual(prompt.name, "新模板 4")
        XCTAssertFalse(prompt.isEnabled)
        XCTAssertEqual(prompt.template, "{{text}}")
        XCTAssertFalse(prompt.id.isEmpty)
    }
}
