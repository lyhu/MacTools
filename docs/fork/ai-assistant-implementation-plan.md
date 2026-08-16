# AI 助手（AI Assistant）插件实现方案

> 基于现有 `Plugins/Translator` 插件扩展而来的通用 AI 翻译/处理工具。
> 本文档结合 MacTools 当前代码结构，给出从插件注册、配置界面、快捷键监听、文本获取、AI 调用到结果展示的完整落地路径，以及上架 tools 市场的流程。

---

## 1. 工具命名与定位

| 项 | 值 |
| --- | --- |
| 英文名 | **AI Assistant** |
| 中文名 | **AI 助手** |
| 插件 ID（`plugin.json.id` = `PluginMetadata.id`） | `ai-assistant` |
| Bundle 名 / `bundleRelativePath` | `AIAssistant.bundle` |
| 工厂类 `factoryClass` | `AIAssistantPlugin.AIAssistantPluginFactory` |
| 源目录 | `Plugins/AIAssistant/` |
| 分类 `category` | `productivity` |

**使用场景（必须覆盖翻译，且不止于翻译）**：用户选中一段文字后按下全局快捷键，插件按对应提示词模板调用 AI 大模型处理并回填结果。典型场景：

- **翻译**：中英互译、多语互译（内置默认模板，继承 Translator 的核心场景）。
- **总结 / 提炼**：长文本摘要、要点提炼。
- **润色 / 改写**：书面化、口语化、降 AI 味、扩写/缩写。
- **解释**：解释选中词句、解释代码片段。
- **自定义指令**：用户自定义任意 Prompt，绑定到独立快捷键，实现「一键个性化处理」。

---

## 2. 功能需求拆解

1. **AI 大模型配置**：用户可配置 API 地址（Base URL）、模型名、API Key 等参数（OpenAI 兼容协议，兼容 DeepSeek / Qwen / GLM / Kimi 等）。
2. **多组 Prompt 模板**：用户可增删改多组提示词模板；每组模板可单独绑定一个系统全局快捷键。
3. **快捷键触发处理**：按下某组模板的快捷键 → 自动读取「当前选中文本」或「输入框中的文本」→ 按该模板调用大模型 → 返回处理结果。
4. **结果展示**：区分「思考过程」与「最终结果」；思考过程可折叠/隐藏；最终结果支持一键复制。

---

## 3. 可复用的现有能力（Translator 插件盘点）

AI 助手 90% 的工程骨架可直接复用 Translator，差异集中在「多组 Prompt + 动态快捷键 + 思考过程展示」。

| 能力 | 现有位置 | 复用方式 |
| --- | --- | --- |
| 插件工厂/提供者 | `TranslatorPlugin.swift`（`TranslatorPluginFactory` / `TranslatorPluginProvider`） | 照搬结构 |
| 主插件类协议集 | `TranslatorPlugin` 实现 `MacToolsPlugin`、`PluginPrimaryPanel`、`PluginSettingsPresenting` 等 | 照搬结构 |
| AI HTTP 客户端 | `OpenAI/OpenAICompatibleClient.swift` | 复制后扩展（支持 `reasoning_content`、通用 `complete` 方法） |
| API 配置模型与校验 | `Settings/OpenAICompatibleConfiguration.swift` | 复制后复用（Base URL / model / prompt 校验 + `endpointURL()` 拼接 `/v1/chat/completions`） |
| API Key 安全存储 | `Settings/OpenAICompatibleSecretStore.swift`（Keychain） | 复制后复用 |
| 选中文本捕获 | `SelectedTextCapture/SelectedTextCapturePipeline.swift`（AX / 浏览器 AppleScript / 模拟复制三策略） | 复制或抽取共享（见 §6.5） |
| 结果面板协议 | `TranslatorCoordinator.swift` 中 `TranslatorPanelControlling` + `TranslatorPanelSnapshot` 状态机 | 复制后改造（加入思考过程字段） |
| 结果面板视图 | `Panel/TranslatorPanelView.swift` | 复制后改造（折叠思考区 + 复制按钮） |
| 设置页宿主 | `PluginSettingsPage.form` + `TranslatorSettingsView` | 复制后改造（Provider + Prompt 列表） |
| 快捷键定义 | `PluginShortcutDefinition`（`MacToolsPluginKit`） | 复用，但改为「按 Prompt 动态生成」 |

