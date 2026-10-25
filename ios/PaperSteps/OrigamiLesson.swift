import Foundation

enum OrigamiLesson: String, CaseIterable, Identifiable {
    case crane, star, frog, turtle, fullRabbit, sittingDog, fullFox, elephant, butterfly, dart, fox, rabbit
    var presentsStandingFinish: Bool { self == .fullRabbit || self == .sittingDog || self == .fullFox || self == .elephant }
    var isFree: Bool { self == .dart || self == .fox }
    private var animalKind: AnimalKind? {
        switch self { case .fox: return .fox; case .rabbit: return .rabbit; case .butterfly: return .butterfly; default: return nil }
    }
    var id: String { rawValue }

    var title: String {
        switch self {
        case .crane: return "The Paper Crane"
        case .star: return "The Lucky Star"
        case .dart: return "The Classic Dart"
        case .fox: return "The Little Fox"
        case .rabbit: return "The Paper Rabbit"
        case .butterfly: return "The Paper Butterfly"
        case .frog: return "The Jumping Frog"
        case .turtle: return "The Paper Turtle"
        case .fullRabbit: return "The Standing Rabbit"
        case .sittingDog: return "The Sitting Dog"
        case .fullFox: return "The Long-Tail Fox"
        case .elephant: return "The Paper Elephant"
        }
    }
    var shortTitle: String {
        switch self { case .crane: return "Crane"; case .star: return "Lucky star"; case .dart: return "Dart"; case .fox: return "Fox"; case .rabbit: return "Rabbit"; case .butterfly: return "Butterfly"; case .frog: return "Jumping frog"; case .turtle: return "Turtle"; case .fullRabbit: return "Standing rabbit"; case .sittingDog: return "Sitting dog"; case .fullFox: return "Full fox"; case .elephant: return "Elephant" }
    }
    var symbol: String {
        switch self { case .crane: return "bird"; case .star: return "star"; case .dart: return "paperplane"; case .fox: return "cat"; case .rabbit, .fullRabbit: return "hare"; case .butterfly: return "leaf"; case .frog: return "pawprint"; case .turtle: return "tortoise"; case .sittingDog: return "dog"; case .fullFox: return "pawprint"; case .elephant: return "leaf" }
    }
    var level: String {
        switch self { case .fullFox, .elephant: return "ADVANCED"; case .crane, .butterfly, .turtle, .fullRabbit, .sittingDog: return "INTERMEDIATE"; case .star: return "PATIENT BEGINNER"; case .frog: return "CONFIDENT BEGINNER"; case .dart, .fox, .rabbit: return "BEGINNER" }
    }
    var time: String {
        switch self { case .crane, .frog: return "About 20 min"; case .turtle, .fullRabbit: return "About 25 min"; case .sittingDog: return "About 30 min"; case .fullFox: return "About 35 min"; case .elephant: return "About 45 min"; case .star: return "About 10 min"; case .dart, .fox: return "About 5 min"; case .rabbit: return "About 8 min"; case .butterfly: return "About 15 min" }
    }
    var paperLabel: String {
        switch self { case .crane, .fox, .rabbit, .butterfly, .turtle, .fullRabbit, .sittingDog, .fullFox, .elephant: return "Square paper"; case .star: return "Paper strip"; case .dart: return "A4 paper"; case .frog: return "1:2 rectangle" }
    }
    var introductionTitle: String {
        switch self {
        case .crane: return "A square of paper.\nA pair of wings."
        case .star: return "One paper strip.\nA little lucky star."
        case .dart: return "A sheet of paper.\nA little flight."
        case .fox: return "A few small folds.\nA bright little fox."
        case .rabbit: return "A square of paper.\nTwo curious ears."
        case .butterfly: return "A patient little fold.\nFour gentle wings."
        case .frog: return "A folded spring.\nA little leap."
        case .turtle: return "One patient square.\nA little paper turtle."
        case .fullRabbit: return "One patient square.\nA rabbit with character."
        case .sittingDog: return "One square. Broad paws.\nA faithful little friend."
        case .fullFox: return "One square. A long tail.\nA curious paper fox."
        case .elephant: return "One patient square.\nA little paper elephant."
        }
    }
    var introduction: String {
        switch self {
        case .crane: return "Learn the traditional crane, including pocket folds, petal folds and inside reverse folds. Take each motion at your own pace."
        case .star: return "Tie, wrap and gently shape a tiny three-dimensional star. Watch every motion, then try it with your own paper strip."
        case .dart: return "Fold a classic paper plane, one motion at a time. Watch, pause, then try it with your own paper."
        case .fox: return "Meet a friendly first fold. Shape the face, raise the ears and make a little fox from a single square."
        case .rabbit: return "Fold a rabbit face with two long ears. Follow the creases, turn the paper and give each little detail time."
        case .butterfly: return "Open pockets, shape a boat base and raise four wings. Discover a traditional butterfly through small, deliberate motions."
        case .fullFox: return "Shape a full fox with a pointed muzzle, broad ears and a long tail. Follow the layered folds and short crimps in this authored variation."
        case .elephant: return "Shape a complete elephant with a broad head, four feet and a hanging trunk. Follow each pocket and fold, then gently open the body."
        case .sittingDog: return "Build a seated dog with a shaped muzzle, a long tail and broad front paws. Explore layered reverses and short crimps, one motion at a time."
        case .fullRabbit: return "Fold a complete standing rabbit with long ears, paired haunches and a little tail. Learn pocket folds and a coupled neck fold in this square-body variation."
        case .turtle: return "Shape a complete turtle with a raised shell, a head, a short tail and four legs. Explore each pocket and pleat, then gently form the feet."
        case .frog: return "Shape a complete frog with four legs and a folded spring. Follow the pocket collapses and layered folds, then try a little jump with your own paper."
        }
    }
    var completion: String {
        switch self {
        case .crane: return "One square has become a paper crane. Explore its wings, neck and tail, then compare it with your own folds."
        case .star: return "One strip, now a little lucky star. Turn it around and admire the five points you shaped."
        case .dart: return "One flat sheet, now a little paper plane. Take a moment to explore your folds."
        case .fox: return "Your little fox has taken shape. Add eyes and a nose to your real paper if you like."
        case .rabbit: return "Two long ears, one little rabbit. Add a face to your real paper to make it your own."
        case .butterfly: return "Your butterfly is ready. Gently adjust the wings of your real paper until it sits the way you like."
        case .fullFox: return "Your fox has a pointed muzzle and a long tail. Gently open the paired layers of your real paper model and adjust its lower folds until it balances."
        case .elephant: return "Your elephant has taken shape. Ease the body of your real paper model open and rest it on its lower front and rear folds."
        case .sittingDog: return "Your sitting dog has taken shape. Ease its two sides apart and settle its broad paws on the table. Adjust the base gently until it balances."
        case .fullRabbit: return "Your rabbit has long ears, two haunches and a short tail. Ease the body of your real paper rabbit open and adjust its lower folds until it balances."
        case .turtle: return "Your turtle has a shell, a head, four legs and a tiny tail. Rest your own paper turtle on the table and gently balance its feet."
        case .frog: return "Four legs and a paper spring. Set your real frog on a firm surface, press its back gently, and release. Adjust the creases if it tips to one side."
        }
    }
    var steps: [LessonStep] {
        switch self { case .crane: return CraneLessonContent.steps; case .star: return StarLessonContent.steps; case .dart: return PaperLesson.steps; case .frog: return FrogLessonContent.steps; case .turtle: return TurtleLessonContent.steps; case .fullRabbit: return FullRabbitLessonContent.steps; case .sittingDog: return SittingDogLessonContent.steps; case .fullFox: return FullFoxLessonContent.steps; case .elephant: return ElephantFinalContent.steps; case .fox, .rabbit, .butterfly: return AnimalLessonContent.steps(for: animalKind!) }
    }
    var lastStep: Int { steps.count - 1 }
    var material: String {
        switch self { case .crane: return CraneLessonContent.material; case .star: return StarLessonContent.material; case .dart: return PaperLesson.material; case .frog: return FrogLessonContent.material; case .turtle: return TurtleLessonContent.material; case .fullRabbit: return FullRabbitLessonContent.material; case .sittingDog: return SittingDogLessonContent.material; case .fullFox: return FullFoxLessonContent.material; case .elephant: return ElephantFinalContent.material; case .fox, .rabbit, .butterfly: return AnimalLessonContent.material(for: animalKind!) }
    }
    var sourceName: String {
        switch self { case .crane: return CraneLessonContent.sourceName; case .star: return StarLessonContent.sourceName; case .dart: return PaperLesson.sourceName; case .frog: return FrogLessonContent.sourceName; case .turtle: return TurtleLessonContent.sourceName; case .fullRabbit: return FullRabbitLessonContent.sourceName; case .sittingDog: return SittingDogLessonContent.sourceName; case .fullFox: return FullFoxLessonContent.sourceName; case .elephant: return ElephantFinalContent.sourceName; case .fox, .rabbit, .butterfly: return AnimalLessonContent.sourceName(for: animalKind!) }
    }
    var sourceURL: URL {
        switch self { case .crane: return CraneLessonContent.sourceURL; case .star: return StarLessonContent.sourceURL; case .dart: return PaperLesson.sourceURL; case .frog: return FrogLessonContent.sourceURL; case .turtle: return TurtleLessonContent.sourceURL; case .fullRabbit: return FullRabbitLessonContent.sourceURL; case .sittingDog: return SittingDogLessonContent.sourceURL; case .fullFox: return FullFoxLessonContent.sourceURL; case .elephant: return ElephantFinalContent.sourceURL; case .fox, .rabbit, .butterfly: return AnimalLessonContent.sourceURL(for: animalKind!) }
    }
    func frame(step: Int, progress: Float) -> PaperFrame {
        switch self {
        case .crane: return CraneGeometry.frame(step: step, progress: progress)
        case .star: return StarGeometry.frame(step: step, progress: progress)
        case .dart: return PaperGeometry.frame(step: step, progress: progress)
        case .frog: return FrogGeometry.frame(step: step, progress: progress)
        case .turtle: return TurtleGeometry.frame(step: step, progress: progress)
        case .fullRabbit: return FullRabbitGeometry.frame(step: step, progress: progress)
        case .sittingDog: return SittingDogGeometry.frame(step: step, progress: progress)
        case .fullFox: return FullFoxReverseGeometry.frame(step: step, progress: progress)
        case .elephant: return ElephantRenderSurface.apply(to: ElephantAssemblyGeometry.frame(step: step, progress: progress))
        case .fox, .rabbit, .butterfly: return AnimalGeometry.frame(kind: animalKind!, step: step, progress: progress)
        }
    }
}
