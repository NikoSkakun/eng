import Foundation

extension DefinitionResult {
    /// A compact, human-readable rendering suitable for storing in the entry's
    /// `definition` column (one line per part of speech).
    var storedText: String {
        var lines: [String] = []
        for sense in senses.prefix(3) {
            let defs = sense.items.prefix(3).map { $0.definition }.joined(separator: "; ")
            if defs.isEmpty { continue }
            lines.append(sense.partOfSpeech.isEmpty ? defs : "(\(sense.partOfSpeech)) \(defs)")
        }
        return lines.joined(separator: "\n")
    }
}