> 结论：新增插件比「魔改 Translator」更干净，既能保留 Translator 作为轻量划词翻译，又能让 AI 助手承载通用多 Prompt 场景。共享的文本捕获能力是否抽取到 Core 层，见 §6.5 的权衡。

---

## 4. 总体架构

沿用 Translator 的「插件类 + 协调器 + 面板控制器」三层：

```text
快捷键触发 (GlobalShortcutManager)
        │  handleShortcutAction(id:)
        ▼
AIAssistantPlugin ──────────────► AIAssistantCoordinator
   │  (解析 promptID)                  │
   │                                   ├─ SelectedTextCapturePipeline.capture()
   │                                   ├─ AIAssistantProviderFactory()  (解析已启用 Provider)
   │                                   ├─ OpenAICompatibleClient.complete()
   │                                   └─ panelController.show/update(snapshot)
   ▼
settingsPage (Provider 配置 + Prompt 列表 + 快捷键)
```

**核心数据模型（新增）**：

```swift
// 一组 Prompt 模板
struct AIAssistantPrompt: Codable, Equatable, Identifiable, Sendable {
    let id: String            // 稳定 ID，同时用作 shortcutDefinitions 的 actionID
    var name: String          // 模板名称，如「中译英」
    var template: String      // 提示词，必须含 {{text}} 占位符
    var systemPrompt: String? // 可选系统提示词
    var isEnabled: Bool
}

// 处理结果（含思考过程）
struct AIProcessResult: Equatable, Sendable {
    var providerTitle: String
    var text: String          // 最终结果
    var reasoningText: String?// 思考过程（模型可能不返回 → nil，UI 自动隐藏）
    var sourceText: String
    var promptName: String
}
```

---

## 5. 文件清单

### 5.1 新增（插件本体，全部位于 `Plugins/AIAssistant/`）

```text
Plugins/AIAssistant/
├── plugin.json                                          # 插件清单
├── project.yml                                          # 仅当需要额外构建设置时才添加（默认可省略）
├── Sources/
│   ├── AIAssistantPlugin.swift                          # 工厂 + Provider + 主插件类
│   ├── AIAssistantCoordinator.swift                     # 处理流程协调器
│   ├── AIAssistantConstants.swift                       # 常量（ID、StorageKey、默认快捷键等）
│   ├── AIAssistantModels.swift                          # Prompt / 结果 / 快照等模型
│   ├── Settings/
│   │   ├── AIAssistantProviderProfile.swift             # Provider（BaseURL/model/prompt 组）+ 校验
│   │   ├── AIAssistantProviderProfileStore.swift        # Provider 持久化
│   │   ├── AIAssistantSecretStore.swift                 # API Key Keychain 存储
│   │   ├── AIAssistantPromptStore.swift                 # Prompt 模板持久化
│   │   └── AIAssistantSettingsView.swift                # 设置界面（配置 + Prompt 列表）
│   ├── OpenAI/
│   │   ├── OpenAICompatibleClient.swift                 # OpenAI 兼容 HTTP 客户端（含 reasoning）
│   │   ├── OpenAICompatibleConfiguration.swift          # BaseURL/model/校验 + endpointURL()
│   │   ├── PromptRenderer.swift                         # {{text}} 等占位符渲染
│   │   └── AIProcessResult.swift                        # 处理结果模型
│   ├── Panel/
│   │   ├── AIAssistantPanelController.swift             # 面板控制器（协议 + 默认实现）
│   │   ├── AIAssistantPanelView.swift                   # SwiftUI 结果视图
│   │   └── AIAssistantPanelSnapshot.swift               # 面板快照/状态机
│   └── SelectedTextCapture/
│       ├── SelectedTextCapturePipeline.swift            # 复用 Translator 三策略（或共享化，见 §6.5）
│       ├── SelectedTextCaptureContext.swift
│       ├── SelectedTextCaptureResult.swift
│       └── SelectedTextCapturing.swift                  # 策略协议 + 三实现
├── Bundle/
│   └── AIAssistantPluginBundleEntrypoint.swift          # 可选；工厂可直接写在 Sources
├── Resources/
│   └── (Localizable.xcstrings 等本地化资源、图标)
└── Tests/
    ├── AIAssistantPromptStoreTests.swift
    ├── AIAssistantPromptRendererTests.swift
    ├── AIAssistantConfigurationTests.swift
    └── AIAssistantCoordinatorTests.swift
```

