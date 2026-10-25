import Foundation

/// Speech-task diagnostics are kept in memory. No private Speech error numbers
/// are assumed to mean that retrying is safe: the caller checks permissions,
/// on-device availability and foreground state before every bounded attempt.
struct VoiceTaskFailure: Equatable, Sendable {
    let domain: String
    let code: Int

    init(_ error: Error) {
        let error = error as NSError
        domain = error.domain
        code = error.code
    }
}

struct VoiceRecoveryPolicy {
    private(set) var attempts = 0
    private(set) var lastFailure: VoiceTaskFailure?
    private static let delays: [UInt64] = [750_000_000, 1_500_000_000, 3_000_000_000]

    mutating func nextDelayNanoseconds(for failure: VoiceTaskFailure, canRecover: Bool) -> UInt64? {
        lastFailure = failure
        guard canRecover, attempts < Self.delays.count else { return nil }
        let delay = Self.delays[attempts]
        attempts += 1
        return delay
    }

    /// Only an explicit user activation or an accepted command earns a fresh
    /// retry budget. Starting a task successfully does not prove it is healthy.
    mutating func reset() {
        attempts = 0
        lastFailure = nil
    }
}
