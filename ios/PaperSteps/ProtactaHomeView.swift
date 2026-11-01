import SwiftUI

private enum TutorialDestination: Identifiable {
    case origami, everyday(EverydayTutorialID), product, equipment(EquipmentTutorialID)
    var id: String {
        switch self {
        case .origami: return "origami"
        case .everyday(let id): return id.rawValue
        case .product: return "aeris"
        case .equipment(let id): return "equipment_\(id.rawValue)"
        }
    }
    var title: String {
        switch self {
        case .origami: return "Origami"
        case .everyday(let id):
            switch id {
            case .tShirt: return "T-shirt"
            case .towel: return "Towel"
            case .flatBedsheet: return "Bedsheet"
            case .squareKnot: return "Square knot"
            case .fourInHand: return "Necktie"
            }
        case .product: return "AERIS One"
        case .equipment(let id): return id == .gearmotor ? "Gearmotor" : "Jet engine"
        }
    }
    var accessibilityID: String {
        switch self {
        case .origami: return "hubOrigami"
        case .everyday(let id): return "hubCourse_\(id.rawValue)"
        case .product: return "hubProductManual"
        case .equipment(let id): return "hubEquipment_\(id.rawValue)"
        }
    }
}

private enum CatalogFilter: String, CaseIterable, Identifiable {
    case all = "All", everyday = "Everyday", spatial = "3D & AR"
    var id: Self { self }
}

enum TutorialColors {
    static let ink = Color(red: 0.13, green: 0.16, blue: 0.15)
    static let muted = Color(red: 0.45, green: 0.49, blue: 0.47)
    static let paper = Color(red: 0.97, green: 0.975, blue: 0.975)
    static let line = Color(red: 0.90, green: 0.915, blue: 0.905)
    static let orange = Color(red: 0.14, green: 0.29, blue: 0.25)
}

