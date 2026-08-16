import Foundation
import MacToolsPluginKit

struct OpenAICompatibleConfiguration: Equatable, Sendable {
    static let defaultBaseURL = "https://api.openai.com"
    static let defaultModel = "gpt-5.4-mini"

    var baseURL: String
    var model: String

    var normalizedBaseURL: String {
        baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedModel: String {
        model.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    init(
        baseURL: String = Self.defaultBaseURL,
        model: String = Self.defaultModel
    ) {
        self.baseURL = baseURL
        self.model = model
    }

    var validationError: OpenAICompatibleConfigurationError? {
        if normalizedBaseURL.isEmpty {
            return .blankBaseURL
        }

        guard let components = URLComponents(string: normalizedBaseURL),
              let host = components.host,
              !host.isEmpty,
              Self.isAllowedScheme(components.scheme, host: host)
        else {
            return .invalidBaseURL
        }

        if normalizedModel.isEmpty {
            return .blankModel
        }

        return nil
    }

    func endpointURL() throws -> URL {
        if let validationError {
            throw validationError
        }

        guard var components = URLComponents(string: normalizedBaseURL),
              let host = components.host,
              !host.isEmpty,
              Self.isAllowedScheme(components.scheme, host: host)
        else {
            throw OpenAICompatibleConfigurationError.invalidBaseURL
        }

        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let pathComponents = basePath.isEmpty ? [] : basePath.split(separator: "/").map(String.init)
        let lowercasedPathComponents = pathComponents.map { $0.lowercased() }
        let completionPathComponents: [String]

        if Array(lowercasedPathComponents.suffix(2)) == ["chat", "completions"] {
            completionPathComponents = pathComponents
        } else if lowercasedPathComponents.last == "v1" {
            completionPathComponents = pathComponents + ["chat", "completions"]
        } else {
            completionPathComponents = pathComponents + ["v1", "chat", "completions"]
        }

        components.path = "/" + completionPathComponents.joined(separator: "/")

        guard let url = components.url else {
            throw OpenAICompatibleConfigurationError.invalidBaseURL
        }

        return url
    }

    private static func isAllowedScheme(_ scheme: String?, host: String) -> Bool {
        guard let scheme = scheme?.lowercased() else {
            return false
        }

        if scheme == "https" {
            return true
        }

        return scheme == "http" && isTrustedHTTPHost(host)
    }

    /// HTTP is only allowed for loopback and private (RFC 1918) hosts so that
    /// local gateways and intranet endpoints can be used without forcing TLS,
    /// while public plaintext HTTP remains blocked.
    private static func isTrustedHTTPHost(_ host: String) -> Bool {
        let normalizedHost = host
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .lowercased()

        if normalizedHost == "localhost"
            || normalizedHost == "127.0.0.1"
            || normalizedHost == "::1" {
            return true
        }

        return isPrivateIPv4Host(normalizedHost)
    }

    private static func isPrivateIPv4Host(_ host: String) -> Bool {
        let octets = host.split(separator: ".").compactMap { UInt8($0) }
        guard octets.count == 4 else {
            return false
        }

        // 10.0.0.0/8
        if octets[0] == 10 {
            return true
        }
        // 172.16.0.0/12
        if octets[0] == 172, octets[1] >= 16, octets[1] <= 31 {
            return true
        }
        // 192.168.0.0/16
        if octets[0] == 192, octets[1] == 168 {
            return true
        }
        return false
    }
}

enum OpenAICompatibleConfigurationError: Error, Equatable, Sendable {
    case blankBaseURL
    case invalidBaseURL
    case blankModel
}

extension OpenAICompatibleConfigurationError: LocalizedError {
    var errorDescription: String? {
        errorDescription()
    }

    func errorDescription(localization: PluginLocalization = PluginLocalization(bundle: .main)) -> String {
        switch self {
        case .blankBaseURL:
            return localization.string("openAIConfiguration.error.blankBaseURL", defaultValue: "Base URL 不能为空。")
        case .invalidBaseURL:
            return localization.string("openAIConfiguration.error.invalidBaseURL", defaultValue: "Base URL 无效。")
        case .blankModel:
            return localization.string("openAIConfiguration.error.blankModel", defaultValue: "模型不能为空。")
        }
    }
}
