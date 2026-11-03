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
    case all = "All", origami = "Origami", everyday = "Everyday", equipment = "Equipment"
    var id: Self { self }
}

private enum CatalogSection: String, Identifiable {
    case clothes, knots, equipment
    var id: Self { self }
    var title: String {
        switch self {
        case .clothes: return "Clothes & linens"
        case .knots: return "Knots & ties"
        case .equipment: return "Objects & equipment"
        }
    }
    var tutorials: [TutorialDestination] {
        switch self {
        case .clothes: return [.everyday(.towel), .everyday(.tShirt), .everyday(.flatBedsheet)]
        case .knots: return [.everyday(.squareKnot), .everyday(.fourInHand)]
        case .equipment: return [.equipment(.gearmotor), .equipment(.turbofan), .product]
        }
    }
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
    @State private var showIntroduction = false
    @State private var replayIntroductionAfterAbout = false
    @State private var showPhoneSetup = false
    @State private var showTutorialSupport = false
    @State private var openSupportAfterAbout = false
    @State private var replayIntroductionAfterSupport = false
    @State private var consideredIntroduction = false
    private let introductionPreferences = FirstRunIntroductionPreferences.appDefault()
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private let progressStore = EverydayTutorialProgressStore.appDefault()
    private var visibleSections: [CatalogSection] {
        switch filter {
        case .all: return [.clothes, .knots, .equipment]
        case .origami: return []
        case .everyday: return [.clothes, .knots]
        case .equipment: return [.equipment]
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        HStack(spacing: 10) {
                            Image("ProtactaMark").resizable().scaledToFit()
                                .frame(width: 44, height: 44).accessibilityHidden(true)
                            Text("Protacta").font(.system(size: 27, weight: .semibold)).tracking(-0.7)
                        }
                        Spacer()
                        Button { showAbout = true } label: {
                            Image(systemName: "info.circle").font(.system(size: 21)).frame(width: 44, height: 44)
                        }.accessibilityLabel("About Protacta").accessibilityIdentifier("hubAbout")
                    }
                    Picker("Tutorial category", selection: $filter) {
                        ForEach(CatalogFilter.allCases) { item in Text(item.rawValue).tag(item) }
                    }.pickerStyle(.segmented).accessibilityIdentifier("hubFilter")
                    phoneSetupEntry
                    if filter == .all || filter == .origami {
                        featuredOrigami
                    }
                    ForEach(visibleSections) { section in
                        VStack(alignment: .leading, spacing: 16) {
                            Text(section.title).font(.title3.weight(.semibold))
                                .accessibilityIdentifier("catalogSection_\(section.rawValue)")
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: horizontalSizeClass == .regular ? 210 : 150, maximum: 300), spacing: 16)],
                                      alignment: .leading, spacing: 26) {
                                ForEach(section.tutorials) { choice in tile(choice) }
                            }
                        }
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
        .sheet(isPresented: $showAbout, onDismiss: {
            if replayIntroductionAfterAbout {
                replayIntroductionAfterAbout = false
                showIntroduction = true
            } else if openSupportAfterAbout {
                openSupportAfterAbout = false
                showTutorialSupport = true
            }
        }) { about }
        .sheet(isPresented: $showPhoneSetup) { PhoneSetupView() }
        .sheet(isPresented: $showTutorialSupport, onDismiss: {
            if replayIntroductionAfterSupport {
                replayIntroductionAfterSupport = false
                showIntroduction = true
            }
        }) {
            TutorialSupportView {
                replayIntroductionAfterSupport = true
                showTutorialSupport = false
            }
        }
        .sheet(isPresented: $showIntroduction) {
            FirstRunIntroductionView {
                introductionPreferences.complete()
                showIntroduction = false
            }
        }
        .onAppear {
            guard !consideredIntroduction else { return }
            consideredIntroduction = true
            showIntroduction = introductionPreferences.shouldPresent
        }
    }

    private var phoneSetupEntry: some View {
        Button { showPhoneSetup = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "iphone").font(.system(size: 19))
                Text("Set up your phone").font(.subheadline.weight(.medium))
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    .foregroundStyle(TutorialColors.muted)
            }.padding(.horizontal, 16).frame(minHeight: 48)
                .background(.white, in: RoundedRectangle(cornerRadius: 16))
                .contentShape(RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain).accessibilityIdentifier("hubPhoneSetup")
            .accessibilityHint("Learn where to place your phone and paper.")
    }

    private var featuredOrigami: some View {
        Button { destination = .origami } label: {
            GeometryReader { geometry in
                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: 28).fill(
                        RadialGradient(colors: [Color(red: 0.65, green: 0.72, blue: 0.68),
                                                Color(red: 0.26, green: 0.34, blue: 0.30),
                                                Color(red: 0.12, green: 0.17, blue: 0.15)],
                                       center: .topTrailing, startRadius: 0, endRadius: geometry.size.width * 1.1))
                    Ellipse().fill(.black.opacity(0.24)).frame(width: geometry.size.width * 0.64, height: 22)
                        .blur(radius: 13).position(x: geometry.size.width * 0.51, y: geometry.size.height * 0.72)
                    modelThumbnail("dart-preview", symbol: "paperplane")
                        .scaleEffect(1.4)
                        .padding(.horizontal, 4).padding(.top, 6).padding(.bottom, 46)
                        .shadow(color: .black.opacity(0.18), radius: 20, y: 12)
                    HStack(alignment: .center) {
                        Text("Origami").font(.system(size: 27, weight: .medium)).tracking(-0.6)
                        Spacer()
                        Image(systemName: "arrow.right").font(.system(size: 19))
                            .frame(width: 44, height: 44).background(.white.opacity(0.18), in: Circle())
                    }.foregroundStyle(.white).padding(22)
                }.clipShape(RoundedRectangle(cornerRadius: 28))
                    .overlay { RoundedRectangle(cornerRadius: 28).strokeBorder(.white.opacity(0.16), lineWidth: 0.7) }
            }.aspectRatio(horizontalSizeClass == .regular ? 1.8 : 1.02, contentMode: .fit)
                .frame(maxHeight: 440)
                // The enlarged transparent image must not intercept taps on
                // the category picker above the card. Clipping is visual only.
                .contentShape(RoundedRectangle(cornerRadius: 28))
        }.buttonStyle(.plain).accessibilityLabel("Origami").accessibilityIdentifier("hubOrigami")
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
                    Button {
                        replayIntroductionAfterAbout = true
                        showAbout = false
                    } label: {
                        Label("Quick tour", systemImage: "arrow.up.forward.app")
                            .frame(minHeight: 44)
                    }.accessibilityIdentifier("replayIntroduction")
                    Button {
                        openSupportAfterAbout = true
                        showAbout = false
                    } label: {
                        Label("Help & setup", systemImage: "questionmark.circle")
                            .frame(minHeight: 44)
                    }.accessibilityIdentifier("openTutorialSupport")
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
