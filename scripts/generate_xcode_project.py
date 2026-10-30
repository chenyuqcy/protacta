#!/usr/bin/env python3
"""Generate the standalone Protacta Xcode project without dependencies.

Re-run whenever Swift files or bundle resources are added. IDs are deterministic,
so generating again does not reorder the project or affect existing source files.
"""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1] / "ios"
APP = "Protacta"
SOURCE_NAMES = {APP: "PaperSteps", APP + "Tests": "PaperStepsTests", APP + "UITests": "PaperStepsUITests"}
TEAM = "67P96Z83PX"
BUNDLE = "org.realitycore.protacta.prototype"
VERSION = "0.1.0"
BUILD = "11"
TARGETS = [APP, APP + "Tests", APP + "UITests"]
objects = []


def uid(value):
    return hashlib.sha1(value.encode()).hexdigest()[:24].upper()


def add(key, body):
    objects.append(f"{uid(key)} = {{ {body} }};")
    return uid(key)


def arr(values):
    return "(" + ",".join(values) + ",)" if values else "()"


def q(value):
    return json.dumps(str(value), ensure_ascii=False)


def file_type(path):
    return {
        ".swift": "sourcecode.swift", ".usdz": "file.usdz",
        ".png": "image.png", ".jpg": "image.jpeg", ".hdr": "image.hdr",
        ".xcassets": "folder.assetcatalog", ".xcprivacy": "text.xml",
        ".json": "text.json", ".plist": "text.plist.xml", ".txt": "text",
    }.get(path.suffix.lower(), "file")


