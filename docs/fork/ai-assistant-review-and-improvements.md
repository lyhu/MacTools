# AI Assistant — Review Summary and Improvement Plan

Follow-up to `docs/fork/ai-assistant-implementation-plan.md`.

Review baseline: `HEAD` (`621acb09`). The plugin is uncommitted work under `Plugins/AIAssistant/`. Spec source: the implementation plan above. Axes: **Standards** (repo rules) and **Spec** (plan fidelity). They are listed separately on purpose.

---

## 1. Current status

MVP core is in place and matches the plan's intended path:

| Area | Status |
| --- | --- |
| Plugin id / factory / category / permissions | Done (`ai-assistant`, `AIAssistantPluginFactory`, `productivity`, accessibility + automation) |
| OpenAI-compatible provider + Keychain API key | Done |
| Prompt store + dynamic per-prompt shortcuts | Done |
| Selected-text capture (AX / AppleScript / simulated copy) | Done (copied from Translator, no PluginKit ABI change) |
| Non-stream `complete` + `reasoning_content` parse | Done |
| Result panel: fold reasoning + copy | Done |
| Changelog fragment | Done (`changes/unreleased/ai-assistant.md`) |
| Adjacent XCTest coverage | Done (stores, renderer, config, coordinator, plugin, client) |

The remaining work is correctness, host conventions, and a few spec mismatches — not a missing skeleton.

---

## 2. Standards findings

### Hard (repo rules)

| Priority | Finding | Rule | Action |
| --- | --- | --- | --- |
| P0 | Repeatable “run prompt on selection” is only `handleShortcutAction`. No `PluginActionProviding` and no inventory rationale. | `CONTRIBUTING.md`, `docs/plugins/local-native-plugins.md`, `docs/plugins/action-provider-coverage.md` | Publish a stable action (or write an explicit skip rationale in the coverage inventory). Workflows, Run Links, and Action Grid cannot call this plugin today. |
| P0 | User-visible plugin is not listed in `README.md` / `README.zh-CN.md`. | `AGENTS.md`, `CONTRIBUTING.md` | Add a short feature entry when the plugin is user-facing. |
| P1 | Settings chrome: host section title `"AI 助手设置"` plus inner `sectionHeader("AI 服务" / "处理模板")`. | `AGENTS.md` plugin settings UI | Drop the extra page-level title. Let the host own section headers, or use declarative `PluginSettingsPage.form` sections. |
| P1 | Settings placeholders (`"AI 服务"`, `"https://api.openai.com"`, `"sk-..."`, `"gpt-5.4-mini"`) are raw strings. | Localize settings copy via `.xcstrings` | Move every user-visible string, including placeholders, into `Localizable.xcstrings`. |
| P1 | `AIAssistantSettingsView.iconButton` uses `.font(.system(size: 12, weight: .medium))`. | `PluginSettingsTheme` typography | Use `PluginSettingsTheme.Typography` tokens only. |
| P2 | Test files `AIAssistantClientTests.swift` / `AIAssistantConfigurationTests.swift` do not match type names `OpenAICompatibleClient` / `OpenAICompatibleConfiguration`. | `<TypeName>Tests.swift` | Rename to match the types they cover. |
| P2 | `docs/fork/` is not a documented tree; agent Markdown is required to be English; plugin/debug docs already live under `docs/plugins/` and large specs under `docs/superpowers/`. | `AGENTS.md`, `CONTRIBUTING.md` | Keep this folder as local planning only, or move lasting docs to the documented trees. |

Already aligned: changelog English fragment, `plugin.json.id` == `PluginMetadata.id`, `capabilities.settings` == `form`.

### Judgement (smells)

- **Duplicated code:** `userFacingMessage` is copied in `AIAssistantPlugin` and `AIAssistantCoordinator`. Extract one helper.
- **Speculative generality:** `cachedPromptBindings` is written and never read. `profiles` / `selectedProfileID` imply a multi-provider picker that does not exist. Profile `temperature` is edited and persisted, but the client ignores it.
- **Middle man:** `AIAssistantPanelHostView` only forwards `model.snapshot`.
- **Divergent change:** `AIAssistantPlugin` owns panel copy, permissions, shortcuts, Keychain, validation, and coordinator lifecycle. Split stores / coordinator wiring if the class keeps growing.

---

## 3. Spec findings

### Missing or partial

| Priority | Spec line | Gap |
| --- | --- | --- |
| P0 | Request body should add optional `reasoning` fields (DeepSeek / Qwen thinking models). | `OpenAIChatCompletionsRequest` is only `model` / `messages` / `temperature` / `stream`. Response `reasoning_content` is parsed; the request never asks for thinking output. |
| P0 | Profile: `var temperature: Double // default 0.2`. | UI slider persists temperature; `complete()` always sends `0.7`. `OpenAICompatibleConfiguration` has no temperature field. Users think the slider works. |
| P1 | Built-in `翻译` is 中英互译 / multi-language. | Default template is one-way: “请将下面的文本翻译为简体中文.” |
| P1 | Default model `gpt-4o-mini` or user-filled. | Code and tests use `gpt-5.4-mini`. |
| P2 | Optional `PluginShortcutBindingChangeHandling` to cache bindings for recreate. | Cache is written; `defaultBinding` stays `nil`; cache is never restored. Protocol is optional for MVP — either implement restore or delete the stub. |
| P3 | File list: standalone `AIAssistantProviderProfileStore.swift`, `OpenAI/AIProcessResult.swift`, `AIAssistantPanelSnapshot.swift`, split capture files. | Types were merged into existing files. Functional, not a user-facing gap. Do not reshuffle unless it helps navigation. |

