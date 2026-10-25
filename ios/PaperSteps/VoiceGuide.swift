import AVFoundation
import Combine
import Foundation
import Speech
import UIKit

/// One recognition task can deliver many revisions, but can dispatch only once.
/// Kept independent of the microphone so revision/cancellation rules are testable.
struct VoiceUtteranceGate {
    struct Candidate: Equatable {
        let revision: Int
        let transcript: String
    }

    private(set) var transcript = ""
    private(set) var revision = 0
    private(set) var isConsumed = false

    @discardableResult
    mutating func update(_ text: String) -> Bool {
        guard !isConsumed, text != transcript else { return false }
        transcript = text
        revision += 1
        return true
    }

    var candidate: Candidate? {
        guard !isConsumed, VoiceCommand.parse(transcript) != nil else { return nil }
        return Candidate(revision: revision, transcript: transcript)
    }

    mutating func consumeStable(_ candidate: Candidate) -> VoiceCommand? {
        guard !isConsumed, candidate.revision == revision,
              candidate.transcript == transcript,
              let command = VoiceCommand.parse(transcript) else { return nil }
        isConsumed = true
        return command
    }

    mutating func consumeFinal(_ text: String) -> VoiceCommand? {
        guard !isConsumed else { return nil }
        update(text)
        isConsumed = true
        return VoiceCommand.parse(text)
    }
}