### 5.2 新增（changelog 片段，遵循 `changes/unreleased/*.md`）

```text
changes/unreleased/ai-assistant.md   # front-matter: release: plugin / type: added
```

### 5.3 修改（仅当抽取共享文本捕获时，属于 ABI 变更，需谨慎）

```text
Sources/MacToolsPluginKit/   # 若将 SelectedTextCapture 抽象为共享协议/类型
```

> `Sources/MacToolsPluginKit/` 任何改动都是「对所有插件 package-relevant」，会触发 `make release` 全量重建所有插件。因此 MVP 阶段建议**先复制**，避免触碰 ABI（详见 §6.5）。

---

## 6. 关键实现细节

### 6.1 插件注册（工厂模式）

与 Translator 完全一致的入口链：

```swift
// AIAssistantPlugin.swift
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
    PluginShortcutBindingChangeHandling   // 动态快捷键绑定变化回调（可选）
{
    let metadata = PluginMetadata(
        id: AIAssistantConstants.pluginID,            // "ai-assistant"
        title: localization.string("metadata.title", defaultValue: "AI 助手"),
        iconName: "sparkles",
        iconTint: Color(nsColor: .systemPurple),
        order: 58,
        defaultDescription: "划词调用 AI 翻译、总结、润色等"
    )

    var shortcutDefinitions: [PluginShortcutDefinition] {
        promptStore.loadPrompts()
            .filter(\.isEnabled)
            .map { prompt in
                PluginShortcutDefinition(
                    id: prompt.id,                    // 稳定 ID
                    title: prompt.name,
                    description: "用「\(prompt.name)」处理当前选中文本。",
                    actionID: prompt.id,              // ★ 关键：触发时回传的 id
                    scope: .global,
                    defaultBinding: nil,              // 新建模板默认无快捷键
                    isRequired: false
                )
            }
    }

    func handleShortcutAction(id: String) {
        guard let prompt = promptStore.loadPrompts().first(where: { $0.id == id }) else { return }
        let coordinator = coordinator ?? makeCoordinator()
        self.coordinator = coordinator
        coordinator.startProcessing(prompt: prompt)
    }
}
```

**要点**：
- `plugin.json` 中 `capabilities.settings` 声明为 `"form"`，`capabilities.primaryPanel` 为 `true`。
- `factoryClass` 写 `AIAssistantPlugin.AIAssistantPluginFactory`，与 `plugin.json.id`、运行时 `PluginMetadata.id` 严格一致，且包内只返回一个插件实例（AGENTS.md 硬性约定）。

### 6.2 AI 大模型配置（Provider + 密钥）

复用 Translator 的 `OpenAICompatibleConfiguration` 校验逻辑与 `endpointURL()` 拼接规则（自动处理 `/v1/chat/completions` 路径）：

```swift
struct AIAssistantProviderProfile: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var name: String
    var isEnabled: Bool
    var baseURL: String     // 默认 https://api.openai.com
    var model: String       // 默认 gpt-4o-mini 或按用户填写
    var temperature: Double // 默认 0.2
    // 校验：baseURL 非空且合法、model 非空；逻辑同 OpenAICompatibleConfiguration.validationError
}
```

- **API Key**：通过 `AIAssistantSecretStore` 写入 Keychain（复制 `OpenAICompatibleSecretStore` 的 `saveAPIKey/loadAPIKey/deleteAPIKey`），不落 UserDefaults、不进日志。
- **持久化**：Provider 列表用 `PluginStorage`（`context.storage`，实际是 `UserDefaultsPluginStorage`，键名 `plugin.ai-assistant.*`）+ JSON 编码，参考 `TranslatorProviderProfileStore`。
- **单 Provider 即可**：AI 助手通常只需一个默认 Provider（用户可自定义 Base URL 接入任意 OpenAI 兼容服务）。保留多 Provider 数组仅为对齐 Translator，MVP 可简化为单实例。

