/// The public update retains the original store and saved-progress identities.
enum AppReleaseIdentity {
    #if FOLIAFOLD_UPDATE
    static let productPrefix = "org.realitycore.foliafold"
    static let origamiContentRevisionSeed = "Foliafold lesson content v1"
    static let privacyPolicyURL = "https://realitycore.org/protacta/privacy"
    #else
    static let productPrefix = "org.realitycore.protacta.prototype"
    static let origamiContentRevisionSeed = "Protacta lesson content v1"
    static let privacyPolicyURL = "https://realitycore.org/foliafold/privacy"
    #endif
}
