import SwiftUI
import MacToolsPluginKit

struct AIAssistantSettingsView: View {
    @State private var profiles: [AIAssistantProviderProfile]
    @State private var prompts: [AIAssistantPrompt]
    @State private var apiKey: String
    @State private var selectedProfileID: String?
    @State private var message: String?
    @State private var messageIsError = false

    private let localization: PluginLocalization
    private let onSave: ([AIAssistantProviderProfile], [AIAssistantPrompt], String) -> String?
    private let onMakeNewPrompt: ([AIAssistantPrompt]) -> AIAssistantPrompt

    init(
        profiles: [AIAssistantProviderProfile],
        prompts: [AIAssistantPrompt],
        apiKey: String,
        localization: PluginLocalization = PluginLocalization(bundle: .main),
        onSave: @escaping ([AIAssistantProviderProfile], [AIAssistantPrompt], String) -> String?,
        onMakeNewPrompt: @escaping ([AIAssistantPrompt]) -> AIAssistantPrompt
    ) {
        _profiles = State(initialValue: profiles.isEmpty ? [AIAssistantProviderProfile.defaultProfile(localization: localization)] : profiles)
        _prompts = State(initialValue: prompts)
        _apiKey = State(initialValue: apiKey)
        _selectedProfileID = State(initialValue: profiles.first?.id ?? AIAssistantProviderProfile.defaultID)
        self.localization = localization
        self.onSave = onSave
        self.onMakeNewPrompt = onMakeNewPrompt
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PluginSettingsTheme.Spacing.section) {
            providerSection
            promptSection
            actions
        }
    }

    private var providerSection: some View {
        VStack(alignment: .leading, spacing: PluginSettingsTheme.Spacing.sectionHeaderContent) {
            sectionHeader(localization.string("settings.provider.title", defaultValue: "AI 服务"), icon: "network")

            VStack(spacing: 0) {
                editableFieldRow(
                    title: localization.string("settings.provider.name.title", defaultValue: "名称"),
                    description: localization.string("settings.provider.name.description", defaultValue: "显示在处理结果卡片上。")
                ) {
                    TextField("AI 服务", text: providerBinding(\.name))
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 280, idealWidth: 320, maxWidth: 420)
                }

                PluginSettingsListDivider()

                editableFieldRow(
                    title: localization.string("settings.provider.baseURL.title", defaultValue: "服务地址"),
                    description: localization.string("settings.provider.baseURL.description", defaultValue: "OpenAI 或兼容网关地址。")
                ) {
                    TextField("https://api.openai.com", text: providerBinding(\.baseURL))
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 280, idealWidth: 320, maxWidth: 420)
                }

                PluginSettingsListDivider()

                editableFieldRow(
                    title: localization.string("settings.provider.apiKey.title", defaultValue: "接口密钥"),
                    description: localization.string("settings.provider.apiKey.description", defaultValue: "留空则保留当前钥匙串内容。")
                ) {
                    SecureField("sk-...", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 280, idealWidth: 320, maxWidth: 420)
                        .onChange(of: apiKey) { _ in
                            message = nil
                            messageIsError = false
                        }
                }

                PluginSettingsListDivider()

                editableFieldRow(
                    title: localization.string("settings.provider.model.title", defaultValue: "模型"),
                    description: localization.string("settings.provider.model.description", defaultValue: "用于处理的模型名称。")
                ) {
                    TextField("gpt-5.4-mini", text: providerBinding(\.model))
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 280, idealWidth: 320, maxWidth: 420)
                }

                PluginSettingsListDivider()

                editableFieldRow(
                    title: localization.string("settings.provider.temperature.title", defaultValue: "温度"),
                    description: localization.string("settings.provider.temperature.description", defaultValue: "0-2，越高越有创造性。")
                ) {
                    Slider(
                        value: providerBinding(\.temperature),
                        in: 0 ... 2,
                        step: 0.1
                    )
                    .frame(minWidth: 160, idealWidth: 220, maxWidth: 280)
                }
            }
        }
    }

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: PluginSettingsTheme.Spacing.sectionHeaderContent) {
            HStack {
                sectionHeader(localization.string("settings.promptList.title", defaultValue: "处理模板"), icon: "square.stack.3d.up")
                Spacer()
                Button {
                    addPrompt()
                } label: {
                    Label(localization.string("settings.promptList.add", defaultValue: "添加"), systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            VStack(spacing: 0) {
                ForEach(Array(prompts.enumerated()), id: \.element.id) { index, prompt in
                    promptRow(index: index)
                    if prompt.id != prompts.last?.id {
                        PluginSettingsListDivider()
                    }
                }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: PluginSettingsTheme.Spacing.controlCluster) {
            Button(localization.string("settings.action.restoreDefaults", defaultValue: "恢复默认")) {
                profiles = [AIAssistantProviderProfile.defaultProfile(localization: localization)]
                prompts = AIAssistantPromptStore.defaultPrompts(localization: localization)
                selectedProfileID = profiles[0].id
                apiKey = ""
                message = nil
                messageIsError = false
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Spacer()

            if let message {
                Text(message)
                    .font(PluginSettingsTheme.Typography.rowDescription)
                    .foregroundStyle(messageIsError ? Color.red : Color.secondary)
            }

            Button(localization.string("settings.action.save", defaultValue: "保存")) {
                save()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }

    private func promptRow(index: Int) -> some View {
        let prompt = prompts[index]

        return VStack(alignment: .leading, spacing: PluginSettingsTheme.Spacing.rowTitleDescription) {
            HStack(spacing: PluginSettingsTheme.Spacing.rowContentControl) {
                Toggle("", isOn: promptEnabledBinding(for: index))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)

                TextField(
                    localization.string("settings.prompt.namePlaceholder", defaultValue: "模板名称"),
                    text: promptBinding(for: index, keyPath: \.name)
                )
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 120, idealWidth: 160, maxWidth: 200)

                Spacer(minLength: PluginSettingsTheme.Spacing.rowContentControl)

                iconButton("chevron.up", help: localization.string("settings.promptRow.moveUpHelp", defaultValue: "上移")) {
                    movePrompt(from: index, offset: -1)
                }
                .disabled(index == 0)

                iconButton("chevron.down", help: localization.string("settings.promptRow.moveDownHelp", defaultValue: "下移")) {
                    movePrompt(from: index, offset: 1)
                }
                .disabled(index == prompts.count - 1)

                iconButton("trash", help: localization.string("settings.promptRow.deleteHelp", defaultValue: "删除")) {
                    prompts.remove(at: index)
                    message = nil
                    messageIsError = false
                }
            }

            TextField(
                localization.string("settings.prompt.templatePlaceholder", defaultValue: "提示词，必须包含 {{text}}"),
                text: promptBinding(for: index, keyPath: \.template),
                axis: .vertical
            )
            .font(.body.monospaced())
            .textFieldStyle(.roundedBorder)
            .lineLimit(2 ... 4)

            TextField(
                localization.string("settings.prompt.systemPromptPlaceholder", defaultValue: "系统提示词（可选）"),
                text: promptSystemPromptBinding(for: index),
                axis: .vertical
            )
            .font(.body.monospaced())
            .textFieldStyle(.roundedBorder)
            .lineLimit(1 ... 2)
        }
        .pluginSettingsListRowPadding(interactive: true)
    }

    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(PluginSettingsTheme.Typography.sectionTitle)
            .foregroundStyle(.secondary)
    }

    private func editableFieldRow<Content: View>(
        title: String,
        description: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: PluginSettingsTheme.Spacing.rowContentControl) {
            VStack(alignment: .leading, spacing: PluginSettingsTheme.Spacing.rowTitleDescription) {
                Text(title)
                    .font(PluginSettingsTheme.Typography.rowTitle)
                Text(description)
                    .font(PluginSettingsTheme.Typography.rowDescription)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: PluginSettingsTheme.Spacing.rowContentControl)

            content()
        }
        .pluginSettingsListRowPadding(interactive: true)
    }

    private func iconButton(
        _ systemName: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .foregroundStyle(.secondary)
        .help(help)
    }

    private func providerBinding<Value>(
        _ keyPath: WritableKeyPath<AIAssistantProviderProfile, Value>
    ) -> Binding<Value> {
        Binding(
            get: {
                let index = profiles.firstIndex(where: { $0.id == selectedProfileID }) ?? 0
                return profiles[index][keyPath: keyPath]
            },
            set: {
                let index = profiles.firstIndex(where: { $0.id == selectedProfileID }) ?? 0
                profiles[index][keyPath: keyPath] = $0
                message = nil
                messageIsError = false
            }
        )
    }

    private func promptBinding<Value>(
        for index: Int,
        keyPath: WritableKeyPath<AIAssistantPrompt, Value>
    ) -> Binding<Value> {
        Binding(
            get: { prompts[index][keyPath: keyPath] },
            set: {
                prompts[index][keyPath: keyPath] = $0
                message = nil
                messageIsError = false
            }
        )
    }

    private func promptSystemPromptBinding(for index: Int) -> Binding<String> {
        Binding(
            get: { prompts[index].systemPrompt ?? "" },
            set: {
                prompts[index].systemPrompt = $0.isEmpty ? nil : $0
                message = nil
                messageIsError = false
            }
        )
    }

    private func promptEnabledBinding(for index: Int) -> Binding<Bool> {
        Binding(
            get: { prompts[index].isEnabled },
            set: {
                prompts[index].isEnabled = $0
                message = nil
                messageIsError = false
            }
        )
    }

    private func addPrompt() {
        let prompt = onMakeNewPrompt(prompts)
        prompts.append(prompt)
        message = nil
        messageIsError = false
    }

    private func movePrompt(from index: Int, offset: Int) {
        let target = index + offset
        guard prompts.indices.contains(index), prompts.indices.contains(target) else {
            return
        }

        prompts.swapAt(index, target)
        message = nil
        messageIsError = false
    }

    private func save() {
        if let errorMessage = onSave(profiles, prompts, apiKey) {
            message = errorMessage
            messageIsError = true
        } else {
            message = localization.string("settings.message.saved", defaultValue: "已保存")
            messageIsError = false
        }
    }
}