### 6.3 多组 Prompt 模板（模型 + 存储）

```swift
final class AIAssistantPromptStore {
    private let storage: PluginStorage
    private static let storageKey = "prompts"

    func loadPrompts() -> [AIAssistantPrompt]
    func savePrompts(_ prompts: [AIAssistantPrompt]) throws
    func makeNewPrompt(existing: [AIAssistantPrompt]) -> AIAssistantPrompt  // 生成 UUID 新模板
}
```

- 模板使用 `{{text}}` 占位符表示「选中文本」，由 `PromptRenderer` 渲染。
- 内置默认模板（首次安装时写入）：`翻译`（中英互译）、`总结`、`润色`，确保「覆盖翻译」场景开箱可用。
- 每个 Prompt 的 `id` 即快捷键 `actionID`，因此 ID 一旦创建必须稳定，删除后不复用（否则可能与历史快捷键绑定残留冲突）。

### 6.4 快捷键监听与「多组模板各自绑定快捷键」

这是本方案与 Translator 的核心差异。现有架构的关键事实：

- `MacToolsPlugin.shortcutDefinitions` 是一个**计算属性**，`PluginHost` 在构建快捷键描述时读取它（见 `PluginHost.swift` 中 `shortcutDefinitions` → `ShortcutDescriptor` 的映射），并把每个定义的 `actionID` 作为回调参数回传给 `handleShortcutAction(id:)`。
- `GlobalShortcutManager` 用 Carbon `RegisterEventHotKey` 注册系统级全局快捷键，触发后通过 `onShortcutTriggered` 回调到 host，最终调用 `plugin.handleShortcutAction(id: descriptor.definition.actionID)`。

因此，「N 组模板 → N 个快捷键」的落地方式为：

1. `shortcutDefinitions` 动态返回当前启用 Prompt 对应的定义（见 §6.1）。
2. Prompt 增删改后调用 `onStateChange?()`，host 重新读取 `shortcutDefinitions` 并调用 `GlobalShortcutManager.updateBindings` 重建注册。
3. `handleShortcutAction(id:)` 用 `id` 反查 Prompt 并启动处理。

**需要注意的边界**：

- **绑定持久化**：默认快捷键由 host 的 `ShortcutAssignmentService` 统一管理（插件只声明 `defaultBinding` 与迁移默认值，不自行二次注册/持久化，避免与 host 冲突，见 `docs/plugins/local-native-plugins.md`）。新模板 `defaultBinding = nil`，用户第一次在设置页的快捷键行里录制即可。
- **动态绑定的保留**：若需要「删除模板再重建时恢复快捷键」，可选实现 `PluginShortcutBindingChangeHandling.shortcutBindingDidChange(id:binding:)`（`PluginInterfaces.swift` 已导出该协议）来缓存绑定；MVP 可省略，删除模板即放弃其快捷键。
- **分组展示**：`PluginShortcutDefinition` 支持 `settingsGroupID/settingsGroupTitle`，可在设置页把「Prompt 快捷键」单独分组展示；否则由 host 的 `PluginSettingsSection.shortcutGroup` 统一渲染。

### 6.5 文本获取（选中文本 / 输入框文本）

`SelectedTextCapturePipeline` 已覆盖两种需求：

| 策略 | 能力 |
| --- | --- |
| `AccessibilitySelectedTextCapture` | 通过 AX API 读 `AXSelectedText`，覆盖普通 App 的选中文本**以及可编辑输入框（NSTextField/NSTextView/WebView 输入域）内的选中文本**（结果含 `isEditable` 标记） |
| `BrowserAppleScriptSelectedTextCapture` | 浏览器（Safari/Chrome 等）划词 |
| `SimulatedCopySelectedTextCapture` | 兜底：模拟 `⌘C` 后读剪贴板 |

**复用方式二选一**：

