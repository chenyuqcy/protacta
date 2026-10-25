import Foundation

/// A deliberately small command vocabulary, not a natural-language or AI
/// interpreter. Only a complete supported phrase can dispatch a lesson action.
enum VoiceCommand: String, CaseIterable, Identifiable {
    case next, back, replay, restart, slower, normalSpeed, pause, resume
    case readStep, explainSimply, why, help, stopListening

    var id: String { rawValue }

    var phrase: String {
        switch self {
        case .next: return "Next step"
        case .back: return "Previous step"
        case .replay: return "Show me again"
        case .restart: return "Restart lesson"
        case .slower: return "Slower"
        case .normalSpeed: return "Normal speed"
        case .pause: return "Pause"
        case .resume: return "Continue"
        case .readStep: return "Read this step"
        case .explainSimply: return "Explain it more simply"
        case .why: return "Why this fold?"
        case .help: return "I'm stuck"
        case .stopListening: return "Stop listening"
        }
    }

    static func parse(_ transcript: String) -> VoiceCommand? {
        var words = normalizedWords(transcript)
        // A single optional courtesy word at either edge does not change the
        // command. Other sentence fragments and repeated commands stay invalid.
        if words.first == "please" { words.removeFirst() }
        if words.last == "please" { words.removeLast() }
        guard !words.isEmpty else { return nil }
        return commandsByPhrase[words.joined(separator: " ")]
    }

    /// Include supported aliases so the recognizer hears both current hints
    /// and familiar commands from earlier app versions.
    static var contextualPhrases: [String] {
        var seen: Set<String> = []
        return allCases.flatMap { [$0.phrase] + $0.aliases }
            .filter { seen.insert(normalizedWords($0).joined(separator: " ")).inserted }
    }

    private var aliases: [String] {
        switch self {
        case .next:
            return ["next", "next fold", "go to the next step", "go to the next fold"]
        case .back:
            return ["back", "go back", "previous fold", "go to the previous step"]
        case .replay:
            return ["replay", "replay this fold", "replay this step", "repeat this fold", "repeat this step", "show it again"]
        case .restart:
            return ["restart", "restart the lesson", "start over", "start the lesson over", "start from the beginning"]
        case .slower:
            return ["slow down", "slow it down", "slow motion", "play slower"]
        case .normalSpeed:
            return ["regular speed", "play at normal speed", "back to normal speed"]
        case .pause:
            return ["pause this fold", "pause animation", "pause the animation"]
        case .resume:
            return ["resume", "resume this fold", "continue folding", "play", "play this fold"]
        case .readStep:
            return ["read the step", "read the instructions", "read this fold", "read it aloud"]
        case .explainSimply:
            return ["explain more simply", "explain this more simply", "explain simply", "make it simpler"]
        case .why:
            return ["why", "why this step", "why should I do this", "why do I need to do this"]
        case .help:
            return ["I am stuck", "im stuck", "help", "help me", "help with this step", "help with this fold"]
        case .stopListening:
            return ["turn off the microphone", "turn off microphone", "microphone off", "stop voice commands"]
        }
    }

    private static let commandsByPhrase: [String: VoiceCommand] = {
        var result: [String: VoiceCommand] = [:]
        for command in allCases {
            for phrase in [command.phrase] + command.aliases {
                let key = normalizedWords(phrase).joined(separator: " ")
                precondition(result[key] == nil || result[key] == command, "Voice command aliases must be unambiguous")
                result[key] = command
            }
        }
        return result
    }()

    private static func normalizedWords(_ phrase: String) -> [String] {
        let lowercased = phrase.lowercased(with: Locale(identifier: "en_US_POSIX"))
        // Treat punctuation as word boundaries, including dictation's curly
        // apostrophe in “I'm”. Keeping digits prevents “next step 12” from
        // silently turning into a supported next-step command.
        let separated = lowercased.unicodeScalars.map { scalar -> String in
            CharacterSet.alphanumerics.contains(scalar) ? String(scalar) : " "
        }.joined()
        return separated.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }
}
