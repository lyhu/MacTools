import Foundation
import MacToolsPluginKit

struct AIAssistantProviderProfile: Codable, Equatable, Identifiable, Sendable {
    static let defaultID = "default"

    var id: String
    var name: String
    var isEnabled: Bool
    var baseURL: String
    var model: String
    var temperature: Double

    init(
        id: String = UUID().uuidString,
        name: String,
        isEnabled: Bool = true,
        baseURL: String = OpenAICompatibleConfiguration.defaultBaseURL,
        model: String = OpenAICompatibleConfiguration.defaultModel,
        temperature: Double = 0.7
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.baseURL = baseURL
        self.model = model
        self.temperature = temperature
    }

    static func defaultProfile(
        localization: PluginLocalization = PluginLocalization(bundle: .main)
    ) -> AIAssistantProviderProfile {
        AIAssistantProviderProfile(
            id: defaultID,
            name: localization.string("provider.defaultName", defaultValue: "AI 服务"),
            isEnabled: true
        )
    }

    var normalizedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var configuration: OpenAICompatibleConfiguration {
        OpenAICompatibleConfiguration(baseURL: baseURL, model: model)
    }

    var validationError: AIAssistantProviderProfileValidationError? {
        if normalizedName.isEmpty {
            return .blankName
        }

        if let configurationError = configuration.validationError {
            return .configuration(configurationError)
        }

        return nil
    }

    func normalized() -> AIAssistantProviderProfile {
        var copy = self
        copy.name = normalizedName
        copy.baseURL = configuration.normalizedBaseURL
        copy.model = configuration.normalizedModel
        return copy
    }
}

enum AIAssistantProviderProfileValidationError: Error, Equatable, Sendable {
    case blankName
    case configuration(OpenAICompatibleConfigurationError)
}

extension AIAssistantProviderProfileValidationError: LocalizedError {
    var errorDescription: String? {
        errorDescription()
    }

    func errorDescription(localization: PluginLocalization = PluginLocalization(bundle: .main)) -> String {
        switch self {
        case .blankName:
            return localization.string("providerProfile.error.blankName", defaultValue: "服务名称不能为空。")
        case let .configuration(error):
            return error.errorDescription(localization: localization)
        }
    }
}

@MainActor
struct AIAssistantProviderProfileStore {
    let storage: PluginStorage
    let localization: PluginLocalization

    init(
        storage: PluginStorage,
        localization: PluginLocalization = PluginLocalization(bundle: .main)
    ) {
        self.storage = storage
        self.localization = localization
    }

    func loadProfiles() -> [AIAssistantProviderProfile] {
        if let data = storage.data(forKey: AIAssistantConstants.StorageKey.providerProfiles),
           let profiles = try? JSONDecoder().decode([AIAssistantProviderProfile].self, from: data),
           !profiles.isEmpty {
            return profiles
        }

        return [AIAssistantProviderProfile.defaultProfile(localization: localization)]
    }

    func saveProfiles(_ profiles: [AIAssistantProviderProfile]) throws {
        let normalizedProfiles = profiles.map { $0.normalized() }
        let data = try JSONEncoder().encode(normalizedProfiles)
        storage.set(data, forKey: AIAssistantConstants.StorageKey.providerProfiles)
    }
}