1. **MVP（推荐）**：把 Translator 的 `SelectedTextCapture/` 目录复制到新插件内。改动零风险、不触碰 PluginKit ABI，代价是短期代码重复。
2. **进阶（可选重构）**：将文本捕获抽象到共享层（`Sources/Core/` 或 `MacToolsPluginKit` 的协议 + 实现），Translator 与 AI 助手共同依赖。符合 AGENTS.md「cross-plugin value 应先抽象到 Core 层」的约定，但会引发 PluginKit ABI 变更和全量插件重建，需随一次 PluginKit 版本迭代单独提交。

**「输入框中的文本」补充说明**：现有 AX 策略读取的是输入框内**已选中的文本**；若输入框无选中文本，MVP 不做「读取整个输入框」的兜底（避免误读敏感内容与体验问题）。可留作后续增强：新增策略读取 `AXValue`（仅在可编辑输入框、用户显式开启时启用）。

### 6.6 AI 调用（含思考过程）

**复制并扩展 `OpenAICompatibleClient`**：现有 `translate` 方法硬编码了翻译语义与 `source/target language` 渲染，需抽出一个通用方法：

```swift
struct OpenAICompatibleClient: Sendable {
    func complete(
        prompt: String,                 // 已渲染的完整用户消息
        systemPrompt: String?,
        configuration: OpenAICompatibleConfiguration,
        apiKey: String
    ) async throws -> AIProcessResult
}
```

请求体（`OpenAIChatCompletionsRequest`）增加可选 `reasoning` 相关字段（按模型要求，如 DeepSeek/Qwen 推理模型），响应体 `Message` 增加可选字段解析：

```swift
private struct OpenAIChatCompletionsResponse: Decodable {
    struct Message: Decodable {
        let content: String
        let reasoningContent: String?   // 对应 JSON 字段 reasoning_content
        enum CodingKeys: String, CodingKey {
            case content
            case reasoningContent = "reasoning_content"
        }
    }
    struct Choice: Decodable { let message: Message }
    let choices: [Choice]
}
```

**思考过程的兼容策略**：
- 返回 `reasoning_content` → 作为 `AIProcessResult.reasoningText` 展示。
- 未返回（非推理模型）→ `reasoningText = nil`，UI 自动隐藏思考区，逻辑不报错。
- 错误处理沿用 `OpenAICompatibleClientError`（`unauthorized` / `parseFailed` / `emptyResponse` 等）。

**流式 vs 非流式**：
- **MVP：非流式**（`stream: false`，同 Translator）。实现简单、复用现有解析，思考过程一次性展示。
- **进阶：流式**（`stream: true` + `URLSession.bytes` 逐行解析 SSE），可做到「思考过程边生成边折叠显示」。作为后续迭代，不影响 MVP 架构。

### 6.7 结果展示（思考折叠 + 一键复制）

`AIAssistantPanelSnapshot` 状态机对齐 Translator，但 `result` 携带 `reasoningText`：

```swift
struct AIAssistantPanelSnapshot: Equatable {
    enum Phase: Equatable {
        case idle
        case capturing          // 正在读取选中文本
        case processing         // 调用大模型中
        case success            // 成功
        case error(AIAssistantPanelError)
    }
    var phase: Phase
    var sourceText: String?
    var result: AIProcessResult?
    var errorMessage: String?
}
```

`AIAssistantPanelView` 关键交互：

```swift
// 成功态布局
VStack(alignment: .leading, spacing: 12) {
    // 1. 思考过程：仅 reasoningText 非空时显示，DisclosureGroup 折叠
    if let reasoning = snapshot.result?.reasoningText, !reasoning.isEmpty {
        DisclosureGroup(isExpanded: $showReasoning) {
            Text(reasoning).font(.subheadline).foregroundStyle(.secondary)
        } label: {
            Label("思考过程", systemImage: "brain")
        }
    }

    // 2. 最终结果：可选 Markdown/纯文本渲染
    Text(snapshot.result?.text ?? "")
        .textSelection(.enabled)

    // 3. 一键复制
    Button {
        copyToPasteboard(snapshot.result?.text)
    } label: {
        Label("复制", systemImage: "doc.on.doc")
    }
}
```

