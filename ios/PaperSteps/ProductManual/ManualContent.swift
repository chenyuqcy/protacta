import Foundation

enum ProductPose: String, CaseIterable {
    case assembled, release, cover, filter, insert, closedRear, exploded, controls
    var title: String {
        switch self {
        case .assembled: "Assembled"
        case .release, .closedRear: "Rear view"
        case .cover: "Cover open"
        case .filter: "Filter out"
        case .insert: "Filter in"
        case .exploded: "Exploded"
        case .controls: "Controls"
        }
    }
}
struct ManualStep: Identifiable {
    let id: Int
    let title: String
    let detail: String
    let pose: ProductPose
    let focus: String
    let callout: String
    var requiresPress: Bool { pose == .release }
}
enum ManualTask: String, CaseIterable, Identifiable {
    case filter = "Replace the filter", setup = "First-time setup", clean = "Routine cleaning"
    var id: String { rawValue }
    var steps: [ManualStep] {
        switch self {
        case .filter: [
            .init(id: 0, title: "Power off and unplug", detail: "Switch off the purifier using the top power control. Unplug it before opening the housing. Confirm when your device is disconnected.", pose: .controls, focus: "Power_symbol_arc", callout: "POWER OFF FIRST"),
            .init(id: 1, title: "Press the release tab", detail: "Find the small tab above the rear handle. Tap the red tab on this model to press it. Once released, choose Next Step to open the cover.", pose: .release, focus: "Cover_Release_Button", callout: "TAP THE RED TAB"),
            .init(id: 2, title: "Open the rear cover", detail: "Hold the dark handle and pull the cover straight outward, as the arrow shows. Watch the opening action, then place the cover to one side.", pose: .cover, focus: "Cover_finger_grip", callout: "PULL STRAIGHT OUT"),
            .init(id: 3, title: "Slide the filter out", detail: "Take hold of the pull loop. Slide the cartridge out through the rear opening. The animation shows the direction of movement.", pose: .filter, focus: "Filter_pull_loop", callout: "PULL THE LOOP"),
            .init(id: 4, title: "Fit the replacement filter", detail: "Keep the TOP mark facing upward. Slide the cartridge into its seat. For an actual product, first follow its instructions for removing any protective packaging.", pose: .insert, focus: "Filter_TOP_mark", callout: "TOP FACES UP"),
            .init(id: 5, title: "Close the rear cover", detail: "Align the rear panel with the opening and move it inward until it sits flush. The animation shows the cover returning to its original position.", pose: .closedRear, focus: "Cover_Release_Button", callout: "ALIGN AND CLOSE"),
            .init(id: 6, title: "Locate the reset control", detail: "After reassembly, find FILTER on the top panel. This concept marks the reset location; a real product's approved manual must provide its reset sequence and timing.", pose: .controls, focus: "Filter_reset_label", callout: "FILTER RESET")
        ]
        case .setup: [
            .init(id: 0, title: "Meet your purifier", detail: "Rotate the model to find the top controls, air inlets and rear service panel. Keep the real device unplugged while checking installation.", pose: .assembled, focus: "Main_Housing", callout: "AIR INLETS"),
            .init(id: 1, title: "Release the rear panel", detail: "Tap the red release tab above the handle. Next Step will demonstrate the panel opening.", pose: .release, focus: "Cover_Release_Button", callout: "TAP THE RED TAB"),
            .init(id: 2, title: "Check the filter compartment", detail: "Look inside the opening. Use the actual model's instructions to check packaging and filter orientation before use.", pose: .cover, focus: "Filter_pull_loop", callout: "CHECK THE FILTER"),
            .init(id: 3, title: "Close the panel", detail: "Return the cover to the opening and align it with the housing.", pose: .closedRear, focus: "Cover_finger_grip", callout: "CLOSE THE COVER"),
            .init(id: 4, title: "Find the power control", detail: "The arrow points to the power control. This app demonstrates instructions; it does not operate your physical appliance.", pose: .controls, focus: "Power_symbol_arc", callout: "POWER CONTROL")
        ]
        case .clean: [
            .init(id: 0, title: "Power off and unplug", detail: "Turn off and disconnect the purifier. Use the actual model's manual for any waiting period before maintenance.", pose: .controls, focus: "Power_symbol_arc", callout: "POWER OFF FIRST"),
            .init(id: 1, title: "Locate the air inlets", detail: "The highlighted slots are the intake area. Cleaning tools and methods must follow the actual product's instructions.", pose: .assembled, focus: "Main_Housing", callout: "INTAKE AREA"),
            .init(id: 2, title: "Release the service panel", detail: "Tap the red tab, then choose Next Step to reveal the filter compartment.", pose: .release, focus: "Cover_Release_Button", callout: "TAP THE RED TAB"),
            .init(id: 3, title: "Inspect the filter area", detail: "Check the cartridge and seals. This demonstration does not mean the filter is washable; cleaning or replacement requirements depend on the real model.", pose: .cover, focus: "Filter_pull_loop", callout: "INSPECT THE FILTER"),
            .init(id: 4, title: "Close the panel", detail: "Refit the rear cover before reconnecting the device.", pose: .closedRear, focus: "Cover_finger_grip", callout: "CLOSE THE COVER")
        ]
        }
    }
}
struct ManualProgress {
    var task: ManualTask = .filter
    var index = 0
    var highestUnlocked = 0
    var completed = false
    var actionConfirmed = false
    var current: ManualStep { task.steps[index] }
    var canAdvance: Bool { !current.requiresPress || actionConfirmed }
    mutating func select(_ task: ManualTask) { self.task = task; index = 0; highestUnlocked = 0; completed = false; actionConfirmed = false }
    mutating func confirmAction() { actionConfirmed = true }
    mutating func next() {
        if completed { select(task) }
        else if canAdvance {
            if index + 1 < task.steps.count { index += 1; highestUnlocked = max(highestUnlocked, index); actionConfirmed = false }
            else { completed = true }
        }
    }
    mutating func go(to index: Int) {
        guard task.steps.indices.contains(index), index <= highestUnlocked else { return }
        self.index = index; completed = false; actionConfirmed = false
    }
}