/// A visual library. The object is the entry point; explanations live in context.
struct ProtactaHomeView: View {
    @State private var destination: TutorialDestination?
    @State private var filter: CatalogFilter = .all
    @State private var progressRevision = 0
    @State private var showAbout = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private let progressStore = EverydayTutorialProgressStore.appDefault()
    private let choices: [TutorialDestination] = [
        .origami, .equipment(.gearmotor), .everyday(.towel), .equipment(.turbofan),
        .everyday(.tShirt), .product, .everyday(.squareKnot), .everyday(.fourInHand), .everyday(.flatBedsheet)
    ]
    private var visibleChoices: [TutorialDestination] {
        choices.filter { choice in
            switch (filter, choice) {
            case (.all, _), (.everyday, .everyday): return true
            case (.spatial, .origami), (.spatial, .product), (.spatial, .equipment), (.spatial, .everyday): return true
            default: return false
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        Text("Protacta").font(.system(size: 27, weight: .semibold)).tracking(-0.7)
                        Spacer()
                        Button { showAbout = true } label: {
                            Image(systemName: "info.circle").font(.system(size: 21)).frame(width: 44, height: 44)
                        }.accessibilityLabel("About Protacta").accessibilityIdentifier("hubAbout")
                    }
                    Picker("Tutorial category", selection: $filter) {
                        ForEach(CatalogFilter.allCases) { item in Text(item.rawValue).tag(item) }
                    }.pickerStyle(.segmented).accessibilityIdentifier("hubFilter")
                    if filter != .everyday {
                        featuredEngine
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: horizontalSizeClass == .regular ? 210 : 150, maximum: 300), spacing: 16)],
                              alignment: .leading, spacing: 26) {
                        ForEach(visibleChoices.filter { $0.id != "equipment_turbofan" }) { choice in tile(choice) }
                    }
                }.padding(22).frame(maxWidth: 900).frame(maxWidth: .infinity)
            }.background(TutorialColors.paper).foregroundStyle(TutorialColors.ink)
                .toolbar(.hidden, for: .navigationBar)
        }
        .accessibilityIdentifier("tutorialHub")
        .fullScreenCover(item: $destination, onDismiss: { progressRevision += 1 }) { selected in
            switch selected {
            case .origami: PaperStepsView(onExit: { destination = nil })
            case .everyday(let id): EverydayTutorialPlayer(courseID: id, onExit: { destination = nil })
            case .product: AerisManualModuleView(onExit: { destination = nil })
            case .equipment(let id): EquipmentTutorialEntry(id: id, onExit: { destination = nil })
            }
        }
        .sheet(isPresented: $showAbout) { about }
    }

    private var featuredEngine: some View {
        Button { destination = .equipment(.turbofan) } label: {
            GeometryReader { geometry in
                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: 28).fill(
                        RadialGradient(colors: [Color(red: 0.53, green: 0.55, blue: 0.55),
                                                Color(red: 0.19, green: 0.22, blue: 0.23),
                                                Color(red: 0.11, green: 0.13, blue: 0.14)],
                                       center: .topTrailing, startRadius: 0, endRadius: geometry.size.width * 1.1))
                    Ellipse().fill(.black.opacity(0.24)).frame(width: geometry.size.width * 0.64, height: 22)
                        .blur(radius: 13).position(x: geometry.size.width * 0.51, y: geometry.size.height * 0.72)
                    modelThumbnail("turbofan-preview", symbol: "engine.combustion")
                        .padding(.horizontal, 4).padding(.top, 6).padding(.bottom, 46)
                        .shadow(color: .black.opacity(0.18), radius: 20, y: 12)
                    HStack(alignment: .center) {
                        Text("Jet engine").font(.system(size: 27, weight: .medium)).tracking(-0.6)
                        Spacer()
                        Image(systemName: "arrow.right").font(.system(size: 19))
                            .frame(width: 44, height: 44).background(.white.opacity(0.18), in: Circle())
                    }.foregroundStyle(.white).padding(22)
                }.overlay { RoundedRectangle(cornerRadius: 28).strokeBorder(.white.opacity(0.16), lineWidth: 0.7) }
            }.aspectRatio(horizontalSizeClass == .regular ? 1.8 : 1.02, contentMode: .fit)
                .frame(maxHeight: 440)
        }.buttonStyle(.plain).accessibilityLabel("Jet engine").accessibilityIdentifier("hubEquipment_turbofan")
    }

    private func tile(_ choice: TutorialDestination) -> some View {
        let _ = progressRevision
        let saved: EverydayTutorialSession? = {
            if case .everyday(let id) = choice { return progressStore.load(courseID: id) }
            return nil
        }()
        return Button { destination = choice } label: {
            VStack(alignment: .leading, spacing: 12) {
                Color.clear.aspectRatio(0.95, contentMode: .fit)
                    .overlay { thumbnail(choice).padding(12) }
                    .background(LinearGradient(colors: [.white, Color(red: 0.90, green: 0.915, blue: 0.92)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 23))
                    .overlay { RoundedRectangle(cornerRadius: 23).strokeBorder(.white.opacity(0.8), lineWidth: 0.7) }
                    .overlay(alignment: .topTrailing) {
                        if saved?.completed == true {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(TutorialColors.orange)
                                .padding(12).accessibilityHidden(true)
                        }
                    }.clipped().allowsHitTesting(false).accessibilityHidden(true)
                Text(choice.title).font(.body.weight(.medium)).lineLimit(2)
                    .padding(.horizontal, 2)
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(choice.title)
            .accessibilityValue(saved?.completed == true ? "Completed by your confirmation" : "")
            .accessibilityIdentifier(choice.accessibilityID)
    }

    @ViewBuilder
    private func thumbnail(_ choice: TutorialDestination) -> some View {
        switch choice {
        case .everyday(let id):
            EverydayTutorialVisual(courseID: id.rawValue, stepIndex: 0, progress: 0, showsCaption: false, showsAnnotations: false, showsPartLabels: false)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .origami:
            modelThumbnail("dart-preview", symbol: "paperplane")
                .shadow(color: .black.opacity(0.15), radius: 9, y: 12)
        case .equipment(let id):
            modelThumbnail(id == .gearmotor ? "gearmotor-preview" : "turbofan-preview", symbol: id.symbol)
        case .product:
            modelThumbnail("aeris-preview", symbol: "air.purifier")
        }
    }

    @ViewBuilder
    private func modelThumbnail(_ name: String, symbol: String) -> some View {
        if let image = UIImage(named: name) {
            Image(uiImage: image).resizable().scaledToFit()
        } else {
            Image(systemName: symbol).font(.system(size: 70, weight: .ultraLight)).foregroundStyle(TutorialColors.muted)
        }
    }

    private var about: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Choose a tutorial, watch the movement, then try it yourself.").font(.title3)
                    Text("Everyday skill confirmations save on this device. Camera checks are available in the Classic Dart practice; everyday skills use continuous 3D movement and optional tabletop AR.")
                        .accessibilityIdentifier("hubCapabilityScope")
                    Text("Classic Dart's paper alignment and outline checks are experimental. Everyday AR places a virtual teaching reference beside your object; it does not inspect or align to your clothes or knots. Equipment AR places a virtual teaching model; it does not recognise or register to real equipment.")
                    Text("AERIS One is an original concept product. These walkthroughs are demonstrations, not manufacturer-approved maintenance instructions. Equipment and everyday courses still need independent learning review.")
                    Text("English narration and supported voice commands run on device. Cloud AI chat is not enabled. Normal use does not save or upload camera photos; progress stays on this device.")
                }.font(.body).padding(24)
            }.background(TutorialColors.paper).navigationTitle("About Protacta")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showAbout = false } } }
        }
    }
}