products = []
source_groups = []
for name in TARGETS:
    source_dir = ROOT / SOURCE_NAMES[name]
    source_dir.mkdir(parents=True, exist_ok=True)
    is_app = name == APP
    ext = "app" if is_app else "xctest"
    product_type = "wrapper.application" if is_app else "wrapper.cfbundle"
    products.append(add(name + "product", f"isa = PBXFileReference; explicitFileType = {product_type}; path = {name}.{ext}; sourceTree = BUILT_PRODUCTS_DIR;"))
    files, sources, resources = [], [], []
    candidates = sorted(source_dir.rglob("*.swift"))
    if is_app:
        resource_dir = source_dir / "Resources"
        candidates += sorted(p for p in resource_dir.rglob("*") if p.is_file() and not p.name.startswith("."))
        product_resources = source_dir / "ProductManual" / "Resources"
        candidates += sorted(p for p in product_resources.rglob("*") if p.is_file() and not p.name.startswith("."))
        assets = source_dir / "Assets.xcassets"
        assets.mkdir(parents=True, exist_ok=True)
        (assets / "Contents.json").write_text('{"info":{"author":"xcode","version":1}}\n')
        candidates.append(assets)
    else:
        # UI test runners have a separate main bundle. The local StoreKit
        # fixture belongs to tests, and is excluded from release app bundles.
        fixture = source_dir / "Resources" / "ProtactaTesting.storekit"
        fixture.parent.mkdir(parents=True, exist_ok=True)
        fixture.write_bytes((ROOT / "PaperSteps/Resources/ProtactaTesting.storekit").read_bytes())
        candidates.append(fixture)
    for path in candidates:
        relative = path.relative_to(ROOT)
        reference = add(str(relative), f"isa = PBXFileReference; lastKnownFileType = {file_type(path)}; path = {q(relative)}; sourceTree = SOURCE_ROOT;")
        build = add(str(relative) + "build", f"isa = PBXBuildFile; fileRef = {reference};")
        files.append(reference)
        (sources if path.suffix == ".swift" else resources).append(build)
    source_groups.append(add(name + "group", f'isa = PBXGroup; children = {arr(files)}; name = {name}; sourceTree = "<group>";'))
    source_phase = add(name + "sources", f"isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {arr(sources)}; runOnlyForDeploymentPostprocessing = 0;")
    resource_phase = add(name + "resources", f"isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = {arr(resources)}; runOnlyForDeploymentPostprocessing = 0;")
    framework_phase = add(name + "frameworks", "isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;")
    dependencies = []
    if not is_app:
        proxy = add(name + "proxy", f'isa = PBXContainerItemProxy; containerPortal = {uid("project")}; proxyType = 1; remoteGlobalIDString = {uid(APP + "target")}; remoteInfo = {APP};')
        dependencies.append(add(name + "dependency", f'isa = PBXTargetDependency; target = {uid(APP + "target")}; targetProxy = {proxy};'))
    configs = []
    for config in ["Debug", "Release"]:
        settings = {
            "PRODUCT_NAME": "$(TARGET_NAME)",
            "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE + ("" if is_app else "." + name),
            "SWIFT_VERSION": "5.0",
            "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
            "TARGETED_DEVICE_FAMILY": "1,2",
            "SDKROOT": "iphoneos",
            "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
            "GENERATE_INFOPLIST_FILE": "YES",
            "DEVELOPMENT_TEAM": TEAM,
            "CODE_SIGN_STYLE": "Automatic",
            "ENABLE_TESTABILITY": "YES",
            "SWIFT_EMIT_LOC_STRINGS": "YES",
            "SWIFT_OPTIMIZATION_LEVEL": "-Onone" if config == "Debug" else "-O",
            "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks @loader_path/Frameworks",
        }
        if config == "Debug":
            settings["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = "$(inherited) DEBUG"
        if is_app:
            settings.update({
                "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
                "INFOPLIST_KEY_CFBundleDisplayName": "Protacta",
                "INFOPLIST_KEY_NSCameraUsageDescription": "Use the camera to align guidance with supported paper states or place a 3D product lesson on a table. Images are processed on your device, not uploaded.",
                "INFOPLIST_KEY_NSMicrophoneUsageDescription": "Optionally use the microphone for hands-free English lesson commands such as Next step, Previous step and Show me again. Audio is not saved or uploaded by Protacta.",
                "INFOPLIST_KEY_NSSpeechRecognitionUsageDescription": "Optionally recognize English tutorial commands on your device. Protacta only enables voice control when on-device recognition is available.",
                "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
                "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES",
                "INFOPLIST_KEY_UISupportedInterfaceOrientations": "UIInterfaceOrientationPortrait",
                "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad": "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight",
                "INFOPLIST_KEY_ITSAppUsesNonExemptEncryption": "NO",
                "MARKETING_VERSION": VERSION,
                "CURRENT_PROJECT_VERSION": BUILD,
            })
            if config == "Release":
                settings["EXCLUDED_SOURCE_FILE_NAMES"] = "ProtactaTesting.storekit"
        elif name == APP + "Tests":
            settings.update({"TEST_HOST": f"$(BUILT_PRODUCTS_DIR)/{APP}.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/{APP}", "BUNDLE_LOADER": "$(TEST_HOST)"})
        else:
            settings["TEST_TARGET_NAME"] = APP
        body = " ".join(f"{key} = {q(value)};" for key, value in settings.items())
        configs.append(add(name + config, f"isa = XCBuildConfiguration; buildSettings = {{ {body} }}; name = {config};"))
    config_list = add(name + "configlist", f"isa = XCConfigurationList; buildConfigurations = {arr(configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;")
    target_type = "com.apple.product-type.application" if is_app else "com.apple.product-type.bundle.unit-test" if name == APP + "Tests" else "com.apple.product-type.bundle.ui-testing"
    add(name + "target", f'isa = PBXNativeTarget; buildConfigurationList = {config_list}; buildPhases = {arr([source_phase, framework_phase, resource_phase])}; buildRules = (); dependencies = {arr(dependencies)}; name = {name}; productName = {name}; productReference = {uid(name + "product")}; productType = {q(target_type)};')

product_group = add("products", f'isa = PBXGroup; children = {arr(products)}; name = Products; sourceTree = "<group>";')
main_group = add("main", f'isa = PBXGroup; children = {arr(source_groups + [product_group])}; sourceTree = "<group>";')
project_configs = []
for config in ["Debug", "Release"]:
    debug_format = "dwarf" if config == "Debug" else '"dwarf-with-dsym"'
    project_configs.append(add("project" + config, f"isa = XCBuildConfiguration; buildSettings = {{ CLANG_ENABLE_MODULES = YES; CLANG_ENABLE_OBJC_ARC = YES; DEBUG_INFORMATION_FORMAT = {debug_format}; SWIFT_COMPILATION_MODE = singlefile; }}; name = {config};"))
project_config_list = add("projectconfigs", f"isa = XCConfigurationList; buildConfigurations = {arr(project_configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;")
add("project", f'isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 2600; }}; buildConfigurationList = {project_config_list}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en,Base); mainGroup = {main_group}; productRefGroup = {product_group}; projectDirPath = ""; projectRoot = ""; targets = {arr([uid(n + "target") for n in TARGETS])};')

project = ROOT / (APP + ".xcodeproj")
project.mkdir(parents=True, exist_ok=True)
(project / "project.pbxproj").write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n' + "\n".join(objects) + f'\n}}; rootObject = {uid("project")}; }}\n')


def reference(name):
    extension = "app" if name == APP else "xctest"
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid(name + "target")}" BuildableName="{name}.{extension}" BlueprintName="{name}" ReferencedContainer="container:{APP}.xcodeproj"/>'


scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.7">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference(APP)}</BuildActionEntry></BuildActionEntries></BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{reference(APP + "Tests")}</TestableReference><TestableReference skipped="NO">{reference(APP + "UITests")}</TestableReference></Testables></TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference(APP)}</BuildableProductRunnable></LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference(APP)}</BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
'''
scheme_file = project / f"xcshareddata/xcschemes/{APP}.xcscheme"
scheme_file.parent.mkdir(parents=True, exist_ok=True)
scheme_file.write_text(scheme)
# An explicitly named local billing scheme opts into Xcode's purchase server.
# The normal run/archive scheme always uses App Store / sandbox products.
fixture_path = ROOT / "PaperSteps/Resources/ProtactaTesting.storekit"
testing_scheme = scheme.replace("</LaunchAction>", f'<StoreKitConfigurationFileReference identifier="{fixture_path}"/></LaunchAction>')
(scheme_file.parent / f"{APP}-StoreKit.xcscheme").write_text(testing_scheme)
print(project)
print(f"Swift files: {sum(len(list((ROOT / SOURCE_NAMES[n]).rglob('*.swift'))) for n in TARGETS)}")
