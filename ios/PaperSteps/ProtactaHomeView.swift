import SwiftUI

private enum TutorialDestination: Identifiable {
    case origami, everyday(EverydayTutorialID), product
    var id: String {
        switch self {
        case .origami: return "origami"
        case .everyday(let id): return id.rawValue
        case .product: return "aeris"
        }
    }
}

enum TutorialColors {
    static let ink = Color(red: 0.12, green: 0.23, blue: 0.20)
    static let muted = Color(red: 0.37, green: 0.45, blue: 0.41)
    static let paper = Color(red: 0.96, green: 0.96, blue: 0.93)
    static let line = Color(red: 0.84, green: 0.88, blue: 0.83)
    static let orange = Color(red: 0.68, green: 0.28, blue: 0.18)
}

struct ProtactaHomeView: View {
    @State private var destination: TutorialDestination?
    @State private var progressRevision = 0
    @State private var showAbout = false
    private let progressStore = EverydayTutorialProgressStore.appDefault()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    brand
                    VStack(alignment: .leading, spacing: 12) {
                        Text("See the move.\nMake it yours.")
                            .font(.system(size: 39, weight: .semibold, design: .rounded)).tracking(-1.5)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Visual guidance for the things you do with your hands.")
                            .font(.system(size: 16)).foregroundStyle(TutorialColors.muted)
                    }
                    featuredOrigami
                    VStack(alignment: .leading, spacing: 14) {
                        sectionTitle("EVERYDAY SKILLS", subtitle: "Watch a move, try it, then confirm your progress.")
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 14) {
                            ForEach(EverydayTutorialID.allCases) { id in everydayCard(id) }
                        }
                    }
                    productCard
                    Text("Everyday skill confirmations save on this device. Camera checks are available in the Classic Dart practice; everyday skills use illustrated guidance.")
                        .font(.footnote).foregroundStyle(TutorialColors.muted)
                        .accessibilityIdentifier("hubCapabilityScope")
                }.padding(22).frame(maxWidth: 900).frame(maxWidth: .infinity)
            }
            .background(TutorialColors.paper).foregroundStyle(TutorialColors.ink)
            .toolbar(.hidden, for: .navigationBar)
        }
        .accessibilityIdentifier("tutorialHub")
        .fullScreenCover(item: $destination, onDismiss: { progressRevision += 1 }) { selected in
            switch selected {
            case .origami: PaperStepsView(onExit: { destination = nil })
            case .everyday(let id): EverydayTutorialPlayer(courseID: id, onExit: { destination = nil })
            case .product: AerisManualModuleView(onExit: { destination = nil })
            }
        }
        .sheet(isPresented: $showAbout) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Learn by looking and doing.").font(.title2.weight(.semibold))
                        Text("Choose paper folding, everyday skills or a product walkthrough. Each tutorial shows the movement and keeps your own confirmation separate from the animation.")
                        Text("Classic Dart has experimental paper alignment and visible-outline checks. Everyday skills show authored animated diagrams; they do not inspect your clothes or knots. AERIS places a virtual concept product in AR; it does not recognize a real appliance.")
                        Text("New everyday tutorials are prototype teaching content awaiting physical follow-through review. Optional read-aloud and supported English commands run on device. Cloud AI chat is not enabled in this version.")
                        Text("Camera photos are not saved or uploaded in normal use. Everyday progress is stored locally. AERIS is an original concept, so follow your actual appliance's approved manual for maintenance.")
                    }.padding(22)
                }.background(TutorialColors.paper)
                    .navigationTitle("About Protacta").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showAbout = false } } }
            }
        }
    }

    private var brand: some View {
        HStack {
            HStack(spacing: 9) {
                Image(systemName: "hand.draw.fill").font(.system(size: 20)).foregroundStyle(TutorialColors.orange)
                Text("PROTACTA").font(.system(size: 12, weight: .bold, design: .rounded)).tracking(2.8)
            }
            Spacer()
            Button { showAbout = true } label: { Image(systemName: "info.circle").frame(width: 44, height: 44) }
                .accessibilityLabel("About Protacta").accessibilityIdentifier("hubAbout")
        }
    }

    private var featuredOrigami: some View {
        Button { destination = .origami } label: {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 9) {
                    Text("PAPER & CRAFT").font(.system(size: 10, weight: .bold)).tracking(1.7)
                        .foregroundStyle(TutorialColors.orange)
                    Text("Start with a sheet.").font(.system(size: 24, weight: .semibold, design: .rounded))
                    Text("Classic Dart, Little Fox and the origami library.").font(.subheadline)
                        .foregroundStyle(TutorialColors.muted)
                    Label("3D lessons · Dart camera practice", systemImage: "viewfinder")
                        .font(.system(size: 11, weight: .medium))
                }
                Spacer(minLength: 0)
                Image(systemName: "paperplane").font(.system(size: 48, weight: .ultraLight))
                    .rotationEffect(.degrees(-15)).foregroundStyle(TutorialColors.ink)
            }.padding(21).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(red: 0.89, green: 0.92, blue: 0.85), in: RoundedRectangle(cornerRadius: 22))
        }.buttonStyle(.plain).accessibilityIdentifier("hubOrigami")
    }

    private func everydayCard(_ id: EverydayTutorialID) -> some View {
        let course = EverydayTutorialCourse.course(id)
        let _ = progressRevision
        let saved = progressStore.load(courseID: id)
        return Button { destination = .everyday(id) } label: {
            VStack(alignment: .leading, spacing: 10) {
                EverydayTutorialVisual(courseID: id.rawValue, stepIndex: 0, progress: 0, showsCaption: false)
                    .frame(height: 128).clipped().allowsHitTesting(false).accessibilityHidden(true)
                    .background(TutorialColors.paper, in: RoundedRectangle(cornerRadius: 12))
                Text(course.title).font(.system(size: 17, weight: .semibold, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 44, alignment: .topLeading)
                Text("\(course.actions.count) actions · Illustrated guide")
                    .font(.system(size: 11)).foregroundStyle(TutorialColors.muted)
                HStack(spacing: 5) {
                    Text(saved?.completed == true ? "Practise again" : saved == nil ? "Start learning" : "Continue action \(saved!.currentAction)")
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right")
                }.font(.system(size: 11, weight: .semibold)).foregroundStyle(TutorialColors.orange)
            }.padding(13).frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 18))
                .overlay { RoundedRectangle(cornerRadius: 18).stroke(TutorialColors.line.opacity(0.7), lineWidth: 1) }
        }.buttonStyle(.plain).accessibilityIdentifier("hubCourse_\(id.rawValue)")
    }

    private var productCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("PRODUCT MANUALS", subtitle: "Find the part. Follow the movement.")
            Button { destination = .product } label: {
                HStack(spacing: 18) {
                    Image(systemName: "air.purifier").font(.system(size: 45, weight: .light))
                        .frame(width: 66, height: 88)
                    VStack(alignment: .leading, spacing: 7) {
                        Text("AERIS One").font(.system(size: 23, weight: .semibold, design: .rounded))
                        Text("Replace a filter, explore the parts, set up and clean.")
                            .font(.subheadline).foregroundStyle(TutorialColors.muted)
                        Text("Interactive 3D · Tabletop AR · Concept product")
                            .font(.system(size: 10, weight: .medium))
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right")
                }.padding(20).background(.white, in: RoundedRectangle(cornerRadius: 20))
            }.buttonStyle(.plain).accessibilityIdentifier("hubProductManual")
        }
    }

    private func sectionTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 10, weight: .bold)).tracking(1.7)
            Text(subtitle).font(.subheadline).foregroundStyle(TutorialColors.muted)
        }
    }
}
