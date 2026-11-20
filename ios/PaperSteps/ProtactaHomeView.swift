import SwiftUI

private enum TutorialDestination: Identifiable {
    case classicDart, origami, origamiLesson(OrigamiLesson), resumeOrigami(OrigamiLesson), everyday(EverydayTutorialID), product, equipment(EquipmentTutorialID)
    var id: String {
        switch self {
        case .classicDart: return "classicDart"
        case .origami: return "origami"
        case .origamiLesson(let lesson): return "origami_\(lesson.rawValue)"
        case .resumeOrigami(let lesson): return "resume_origami_\(lesson.rawValue)"
        case .everyday(let id): return id.rawValue
        case .product: return "aeris"
        case .equipment(let id): return "equipment_\(id.rawValue)"
        }
    }
    var title: String {
        switch self {
        case .classicDart: return OrigamiLesson.dart.title
        case .origami: return "Origami"
        case .origamiLesson(let lesson), .resumeOrigami(let lesson): return lesson.title
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
        case .classicDart: return "hubClassicDart"
        case .origami: return "hubOrigami"
        case .origamiLesson(let lesson): return "hubOrigamiLesson_\(lesson.rawValue)"
        case .resumeOrigami(let lesson): return "hubResume_origami_\(lesson.rawValue)"
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
        case .clothes: return "Everyday · Clothes & linens"
        case .knots: return "Everyday · Knots & ties"
        case .equipment: return "Equipment · Objects & equipment"
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
    static let muted = Color(red: 0.38, green: 0.43, blue: 0.41)
    static let paper = Color(red: 0.969, green: 0.945, blue: 0.890)
    static let line = Color(red: 0.90, green: 0.915, blue: 0.905)
    static let orange = Color(red: 0.14, green: 0.29, blue: 0.25)
}

enum Brand {
    static let forest = Color(red: 0.145, green: 0.294, blue: 0.235)
    static let forestDeep = Color(red: 0.102, green: 0.223, blue: 0.173)
    static let emerald = Color(red: 0.169, green: 0.647, blue: 0.416)
    static let mint = Color(red: 0.396, green: 0.776, blue: 0.576)
    static let orange = Color(red: 0.910, green: 0.561, blue: 0.231)
    static let cream = Color(red: 0.969, green: 0.945, blue: 0.890)
    static let ink = Color(red: 0.102, green: 0.145, blue: 0.122)
}

enum HomeCard {
    static let radius: CGFloat = 23
    static let stroke = Color.white.opacity(0.8)
    static let origamiPlate = LinearGradient(colors: [Color(red: 0.30, green: 0.41, blue: 0.35),
                                                      Color(red: 0.12, green: 0.18, blue: 0.15)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing)
    static let everydayPlate = LinearGradient(colors: [Color(red: 0.87, green: 0.93, blue: 0.94),
                                                       Color(red: 0.74, green: 0.85, blue: 0.88)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing)
    static let equipmentPlate = LinearGradient(colors: [Color(red: 0.91, green: 0.93, blue: 0.95),
                                                        Color(red: 0.78, green: 0.82, blue: 0.88)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// A visual library. The object is the entry point; explanations live in context.
struct ProtactaHomeView: View {
    @State private var destination: TutorialDestination?
    @State private var filter: CatalogFilter = .all
    @State private var progressRevision = 0
    @State private var origamiProgressStore: LearningProgressStore?
    @State private var showAbout = false
    @State private var showIntroduction = false
    @State private var replayIntroductionAfterAbout = false
    @State private var showPhoneSetup = false
    @State private var showPricing = false
    #if FOLIAFOLD_UPDATE
    @StateObject private var homePurchases = PurchaseStore()
    @State private var selectedPurchasePlan: PurchasePlan = .annual
    #endif
    @State private var showTutorialSupport = false
    @State private var openSupportAfterAbout = false
    @State private var replayIntroductionAfterSupport = false
    @State private var consideredIntroduction = false
    private let introductionPreferences = FirstRunIntroductionPreferences.appDefault()
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image("ProTactaWordmark").resizable().scaledToFit()
                                .frame(height: 25)
                                .accessibilityLabel("ProTacta")
                            Spacer()
                            HStack(spacing: 6) {
                                Button { showPricing = true } label: {
                                    Text("Plans").font(.system(size: 14, weight: .semibold))
                                        .padding(.horizontal, 15).frame(height: 36)
                                        .background(Brand.orange, in: Capsule()).foregroundStyle(.white)
                                }.accessibilityLabel("Plans and pricing").accessibilityIdentifier("hubPricing")
                                Button { showAbout = true } label: {
                                    Image(systemName: "info.circle").font(.system(size: 21)).frame(width: 44, height: 44)
                                }.accessibilityLabel("About ProTacta").accessibilityIdentifier("hubAbout")
                            }
                        }
                        Text("Watch it in 3D, then fold it yourself - hands-free.")
                            .font(.subheadline).foregroundStyle(TutorialColors.muted)
                            .accessibilityIdentifier("hubTagline")
                    }
                    Picker("Tutorial category", selection: $filter) {
                        ForEach(CatalogFilter.allCases) { item in Text(item.rawValue).tag(item) }
                    }.pickerStyle(.segmented).accessibilityIdentifier("hubFilter")
                    let resumes = resumeLessons()
                    if filter != .equipment && !resumes.isEmpty {
                        VStack(spacing: 10) {
                            ForEach(resumes) { resumeCard($0) }
                        }
                    }
                    if filter == .all {
                        VStack(alignment: .leading, spacing: 14) {
                            featuredOrigami
                            classicDartEntry
                        }
                    }
                    if filter == .origami { origamiGrid }
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
                    phoneSetupEntry
                }.padding(22).frame(maxWidth: 900).frame(maxWidth: .infinity)
            }.background(Brand.cream).foregroundStyle(Brand.ink)
                .toolbar(.hidden, for: .navigationBar)
        }
        .accessibilityIdentifier("tutorialHub")
        .fullScreenCover(item: $destination, onDismiss: { progressRevision += 1 }) { selected in
            switch selected {
            case .classicDart:
                PaperStepsView(onExit: { destination = nil }, progressStore: origamiProgressStore, opensClassicDart: true)
            case .origami:
                PaperStepsView(onExit: { destination = nil }, progressStore: origamiProgressStore)
            case .resumeOrigami(let lesson):
                PaperStepsView(onExit: { destination = nil }, progressStore: origamiProgressStore, resumeLesson: lesson)
            case .origamiLesson(let lesson):
                PaperStepsView(onExit: { destination = nil }, progressStore: origamiProgressStore, openLesson: lesson)
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
        .sheet(isPresented: $showPricing) {
            #if FOLIAFOLD_UPDATE
            LibraryPurchaseSheet(purchases: homePurchases, selectedPurchasePlan: $selectedPurchasePlan) {
                showPricing = false
            }
            .task { await homePurchases.refresh() }
            #else
            PlansView()
            #endif
        }
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
            origamiProgressStore = LessonController.makeProgressStore()
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
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("hubPhoneSetup")
            .accessibilityHint("Learn where to place your phone and paper.")
    }

    private var classicDartEntry: some View {
        let _ = progressRevision
        let saved = origamiProgressStore?.record(for: .dart)
        let title: String
        if saved?.completed == true { title = "View finished fold" }
        else if let saved, saved.stepIndex > 0 { title = "Continue · Step \(saved.stepIndex)" }
        else if saved != nil { title = "Continue folding" }
        else { title = "Try the first fold" }

        return Button { destination = .classicDart } label: {
            HStack(spacing: 14) {
                Image(systemName: "play.fill").font(.system(size: 15, weight: .semibold))
                    .frame(width: 40, height: 40).background(.white, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(OrigamiLesson.dart.title).font(.caption).foregroundStyle(TutorialColors.muted)
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.right").font(.subheadline.weight(.semibold))
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(Brand.forest)
                .background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain)
            .accessibilityLabel("\(OrigamiLesson.dart.title), \(title)")
            .accessibilityHint("A4 paper · 10 folds")
            .accessibilityIdentifier(TutorialDestination.classicDart.accessibilityID)
    }

    private var featuredOrigami: some View {
        Button { filter = .origami } label: {
            VStack(alignment: .leading, spacing: 12) {
                Color.clear.aspectRatio(horizontalSizeClass == .regular ? 2.3 : 1.55, contentMode: .fit)
                    .overlay {
                        modelThumbnail("dart-preview", symbol: "paperplane")
                            .padding(.horizontal, 30).padding(.vertical, 24)
                            .shadow(color: .black.opacity(0.28), radius: 20, y: 14)
                    }
                    .frame(maxWidth: .infinity)
                    .background(HomeCard.origamiPlate, in: RoundedRectangle(cornerRadius: HomeCard.radius))
                    .overlay { RoundedRectangle(cornerRadius: HomeCard.radius).strokeBorder(.white.opacity(0.16), lineWidth: 0.7) }
                    .overlay(alignment: .bottomLeading) {
                        Text("\(OrigamiLesson.allCases.count) paper models")
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.85))
                            .padding(18)
                    }
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: "square.grid.2x2.fill").font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(TutorialColors.ink).frame(width: 40, height: 40)
                            .background(.white.opacity(0.92), in: Circle()).padding(14)
                    }
                    .clipped()
                Text("Origami").font(.body.weight(.medium)).padding(.horizontal, 2)
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("Origami").accessibilityHint("Browse all paper models")
            .accessibilityIdentifier("hubOrigami")
    }

    private var orderedOrigami: [OrigamiLesson] {
        OrigamiLesson.allCases.filter(\.isFree) + OrigamiLesson.allCases.filter { !$0.isFree }
    }

    private var origamiGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: horizontalSizeClass == .regular ? 210 : 150, maximum: 300), spacing: 16)],
                  alignment: .leading, spacing: 26) {
            ForEach(orderedOrigami) { lesson in origamiCard(lesson) }
        }
    }

    private func origamiCard(_ lesson: OrigamiLesson) -> some View {
        let _ = progressRevision
        let record = origamiProgressStore?.record(for: lesson)
        return Button { destination = .origamiLesson(lesson) } label: {
            VStack(alignment: .leading, spacing: 12) {
                Color.clear.aspectRatio(0.95, contentMode: .fit)
                    .overlay {
                        Image(systemName: lesson.symbol).font(.system(size: 44, weight: .light))
                            .foregroundStyle(.white)
                    }
                    .background(HomeCard.origamiPlate, in: RoundedRectangle(cornerRadius: HomeCard.radius))
                    .overlay { RoundedRectangle(cornerRadius: HomeCard.radius).strokeBorder(.white.opacity(0.14), lineWidth: 0.7) }
                    .overlay(alignment: .topTrailing) {
                        if record?.completed == true {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.white).padding(12)
                        } else if !lesson.isFree {
                            Image(systemName: "lock.fill").font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.85)).padding(12)
                        }
                    }.clipped().accessibilityHidden(true)
                Text(lesson.title).font(.body.weight(.medium)).lineLimit(2).padding(.horizontal, 2)
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(lesson.title)
            .accessibilityValue(record?.completed == true ? "Completed" : lesson.isFree ? "Free" : "Full library")
            .accessibilityIdentifier("hubOrigamiLesson_\(lesson.rawValue)")
    }

    private func plate(for choice: TutorialDestination) -> LinearGradient {
        switch choice {
        case .classicDart, .origami, .origamiLesson, .resumeOrigami: return HomeCard.origamiPlate
        case .everyday: return HomeCard.everydayPlate
        case .equipment, .product: return HomeCard.equipmentPlate
        }
    }

    private struct ResumeTarget: Identifiable {
        enum Kind { case origami(OrigamiLesson), everyday(EverydayTutorialID) }
        let kind: Kind
        let title: String
        let detail: String
        let updatedAt: Date
        var id: String {
            switch kind {
            case .origami(let lesson): return "origami_\(lesson.rawValue)"
            case .everyday(let course): return "everyday_\(course.rawValue)"
            }
        }
    }

    private func resumeLessons() -> [ResumeTarget] {
        let _ = progressRevision
        var targets: [ResumeTarget] = []
        for point in origamiProgressStore?.inProgress(limit: 3) ?? [] where filter == .all || filter == .origami {
            targets.append(ResumeTarget(kind: .origami(point.lesson), title: point.lesson.title,
                                        detail: point.stepIndex == 0 ? "Not started yet" : "Step \(point.stepIndex) of \(point.lesson.lastStep)",
                                        updatedAt: point.updatedAt))
        }
        for point in progressStore.inProgress(limit: 3) where filter == .all || filter == .everyday {
            let total = EverydayTutorialCourse.course(point.courseID).actions.count
            targets.append(ResumeTarget(kind: .everyday(point.courseID), title: TutorialDestination.everyday(point.courseID).title,
                                        detail: "Step \(point.currentAction) of \(total)", updatedAt: point.updatedAt))
        }
        return Array(targets.sorted { $0.updatedAt > $1.updatedAt }.prefix(3))
    }

    private func startResume(_ target: ResumeTarget) {
        switch target.kind {
        case .origami(let lesson): destination = .resumeOrigami(lesson)
        case .everyday(let id): destination = .everyday(id)
        }
    }

    private func resumeCard(_ target: ResumeTarget) -> some View {
        Button { startResume(target) } label: {
            HStack(spacing: 14) {
                Image(systemName: "play.fill").font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Brand.forest)
                    .frame(width: 44, height: 44).background(.white, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text("RESUME").font(.system(size: 11, weight: .bold)).tracking(1.4).opacity(0.85)
                    Text(target.title).font(.headline)
                    Text(target.detail).font(.subheadline).opacity(0.85)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).opacity(0.7)
            }.padding(16).foregroundStyle(.white)
                .background(Brand.forest, in: RoundedRectangle(cornerRadius: 20))
        }.buttonStyle(.plain).accessibilityIdentifier("hubResume_\(target.id)")
            .accessibilityLabel("Resume \(target.title)")
    }

    private func tile(_ choice: TutorialDestination) -> some View {
        let _ = progressRevision
        let saved: EverydayTutorialSession? = {
            if case .everyday(let id) = choice { return progressStore.load(courseID: id) }
            return nil
        }()
        let actionCount: Int? = {
            if case .everyday(let id) = choice { return EverydayTutorialCourse.course(id).actions.count }
            return nil
        }()
        let detail: String? = actionCount.map { count in
            if saved?.completed == true { return "Completed" }
            if let saved { return "Continue · \(saved.currentAction)/\(count)" }
            return "\(count) actions"
        }
        let accessibilityProgress: String = {
            guard let count = actionCount else { return "" }
            guard let saved else { return "\(count) actions" }
            if saved.completed { return "Completed by your confirmation" }
            return "Continue at action \(saved.currentAction) of \(count). \(saved.confirmedCount) actions confirmed by you."
        }()
        return Button { destination = choice } label: {
            VStack(alignment: .leading, spacing: 12) {
                Color.clear.aspectRatio(0.95, contentMode: .fit)
                    .overlay { thumbnail(choice).padding(12) }
                    .background(plate(for: choice), in: RoundedRectangle(cornerRadius: HomeCard.radius))
                    .overlay { RoundedRectangle(cornerRadius: HomeCard.radius).strokeBorder(HomeCard.stroke, lineWidth: 0.7) }
                    .overlay(alignment: .topTrailing) {
                        if saved?.completed == true {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(TutorialColors.orange)
                                .padding(12).accessibilityHidden(true)
                        }
                    }.clipped().allowsHitTesting(false).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(choice.title).font(.body.weight(.medium)).lineLimit(2)
                    if let detail {
                        Text(detail).font(.caption).foregroundStyle(TutorialColors.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let saved, let actionCount, saved.confirmedCount > 0, !saved.completed {
                        ProgressView(value: Double(saved.confirmedCount), total: Double(actionCount))
                            .tint(TutorialColors.orange).padding(.top, 3)
                            .accessibilityHidden(true)
                    }
                }.padding(.horizontal, 2)
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(choice.title)
            .accessibilityValue(accessibilityProgress)
            .accessibilityIdentifier(choice.accessibilityID)
    }

    @ViewBuilder
    private func thumbnail(_ choice: TutorialDestination) -> some View {
        switch choice {
        case .everyday(let id):
            modelThumbnail(everydayThumbnail(id), symbol: "square.stack.3d.up")
                .shadow(color: .black.opacity(0.12), radius: 7, y: 9)
        case .classicDart, .origami:
            modelThumbnail("dart-preview", symbol: "paperplane")
                .shadow(color: .black.opacity(0.15), radius: 9, y: 12)
        case .origamiLesson(let lesson), .resumeOrigami(let lesson):
            Image(systemName: lesson.symbol).font(.system(size: 44, weight: .light)).foregroundStyle(.white)
        case .equipment(let id):
            modelThumbnail(id == .gearmotor ? "gearmotor-preview" : "turbofan-preview", symbol: id.symbol)
        case .product:
            modelThumbnail("aeris-preview", symbol: "air.purifier")
        }
    }

    private func everydayThumbnail(_ id: EverydayTutorialID) -> String {
        switch id {
        case .towel: return "everyday-towel-preview"
        case .tShirt: return "everyday-t-shirt-preview"
        case .flatBedsheet: return "everyday-bedsheet-preview"
        case .squareKnot: return "everyday-square-knot-preview"
        case .fourInHand: return "everyday-necktie-preview"
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
                    Text("Classic Dart's paper alignment and outline checks are experimental. Towel, T-shirt and bedsheet AR offer manual three-point alignment to a flat item. Knots and ties use a tabletop visual reference. Everyday guides do not track changing fabric or strands, or grade your work. Equipment AR places a virtual teaching model; it does not recognise or register to real equipment.")
                    Text("AERIS One is an original concept product. These walkthroughs are demonstrations, not manufacturer-approved maintenance instructions. Equipment and everyday courses still need independent learning review.")
                    Text("English narration and supported voice commands run on device. Cloud AI chat is not enabled. Normal use does not save or upload camera photos; progress stays on this device.")
                }.font(.body).padding(24)
            }.background(TutorialColors.paper).navigationTitle("About ProTacta")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showAbout = false } } }
        }
    }
}

