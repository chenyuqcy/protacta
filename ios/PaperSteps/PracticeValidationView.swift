import SwiftUI

/// Developer-requested local evidence collection. The entry is hidden unless
/// the Debug process was launched with --practice-validation.
struct PracticeValidationControls: View {
    @ObservedObject var controller: LessonController

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("LOCAL TEST MODE").font(.system(size: 10, weight: .bold))
                Text(controller.validationAvailabilityMessage).font(.system(size: 12))
                    .accessibilityIdentifier("validationAvailability")
                Button("Save local test sample") { controller.requestValidationSample() }
                    .buttonStyle(.bordered)
                    .disabled(!controller.canSaveValidationSample)
                    .accessibilityIdentifier("saveValidationSample")
                Text(controller.validationStatus).font(.system(size: 11)).foregroundStyle(.secondary)
                    .accessibilityIdentifier("validationCaptureStatus")
                if let directory = controller.lastValidationDirectory {
                    Text("Saved record: \(directory.lastPathComponent)").font(.system(size: 10, design: .monospaced))
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct PracticeValidationSettingsView: View {
    @ObservedObject var controller: LessonController

    var body: some View {
        Form {
            Section("Test identity") {
                Text("Use anonymous IDs. Keep each physical paper and attempt identifiable across exports; the evaluator prevents them from crossing development and evaluation splits.")
                    .font(.footnote)
                TextField("Operator ID, e.g. P01", text: $controller.validationIdentity.operatorID)
                    .accessibilityIdentifier("validationOperatorID")
                TextField("Physical sheet ID, e.g. sheet-001", text: $controller.validationIdentity.sheetID)
                    .accessibilityIdentifier("validationSheetID")
                TextField("Attempt ID, e.g. P01-attempt-001", text: $controller.validationIdentity.attemptID)
                    .accessibilityIdentifier("validationAttemptID")
                Picker("Dataset split", selection: $controller.validationIdentity.split) {
                    Text("Development").tag(PracticeValidationSample.Split.development)
                    Text("Evaluation").tag(PracticeValidationSample.Split.evaluation)
                }
                Text("IDs use letters, numbers, dots, underscores or hyphens, up to 80 characters.")
                    .font(.caption).foregroundStyle(.secondary)
            }.disabled(controller.validationBusy)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            Section("Capture session") {
                Text(controller.validationIdentity.sessionID).font(.caption.monospaced())
                Button("Begin a new capture session") {
                    controller.validationIdentity.sessionID = UUID().uuidString.lowercased()
                }.disabled(controller.validationBusy)
                Text("Return to the camera, frame your paper and press Save local test sample. That explicit button saves one full camera image and metadata on the device. It does not assign a human label or approve the fold.")
                    .font(.footnote)
            }
            Section("Availability") {
                Text(controller.validationAvailabilityMessage).accessibilityIdentifier("validationSetupAvailability")
                Text("Records are stored in the app's Documents/ProtactaValidation folder. Copy the folder through Xcode or devicectl for independent annotation. No export is sent automatically.")
                    .font(.footnote)
            }
        }.navigationTitle("Local validation")
            .navigationBarTitleDisplayMode(.inline)
    }
}
