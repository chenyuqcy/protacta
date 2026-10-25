import Foundation

/// Complete candidate sequence, including the authored head, trunk and standing finish.
/// One source square; final body opening uses a separately bounded forming approximation.
enum ElephantAssemblyGeometry {
    static let width = ElephantGeometry.width
    static let isComplete = true
    static let prefixLastStep = ElephantShoulderStudy.sourceCheckpointStep
    static let rearLastStep = prefixLastStep + ElephantRearSquashStudy.lastStep
    static let shoulderLastStep = rearLastStep + ElephantShoulderStudy.lastStep
    static let headLastStep = shoulderLastStep + ElephantAuthoredHeadStudy.stepCount - 1
    static let trunkLastStep = headLastStep + ElephantTrunkFinishStudy.lastStep
    static let finalFormingStep = trunkLastStep + 1
    static let lastStep = finalFormingStep
    static let stepCount = lastStep + 1

    static func frame(step requested: Int, progress: Float) -> PaperFrame {
        let step = min(lastStep, max(0, requested))
        if step <= prefixLastStep {
            return ElephantGeometry.frame(step: step, progress: progress)
        }
        if step <= rearLastStep {
            return ElephantRearSquashStudy.frame(step: step-prefixLastStep, progress: progress)
        }
        if step <= shoulderLastStep {
            return ElephantShoulderStudy.frame(step: step-rearLastStep, progress: progress, withRearFeet: true)
        }
        let shoulder = ElephantShoulderStudy.frame(step: ElephantShoulderStudy.lastStep, progress: 1, withRearFeet: true)
        if step <= headLastStep {
            return ElephantAuthoredHeadStudy.frame(step: step-shoulderLastStep, progress: progress, input: shoulder)
        }
        let head = ElephantAuthoredHeadStudy.frame(step: ElephantAuthoredHeadStudy.stepCount-1, progress: 1, input: shoulder)
        if step <= trunkLastStep {
            return ElephantTrunkFinishStudy.frame(step: step-headLastStep, progress: progress, input: head)
        }
        let trunk = ElephantTrunkFinishStudy.frame(step: ElephantTrunkFinishStudy.lastStep, progress: 1, input: head)
        return ElephantStandingStudy.frame(progress: progress, input: trunk)
    }
}