struct PlansView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selected = 1

    private struct Plan: Identifiable {
        let id = UUID()
        let name: String
        let price: String
        let period: String?
        let note: String
        let features: [String]
        let recommended: Bool
    }

    private let plans: [Plan] = [
        Plan(name: "Free", price: "QAR 0", period: nil, note: "Try before you pay",
             features: ["2 starter lessons (with AR guide)", "3D steps you can rotate", "Voice control"],
             recommended: false),
        Plan(name: "ProTacta Plus", price: "QAR 29", period: "month", note: "or QAR 218 / year",
             features: ["Full lesson library", "AR guide on your own object", "3D steps you can rotate",
                        "Voice control", "New lessons every month"],
             recommended: true),
        Plan(name: "Family", price: "QAR 45", period: "month", note: "One plan for the home",
             features: ["Everything in Plus", "Up to 4 learners", "Kids' progress and badges"],
             recommended: false)
    ]

    private let accent = Brand.orange

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 10) {
                        Image(systemName: "leaf").font(.system(size: 26, weight: .light))
                        Text("PROTACTA COMPLETE").font(.system(size: 10, weight: .bold)).tracking(1.7)
                    }.foregroundStyle(accent)
                    Text("Small folds.\nMore possibilities.").font(.system(size: 32, weight: .semibold))
                    Text("Watch it in 3D, then fold it yourself - hands-free. Pick the plan that fits.")
                        .font(.subheadline).lineSpacing(4).foregroundStyle(TutorialColors.muted)
                    VStack(spacing: 10) {
                        ForEach(plans.indices, id: \.self) { index in planRow(index) }
                    }
                    let plan = plans[selected]
                    VStack(alignment: .leading, spacing: 12) {
                        Text("WHAT'S INCLUDED IN \(plan.name.uppercased())")
                            .font(.system(size: 11, weight: .bold)).tracking(0.8).foregroundStyle(TutorialColors.muted)
                        ForEach(plan.features, id: \.self) { feature in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "checkmark.circle.fill").font(.system(size: 15)).foregroundStyle(accent)
                                Text(feature).font(.system(size: 15))
                                Spacer(minLength: 0)
                            }
                        }
                    }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
                    Button { dismiss() } label: {
                        HStack {
                            Spacer()
                            Text(plan.price == "QAR 0" ? "Start with Free" : "Choose \(plan.name)")
                            Image(systemName: "arrow.right")
                            Spacer()
                        }.font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                            .padding(.vertical, 16).background(accent, in: RoundedRectangle(cornerRadius: 15))
                    }.buttonStyle(.plain).accessibilityIdentifier("choosePlan")
                    Text("The dart and fox lessons stay free. Prices in Qatari Riyal. Prototype preview - no charges are made.")
                        .font(.caption).foregroundStyle(TutorialColors.muted).lineSpacing(3)
                }.padding(28).frame(maxWidth: 640).frame(maxWidth: .infinity)
            }.background(Brand.cream).foregroundStyle(Brand.ink).tint(accent)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("closePlans") } }
        }
        .fontDesign(.rounded)
        .accessibilityIdentifier("plansPage")
    }

    private func planRow(_ index: Int) -> some View {
        let plan = plans[index]
        let isSelected = selected == index
        return Button { selected = index } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 20)).foregroundStyle(isSelected ? accent : TutorialColors.muted)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(plan.name).font(.system(size: 16, weight: .semibold))
                        if plan.recommended {
                            Text("Recommended").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                                .padding(.horizontal, 8).padding(.vertical, 3).background(accent, in: Capsule())
                        }
                    }
                    Text(plan.note).font(.system(size: 11)).foregroundStyle(TutorialColors.muted)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(plan.price).font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(plan.recommended ? accent : Brand.ink)
                    if let period = plan.period {
                        Text("per \(period)").font(.system(size: 10)).foregroundStyle(TutorialColors.muted)
                    }
                }
            }.padding(16).frame(maxWidth: .infinity, minHeight: 72)
                .background(isSelected ? accent.opacity(0.08) : .white.opacity(0.6), in: RoundedRectangle(cornerRadius: 15))
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(isSelected ? accent : TutorialColors.line, lineWidth: isSelected ? 1.5 : 1))
        }.buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("plansPlan_\(index)")
    }
}
