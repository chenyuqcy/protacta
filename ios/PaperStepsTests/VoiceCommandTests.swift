import XCTest
@testable import Foliafold

final class VoiceCommandTests: XCTestCase {
    func testEveryDisplayedCommandCanBeSpokenWithCasePunctuationAndCourtesyWords() {
        for command in VoiceCommand.allCases {
            XCTAssertEqual(VoiceCommand.parse(command.phrase), command, command.rawValue)
            XCTAssertEqual(VoiceCommand.parse("  PLEASE, \(command.phrase.uppercased())! Please.  "), command, command.rawValue)
        }
    }

    func testSupportedDictationVariationsDispatchTheirExactActions() {
        let examples: [(String, VoiceCommand)] = [
            ("next\n\tstep", .next),
            ("Go to the next fold.", .next),
            ("Previous step, please.", .back),
            ("please replay this fold", .replay),
            ("Show it again!", .replay),
            ("Slow it down.", .slower),
            ("Play at normal speed", .normalSpeed),
            ("Pause the animation", .pause),
            ("Resume this fold", .resume),
            ("Read it aloud", .readStep),
            ("Make it simpler", .explainSimply),
            ("Why should I do this?", .why),
            ("I’m stuck.", .help),
            ("I am stuck", .help),
            ("im stuck", .help),
            ("Microphone off", .stopListening)
        ]
        for (transcript, command) in examples {
            XCTAssertEqual(VoiceCommand.parse(transcript), command, transcript)
        }
    }

    func testNegationAndUnrelatedSentencesCannotTriggerSubstringCommands() {
        let rejected = [
            "do not go back", "don't go back", "don’t go back", "never go back",
            "don't show me again", "not next fold", "please don't continue",
            "I don't want to pause", "do not stop listening",
            "the next fold is difficult", "I said show me again yesterday",
            "can you tell me what comes after the next fold",
            "why is the sky blue", "read this step after I finish",
            "show me again if it is safe", "please explain another tutorial",
            "next step 12", "nextfold", "playground", "slower than before",
            "下一步", "what is my account password"
        ]
        for transcript in rejected {
            XCTAssertNil(VoiceCommand.parse(transcript), transcript)
        }
    }

    func testCompoundAmbiguousAndRepeatedCommandsAreRejected() {
        for transcript in [
            "next fold and go back", "next fold, go back", "next fold or go back",
            "pause then continue", "read this step and explain it more simply",
            "stop listening and go back", "next next", "next fold next fold",
            "please please next fold", "next fold please please", "stop", "faster"
        ] {
            XCTAssertNil(VoiceCommand.parse(transcript), transcript)
        }
    }

    func testEmptyInputAndCourtesyWordsAloneDoNothing() {
        for transcript in ["", " \n\t ", "?!…", "please", "please please", "123"] {
            XCTAssertNil(VoiceCommand.parse(transcript), transcript)
        }
    }

    func testCoreHintsUseTheRequestedEnglishPhrasesAndKeepOlderAliases() {
        XCTAssertEqual(VoiceCommand.next.phrase, "Next step")
        XCTAssertEqual(VoiceCommand.back.phrase, "Previous step")
        XCTAssertEqual(VoiceCommand.replay.phrase, "Show me again")
        XCTAssertEqual(VoiceCommand.parse("Next fold"), .next)
        XCTAssertEqual(VoiceCommand.parse("Go back"), .back)
        XCTAssertEqual(VoiceCommand.parse("replay this step"), .replay)
    }

    func testRestartIsExplicitAndDoesNotReplaceStepReplay() {
        for text in ["Restart lesson", "restart the lesson", "Start over", "start from the beginning"] {
            XCTAssertEqual(VoiceCommand.parse(text), .restart, text)
        }
        XCTAssertEqual(VoiceCommand.parse("Show me again"), .replay)
        XCTAssertEqual(VoiceCommand.parse("repeat this step"), .replay)
        for text in ["do not restart", "don't start over", "restart lesson and go back", "start over tomorrow", "restart lesson 2"] {
            XCTAssertNil(VoiceCommand.parse(text), text)
        }
    }

    func testRecognitionContextContainsOnlyUnambiguousSupportedPhrases() throws {
        let phrases = VoiceCommand.contextualPhrases
        XCTAssertEqual(phrases.count, Set(phrases.map { $0.lowercased() }).count)
        for phrase in phrases {
            XCTAssertNotNil(VoiceCommand.parse(phrase), phrase)
        }
        for phrase in ["Next step", "Previous step", "Show me again", "Restart lesson", "next fold", "go back"] {
            XCTAssertTrue(phrases.contains(phrase), phrase)
        }
    }

    func testContinueAndReplayRemainDifferentCommands() {
        // Resume must finish the current partial fold; replay may reset it.
        XCTAssertEqual(VoiceCommand.parse("Continue"), .resume)
        XCTAssertEqual(VoiceCommand.parse("Next fold"), .next)
        XCTAssertEqual(VoiceCommand.parse("Show me again"), .replay)
        XCTAssertEqual(VoiceCommand.parse("Pause"), .pause)
        XCTAssertEqual(VoiceCommand.parse("Stop listening"), .stopListening)
    }
}