/// Explicitly enabled, English, on-device commands and system narration.
/// Transcripts exist only in memory; no audio files or network fallback are used.
@MainActor
final class VoiceGuide: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var isEnabled = false
    @Published private(set) var isListening = false
    @Published private(set) var isSpeaking = false
    @Published private(set) var isRequestingPermission = false
    @Published private(set) var status = "Voice commands are off."
    @Published private(set) var lastHeard = ""
    @Published private(set) var recoveryMessage: String?

    var onCommand: ((VoiceCommand) -> Void)?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recoveryPolicy = VoiceRecoveryPolicy()
    private let engine = AVAudioEngine()
    private let synthesizer = AVSpeechSynthesizer()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var tapInstalled = false
    private var generation: UInt64 = 0
    private var permissionGeneration: UInt64 = 0
    private var recognitionGeneration: UInt64 = 0
    private var utteranceGate = VoiceUtteranceGate()
    private var stablePartialTask: Task<Void, Never>?
    private var turnoverTask: Task<Void, Never>?
    private var rearmTask: Task<Void, Never>?
    private var activeUtterance: AVSpeechUtterance?
    private var pendingActivation: UInt64?
    private var sceneIsActive = true
    private var notificationObservers: [NSObjectProtocol] = []

    override init() {
        super.init()
        synthesizer.delegate = self
        notificationObservers.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let type = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber)?.uintValue
            guard type == AVAudioSession.InterruptionType.began.rawValue else { return }
            Task { @MainActor [weak self] in
                self?.stopForAudioChange("Audio was interrupted. Tap Retry voice to listen again.")
            }
        })
        notificationObservers.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let reason = (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? NSNumber)?.uintValue
            // Switching our own playback/recognition category emits this notification;
            // it does not mean the microphone/headphone route was disconnected.
            guard reason != AVAudioSession.RouteChangeReason.categoryChange.rawValue else { return }
            Task { @MainActor [weak self] in
                self?.stopForAudioChange("The audio device changed. Tap Retry voice to listen again.")
            }
        })
    }

    deinit {
        notificationObservers.forEach(NotificationCenter.default.removeObserver)
        stablePartialTask?.cancel()
        turnoverTask?.cancel()
        rearmTask?.cancel()
        recognitionTask?.cancel()
        engine.stop()
        if tapInstalled { engine.inputNode.removeTap(onBus: 0) }
    }

    func startListening() async {
        guard !isRequestingPermission, !isListening else { return }
        stop()
        recoveryPolicy.reset()
        guard !Self.isAutomatedUITest else {
            fail("Voice input is unavailable in automated tests. Use the lesson buttons.")
            return
        }
        #if targetEnvironment(simulator)
        fail("Voice input needs a supported iPhone or iPad. Use the lesson buttons here.")
        return
        #else
        guard let recognizer, recognizer.supportsOnDeviceRecognition else {
            fail("On-device English speech is unavailable. Use the lesson buttons.")
            return
        }
        guard sceneIsActive, UIApplication.shared.applicationState != .background else { return }
        isEnabled = true
        isRequestingPermission = true
        status = "Allow speech and microphone access to use voice commands."
        let token = permissionGeneration

        let speechPermission: SFSpeechRecognizerAuthorizationStatus
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            speechPermission = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
            }
        } else {
            speechPermission = SFSpeechRecognizer.authorizationStatus()
        }
        guard token == permissionGeneration, isEnabled else { return }
        guard speechPermission == .authorized else {
            fail("Speech access is unavailable. Enable it in Settings, or use the lesson buttons.")
            return
        }

        let microphoneAllowed: Bool
        switch AVAudioApplication.shared.recordPermission {
        case .granted: microphoneAllowed = true
        case .denied: microphoneAllowed = false
        case .undetermined:
            microphoneAllowed = await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
            }
        @unknown default: microphoneAllowed = false
        }
        guard token == permissionGeneration, isEnabled else { return }
        guard microphoneAllowed else {
            fail("Microphone access is unavailable. Enable it in Settings, or use the lesson buttons.")
            return
        }
        isRequestingPermission = false
        guard UIApplication.shared.applicationState != .background else { stop(); return }
        // A permission completion can arrive just before the system dismisses
        // its own prompt. The matching active event may start this request once.
        guard canUseAudio else {
            pendingActivation = generation
            status = "Voice is ready when you return to the lesson."
            return
        }
        beginRecognition()
        #endif
    }

    func stop() {
        generation &+= 1
        permissionGeneration &+= 1
        isEnabled = false
        isRequestingPermission = false
        pendingActivation = nil
        rearmTask?.cancel()
        rearmTask = nil
        stopRecognition()
        cancelNarration()
        deactivateAudio()
        lastHeard = ""
        recoveryMessage = nil
        status = "Voice commands are off."
    }

    func contextDidChange() {
        generation &+= 1
        pendingActivation = nil
        rearmTask?.cancel()
        rearmTask = nil
        stopRecognition()
        cancelNarration()
        if isEnabled, !isRequestingPermission {
            scheduleRearm(generation: generation)
        } else {
            deactivateAudio()
            status = isRequestingPermission ? "Waiting for speech and microphone permission." : "Voice commands are off."
        }
    }

    func speak(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        generation &+= 1
        pendingActivation = nil
        rearmTask?.cancel()
        rearmTask = nil
        stopRecognition()
        cancelNarration()
        guard !Self.isAutomatedUITest else {
            status = "Read-aloud is unavailable in automated tests. Read the explanation on screen."
            return
        }
        guard canUseAudio else { stop(); return }
        do {
            try activateNarrationAudio()
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
            activeUtterance = utterance
            isSpeaking = true
            status = "Reading the explanation."
            synthesizer.speak(utterance)
        } catch {
            fail("Read-aloud could not start. Read the explanation, or try again.")
        }
    }

    func handleSceneInactive() {
        if isRequestingPermission || (pendingActivation != nil && UIApplication.shared.applicationState != .background) {
            return
        }
        sceneIsActive = false
        stop()
    }

    func handleSceneActive() {
        sceneIsActive = true
        guard let token = pendingActivation, token == generation, isEnabled else { return }
        pendingActivation = nil
        beginRecognition()
    }

    private static var isAutomatedUITest: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-testing")
    }

    private var canUseAudio: Bool {
        sceneIsActive && UIApplication.shared.applicationState == .active
    }

    private func activateRecognitionAudio() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try audioSession.setActive(true)
    }

    private func activateNarrationAudio() throws {
        let audioSession = AVAudioSession.sharedInstance()
        // Narration has no input requirement and remains usable when microphone
        // access is denied or has never been requested.
        try audioSession.setCategory(.playback, mode: .spokenAudio)
        try audioSession.setActive(true)
    }

    private func deactivateAudio() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func beginRecognition() {
        guard isEnabled, !isSpeaking, !isRequestingPermission, canUseAudio else { return }
        guard let recognizer, recognizer.supportsOnDeviceRecognition, recognizer.isAvailable,
              SFSpeechRecognizer.authorizationStatus() == .authorized,
              AVAudioApplication.shared.recordPermission == .granted else {
            fail("On-device English speech is unavailable. Tap Try voice again, or use the buttons.")
            return
        }
        stopRecognition()
        let token = recognitionGeneration
        let lifecycle = generation
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.taskHint = .confirmation
        request.contextualStrings = VoiceCommand.contextualPhrases
        self.request = request
        utteranceGate = VoiceUtteranceGate()
        do {
            try activateRecognitionAudio()
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                fail("The microphone is not ready. Check your audio device, then enable voice again.")
                return
            }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }
            tapInstalled = true
            engine.prepare()
            try engine.start()
            isListening = true
            recoveryMessage = nil
            status = "Listening in English. Say ‘Next step’, ‘Previous step’, or ‘Show me again’."
            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                let transcript = result?.bestTranscription.formattedString
                let isFinal = result?.isFinal ?? false
                let failure = error.map(VoiceTaskFailure.init)
                Task { @MainActor [weak self] in
                    self?.receive(transcript: transcript, isFinal: isFinal, failure: failure,
                                  recognition: token, generation: lifecycle)
                }
            }
            // Turn over a healthy task before Speech's approximately one-minute
            // limit, including while the user is quietly folding. An error takes
            // a separate bounded recovery path; healthy turnover spends no retries.
            turnoverTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 55_000_000_000)
                guard !Task.isCancelled, let self,
                      token == self.recognitionGeneration, lifecycle == self.generation else { return }
                self.stopRecognition()
                self.scheduleRearm(generation: lifecycle)
            }
        } catch {
            fail("The microphone could not start. Check your audio device, then enable voice again.")
        }
    }

    private func receive(transcript: String?, isFinal: Bool, failure: VoiceTaskFailure?,
                         recognition: UInt64, generation lifecycle: UInt64) {
        guard recognition == recognitionGeneration, lifecycle == generation,
              isEnabled, isListening, !utteranceGate.isConsumed else { return }
        if let transcript {
            lastHeard = transcript
            if isFinal {
                stablePartialTask?.cancel()
                stablePartialTask = nil
                if let command = utteranceGate.consumeFinal(transcript) {
                    dispatch(command, generation: lifecycle)
                } else if let failure {
                    recoverSpeechTask(failure, generation: lifecycle)
                } else {
                    stopRecognition()
                    status = "Try ‘Next step’, ‘Previous step’, or ‘Show me again’."
                    scheduleRearm(generation: lifecycle)
                }
                return
            }
            if utteranceGate.update(transcript) {
                stablePartialTask?.cancel()
                stablePartialTask = nil
                if let candidate = utteranceGate.candidate {
                    stablePartialTask = Task { @MainActor [weak self] in
                        try? await Task.sleep(nanoseconds: 700_000_000)
                        guard !Task.isCancelled, let self,
                              recognition == self.recognitionGeneration, lifecycle == self.generation,
                              self.isEnabled, self.isListening,
                              let command = self.utteranceGate.consumeStable(candidate) else { return }
                        self.dispatch(command, generation: lifecycle)
                    }
                }
            }
        }
        if let failure {
            recoverSpeechTask(failure, generation: lifecycle)
        }
    }

    private func dispatch(_ command: VoiceCommand, generation lifecycle: UInt64) {
        recoveryPolicy.reset()
        recoveryMessage = nil
        stopRecognition()
        if command == .stopListening { stop() }
        onCommand?(command)
        // Routing may synchronously change a step, speak, or turn voice off.
        guard lifecycle == generation, isEnabled, !isSpeaking else { return }
        scheduleRearm(generation: lifecycle)
    }

    private func recoverSpeechTask(_ failure: VoiceTaskFailure, generation lifecycle: UInt64) {
        stopRecognition()
        let eligible = isEnabled && !isSpeaking && !isRequestingPermission && canUseAudio
            && recognizer?.supportsOnDeviceRecognition == true && recognizer?.isAvailable == true
            && SFSpeechRecognizer.authorizationStatus() == .authorized
            && AVAudioApplication.shared.recordPermission == .granted
        guard let delay = recoveryPolicy.nextDelayNanoseconds(for: failure, canRecover: eligible) else {
            fail("Voice input stopped. Tap Try voice again, or use the lesson buttons.")
            return
        }
        recoveryMessage = "Voice is reconnecting. You can keep folding."
        status = "Reconnecting voice (\(recoveryPolicy.attempts) of 3)."
        scheduleRearm(generation: lifecycle, delayNanoseconds: delay)
    }

    private func scheduleRearm(generation token: UInt64, delayNanoseconds: UInt64 = 250_000_000) {
        rearmTask?.cancel()
        rearmTask = Task { @MainActor [weak self] in
            // Allow the just-consumed phrase and UI context changes to settle.
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled, let self, token == self.generation,
                  self.isEnabled, !self.isSpeaking, !self.isRequestingPermission else { return }
            self.rearmTask = nil
            self.beginRecognition()
        }
    }

    private func stopRecognition() {
        recognitionGeneration &+= 1
        stablePartialTask?.cancel()
        stablePartialTask = nil
        turnoverTask?.cancel()
        turnoverTask = nil
        engine.stop()
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        request?.endAudio()
        request = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isListening = false
    }

    private func cancelNarration() {
        // Clear identity before didCancel can arrive for the previous utterance.
        activeUtterance = nil
        isSpeaking = false
        synthesizer.stopSpeaking(at: .immediate)
    }

    private func narrationEnded(_ utterance: AVSpeechUtterance) {
        guard activeUtterance === utterance else { return }
        activeUtterance = nil
        isSpeaking = false
        if isEnabled, canUseAudio {
            // Leave a short tail so the speaker is not heard as a fresh command.
            scheduleRearm(generation: generation, delayNanoseconds: 500_000_000)
        } else {
            deactivateAudio()
            status = "Voice commands are off."
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.narrationEnded(utterance) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.narrationEnded(utterance) }
    }

    private func stopForAudioChange(_ message: String) {
        guard isEnabled || isSpeaking || isRequestingPermission else { return }
        fail(message)
    }

    private func fail(_ message: String) {
        stop()
        recoveryMessage = message
        status = message
    }
}
