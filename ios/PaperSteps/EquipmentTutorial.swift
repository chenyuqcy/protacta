import SwiftUI

enum EquipmentTutorialID: String, CaseIterable, Identifiable {
    case gearmotor, turbofan
    var id: String { rawValue }
    var title: String { self == .gearmotor ? "Explore a gearmotor" : "Inside a turbofan" }
    var subtitle: String { self == .gearmotor ? "5 virtual actions · Exterior parts" : "6 virtual actions · Structure preview" }
    var symbol: String { self == .gearmotor ? "gearshape.2" : "airplane.circle" }

    func load() throws -> AssemblyTutorial {
        guard let url = Bundle.main.url(forResource: "equipment-\(rawValue)", withExtension: "json") else { throw CocoaError(.fileNoSuchFile) }
        return try JSONDecoder().decode(AssemblyTutorial.self, from: Data(contentsOf: url))
    }
}

struct EquipmentTutorialEntry: View {
    let id: EquipmentTutorialID
    let onExit: () -> Void
    @State private var tutorial: AssemblyTutorial?
    @State private var failure: String?
    var body: some View {
        Group {
            if let tutorial { AssemblyTutorialPlayer(tutorial: tutorial, onExit: onExit) }
            else {
                VStack(spacing: 20) {
                    if let failure { Text(failure).font(.callout).accessibilityIdentifier("equipmentLoadFailure") }
                    else { ProgressView("Opening walkthrough…") }
                    Button("All tutorials", action: onExit)
                }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity).background(TutorialColors.paper)
            }
        }.task {
            guard tutorial == nil else { return }
            do { tutorial = try id.load() }
            catch { failure = "This walkthrough could not be opened. Return to the library and try again." }
        }
    }
}