### Scope beyond the spec (keep if useful, do not treat as missing)

- Menu-bar master switch (`ai-assistant.shortcut.enabled`); shortcuts no-op when off.
- Settings “恢复默认”, prompt reorder.
- Result panel retry, “如何解决”, and source card.
- Extra sources (`AIAssistantLog`, `AIAssistantHTTPClient`, `AIAssistantPanelWindow`) and extra tests (`AIAssistantClientTests`, `AIAssistantPluginTests`).

These extras are reasonable Translator carry-over. Keep the master switch and retry; they do not conflict with the plan.

### Implemented but wrong

Same three as above: temperature slider vs hardcoded `0.7`; binding-change protocol without restore; default 翻译 template vs 中英互译.

---

## 4. Recommended work order

### P0 — correctness and host contract

1. **Wire temperature end to end.**
   - Add `temperature` to `OpenAICompatibleConfiguration` (or pass it from the selected profile).
   - Send `profile.temperature` from `complete()`.
   - Default: pick one number and use it everywhere. Spec says `0.2`; current UI/tests use `0.7`. Prefer `0.2` if following the plan, or update the plan if `0.7` is intentional.
   - Extend `AIAssistantClientTests` to assert the encoded body uses the configured value.

2. **Optional request-side reasoning.**
   - Add an optional request field (or a small per-provider toggle) for models that require `reasoning` / `enable_thinking` style flags.
   - Keep response `reasoning_content` parsing.
   - Hide the thinking UI when the field is absent (already done).

3. **`PluginActionProviding`.**
   - One stable action per enabled prompt, or one action with a prompt parameter — match existing Translator / Action Grid patterns before inventing a new shape.
   - If this plugin should stay shortcut-only for MVP, add the required inventory rationale instead of shipping a silent gap.

### P1 — product defaults and settings chrome

4. Change the default 翻译 template to bidirectional Chinese/English (and keep “only return the translation”).
5. Align the default model with the plan (`gpt-4o-mini`) or document why `gpt-5.4-mini` is the placeholder.
6. Localize leftover settings placeholders; remove the inner page/section title; replace raw `12pt` fonts with `PluginSettingsTheme`.
7. Add README / README.zh-CN entries.

### P2 — cleanup

8. Either restore cached bindings into `defaultBinding` when a prompt is recreated, or delete `cachedPromptBindings` and drop `PluginShortcutBindingChangeHandling`.
9. Rename tests: `OpenAICompatibleClientTests.swift`, `OpenAICompatibleConfigurationTests.swift`.
10. Deduplicate `userFacingMessage`.
11. Collapse unused multi-provider UI state (`selectedProfileID`) until a real picker exists. Keep the profile array if it matches Translator storage.

### P3 — later (plan already marks these as follow-ups)

- Streaming SSE for live reasoning.
- Shared `SelectedTextCapture` in Core / PluginKit (ABI + full plugin rebuild).
- Read full `AXValue` when the field has no selection (opt-in only).
- Marketplace catalog entry (`make release` / plugin batch). Not part of this working-tree review.

---

## 5. Suggested verification

```bash
make generate
make build-plugin PLUGIN=ai-assistant

xcodebuild -project MacTools.xcodeproj -scheme MacTools \
  -configuration Debug -derivedDataPath build/DerivedData test -quiet \
  -only-testing:MacToolsTests/AIAssistantCoordinatorTests \
  -only-testing:MacToolsTests/AIAssistantClientTests \
  -only-testing:MacToolsTests/AIAssistantConfigurationTests \
  -only-testing:MacToolsTests/AIAssistantPromptStoreTests \
  -only-testing:MacToolsTests/AIAssistantPromptRendererTests \
  -only-testing:MacToolsTests/AIAssistantPluginTests
```

After P0, add or update a client test that:

- encodes the profile temperature (not `0.7` unless that is the configured value);
- optionally includes a reasoning request field when enabled;
- still parses `reasoning_content` and hides it when missing.

Manual: set temperature to `0`, run 翻译, confirm the request body (proxy or test double) is `0`; toggle the menu-bar switch off and confirm shortcuts do nothing.

---

## 6. Counts

- **Standards:** 11 findings. Worst: executable capability is shortcut-only (`PluginActionProviding` missing).
- **Spec:** 12 findings. Worst: temperature is shown and saved, then ignored (`0.7` hardcoded).