- **一键复制**：`NSPasteboard.general.clearContents(); setString(text, forType: .string)`（同 `TranslatorCoordinator.copy`）。
- **面板宿主**：面板控制器实现 `AIAssistantPanelControlling`（`show/update/close`），通过 `PluginPrimaryPanel` 的 `.switch` + `menuActionBehavior: .keepPresented` 挂在菜单栏主面板，行为对齐 Translator。
- **权限引导**：`permissionRequirements` 声明 `accessibility`（读选中文本必须）、`automation`（浏览器划词按需）、`screen-recording` 仅在需要截图/OCR 时声明（本方案 MVP 不做截图，可省略，减少权限负担）。

---

## 7. 实现步骤（分阶段）

### 阶段 0：准备
1. 复制 `Plugins/Translator/` 目录骨架为 `Plugins/AIAssistant/`，全局重命名 `Translator*` → `AIAssistant*`。
2. 写 `plugin.json`：`id=ai-assistant`、`factoryClass`、`capabilities.settings=form`、`permissions=["accessibility","automation"]`、`category=productivity`、`minHostVersion` 取当前 host 版本。

### 阶段 1：AI 配置 + 存储
3. 落地 `OpenAICompatibleConfiguration`、`AIAssistantProviderProfile(+Store)`、`AIAssistantSecretStore`。
4. 落地 `AIAssistantPromptStore` 与默认模板（翻译/总结/润色）。

### 阶段 2：AI 调用
5. 复制并扩展 `OpenAICompatibleClient`（通用 `complete` + `reasoning_content` 解析）。
6. 落地 `PromptRenderer`（`{{text}}` 渲染）与 `AIProcessResult`。

### 阶段 3：快捷键 + 文本获取 + 协调器
7. 落地 `SelectedTextCapture` 三策略（复制或共享）。
8. `AIAssistantPlugin.shortcutDefinitions` 动态生成 + `handleShortcutAction(id:)` 解析 Prompt。
9. `AIAssistantCoordinator`：`capture → resolveProvider → complete → update(snapshot)`，Prompt 增删后 `onStateChange?()`。

### 阶段 4：结果面板 + 设置页
10. `AIAssistantPanelController/View/Snapshot`：思考折叠 + 复制。
11. `AIAssistantSettingsView`：Provider 配置区 + Prompt 列表（增删改 + 录制快捷键）。

### 阶段 5：验证与收尾
12. 单测（PromptStore 往返、Renderer 占位符、Configuration 校验、Coordinator 用 fake client 走通状态机）。
13. `make build-plugin PLUGIN=ai-assistant` → `make run` 本地联调。
14. 写 `changes/unreleased/ai-assistant.md`。

**本地验证命令**（对齐 AGENTS.md）：

```bash
make generate
make build-plugin PLUGIN=ai-assistant
make run
# 聚焦测试
xcodebuild -project MacTools.xcodeproj -scheme MacTools \
  -configuration Debug -derivedDataPath build/DerivedData test -quiet \
  -only-testing:MacToolsTests/AIAssistantCoordinatorTests
```

---

## 8. 市场上架（tools 市场）

MacTools 的插件市场是**目录（catalog）驱动**的，上架即「把插件打进带签名目录、随 GitHub Release 发布」。参考 `docs/plugins/plugin-catalog.md` 与 `docs/plugins/local-native-plugins.md`。

### 8.1 所需配置文件

| 文件 | 作用 | 谁生成 |
| --- | --- | --- |
| `Plugins/AIAssistant/plugin.json` | 插件清单（ID/版本/能力/权限/分类/构建 scheme） | 开发者手写 |
| `Plugins/AIAssistant/` 源码 + `Bundle/` + `Resources/` | 插件实现 | 开发者 |
| `docs/plugins/v4/host-1.2/catalog.json`（当前 PluginKit v4 host 线） | 生产目录（含签名、包 URL、sha256、size） | `make release` / CI 自动生成 |
| `changes/unreleased/ai-assistant.md` | 发布说明片段（`release: plugin` / `type: added`） | 开发者手写 |

`plugin.json` 的完整字段对齐 Translator（`localizedMetadata` 建议至少补 `zh-Hans` / `en`）：

