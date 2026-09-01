import Foundation

/// Result of a translation lookup.
struct TranslationResult: Codable {
    var translatedText: String
    var alternatives: [String] = []
    var providerId: String
    var attribution: String?
}

/// A single sense/definition, optionally with an example sentence.
struct DefinitionItem: Codable {
    var definition: String
    var example: String?
}

/// A part-of-speech grouping of definitions.
struct DefinitionSense: Codable {
    var partOfSpeech: String
    var items: [DefinitionItem]
}

/// Result of a monolingual definition lookup.
struct DefinitionResult: Codable {
    var word: String
    var phonetic: String?
    var senses: [DefinitionSense] = []
    var providerId: String
    var attribution: String?
    var audioUrl: String?

    var isEmpty: Bool { senses.isEmpty }
}

/// Raised when a provider cannot fulfil a request. `notFound` distinguishes a
/// plain "nothing here" (HTTP 404) from a transport/quota failure, so the
/// service knows whether to fall back to another provider.
struct ProviderError: Error {
    let message: String
    var notFound = false
    var needsConfiguration = false

    init(_ message: String, notFound: Bool = false, needsConfiguration: Bool = false) {
        self.message = message
        self.notFound = notFound
        self.needsConfiguration = needsConfiguration
    }
}