```json
{
  "id": "ai-assistant",
  "displayName": "AI 助手",
  "summary": "划词调用 AI 翻译、总结、润色等",
  "version": "0.1.0",
  "minHostVersion": "1.2.0",
  "pluginKitVersion": 4,
  "bundleRelativePath": "AIAssistant.bundle",
  "factoryClass": "AIAssistantPlugin.AIAssistantPluginFactory",
  "build": { "project": "../../MacTools.xcodeproj", "scheme": "AIAssistantPlugin" },
  "capabilities": { "primaryPanel": true, "componentPanel": false, "settings": "form" },
  "permissions": ["accessibility", "automation"],
  "category": "productivity"
}
```

### 8.2 上架流程

1. **功能 PR 阶段**：只改插件代码/资源/测试，**不要手动 bump `plugin.json.version`**（`make release` 会自动处理，见 `local-native-plugins.md`）。
2. **发布**：运行 `make release` → 选 `plugin` 通道 → 选 `patch/minor/major`。助手会分析生产目录、展示计划中的 manifest 版本 bump。
3. 确认后自动：同步 `main` → bump 变更插件的 manifest 版本 → 把 `release: plugin` 片段编译进 `CHANGELOG.md` → 运行发布计划检查 → 提交 → 推送批量 tag（如 `plugins-1.0.x`）。
4. **GitHub Action（Plugin Release）**：读取当前 PluginKit 版本目录，`auto` 模式选中新增插件 → 构建 → 签名 → zip → 上传 `ai-assistant.mactoolsplugin.zip` 到 tag 对应 Release。
5. 生成 delta 目录并合并进 `docs/plugins/v4/host-1.2/catalog.json`，用 Ed25519 私钥签名（私钥来自 CI secrets，绝不入库）。
6. `Deploy Pages` 将签名目录发布到 GitHub Pages，市场即可在 App 内看到并安装 `ai-assistant`。

**本地打包演练**（对齐 `plugin-catalog.md`）：

```bash
make package-plugins-release \
  PLUGIN_CODE_SIGN_IDENTITY="Developer ID Application: Example (TEAMID)" \
  PLUGIN_CATALOG_PRIVATE_KEY_BASE64="$PLUGIN_CATALOG_PRIVATE_KEY_BASE64" \
  PLUGIN_RELEASE_TAG=plugins-1.0.x
```

---

## 9. 风险与注意事项

1. **动态快捷键的稳定 ID**：Prompt `id` 同时是 `shortcutDefinitions.actionID`，务必稳定、删除不复用；否则与 host 已持久化的快捷键绑定脱钩。
2. **AIText 捕获不落隐私坑**：只读取「已选中文本」与「可编辑输入框选中文本」，不主动读取整个输入框；API Key 只进 Keychain。
3. **思考字段兼容**：`reasoning_content` 为可选解析，模型不返回时 UI 自动隐藏，不得因缺字段报错。
4. **PluginKit ABI**：除非确需共享文本捕获，否则不要动 `Sources/MacToolsPluginKit/`（会全量重建所有插件）。
5. **不要重复注册快捷键**：默认绑定由 host 的 `ShortcutAssignmentService` 统一管理，插件不得自行 `RegisterEventHotKey` 二次注册。
6. **非流式优先**：MVP 用 `stream:false`，超时/取消/错误路径沿用 `OpenAICompatibleClientError` 统一映射为用户可读文案。

---

## 10. 与 Translator 的关系总结

| 维度 | Translator（现状） | AI Assistant（本方案） |
| --- | --- | --- |
| 定位 | 划词/截图翻译 | 通用 AI 处理，翻译为内置场景之一 |
| Prompt | 单一翻译模板 | 多组可自定义模板 |
| 快捷键 | 2 个固定（划词/截图） | N 个动态（随模板增减） |
| 结果 | 译文 | 思考过程 + 最终结果 |
| 复用 | — | 复用其工厂/配置/密钥/文本捕获/面板骨架 |

实现上「复制 + 扩展」而非「改造」，二者共存不冲突，`plugin.json.id`（`translator` 与 `ai-assistant`）互不影响，可独立上架、独立更新。
