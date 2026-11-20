#!/usr/bin/env python3
"""Generate the standalone Protacta Xcode project without dependencies.

Re-run whenever Swift files or bundle resources are added. IDs are deterministic,
so generating again does not reorder the project or affect existing source files.
"""
from pathlib import Path
import argparse
import hashlib
import json

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--foliafold-update", action="store_true",
                    help="Generate the production update project for the existing Foliafold listing.")
foliafold_update = parser.parse_args().foliafold_update

ROOT = Path(__file__).resolve().parents[1] / "ios"
APP = "Protacta"
CLIP = "ProtactaClip"
SOURCE_NAMES = {APP: "PaperSteps", CLIP: CLIP, APP + "Tests": "PaperStepsTests", APP + "UITests": "PaperStepsUITests"}
TEAM = "67P96Z83PX"
PROTOTYPE_BUNDLE = "org.realitycore.protacta.prototype"
BUNDLE = "org.realitycore.foliafold" if foliafold_update else PROTOTYPE_BUNDLE
CLIP_BUNDLE = BUNDLE + ".Clip"
VERSION, BUILD = ("1.1.1", "40") if foliafold_update else ("1.0", "40")
PROJECT_NAME = "Protacta-FoliafoldUpdate.xcodeproj" if foliafold_update else "Protacta.xcodeproj"
CLIP_ENTITLEMENTS = "FoliafoldUpdate.entitlements" if foliafold_update else "ProtactaClip.entitlements"
TARGETS = list(SOURCE_NAMES)
APPLICATION_TARGETS = {APP, CLIP}
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
        ".json": "text.json", ".plist": "text.plist.xml", ".entitlements": "text.plist.entitlements", ".txt": "text",
    }.get(path.suffix.lower(), "file")


def storekit_fixture(name):
    if not foliafold_update:
        return ROOT / SOURCE_NAMES[name] / "Resources/ProtactaTesting.storekit"
    return ROOT / ".foliafold-update" / SOURCE_NAMES[name] / "ProtactaTesting.storekit"


fixture_source = ROOT / "PaperSteps/Resources/ProtactaTesting.storekit"
fixture_contents = fixture_source.read_bytes()
if foliafold_update:
    fixture_contents = fixture_contents.replace(PROTOTYPE_BUNDLE.encode(), BUNDLE.encode())
for name in (APP, APP + "Tests", APP + "UITests"):
    fixture = storekit_fixture(name)
    if fixture != fixture_source:
        fixture.parent.mkdir(parents=True, exist_ok=True)
        fixture.write_bytes(fixture_contents)


products = []
source_groups = []
file_references = {}
for name in TARGETS:
    source_dir = ROOT / SOURCE_NAMES[name]
    source_dir.mkdir(parents=True, exist_ok=True)
    is_app = name == APP
    is_clip = name == CLIP
    is_application = name in APPLICATION_TARGETS
    ext = "app" if is_application else "xctest"
    product_type = "wrapper.application" if is_application else "wrapper.cfbundle"
    products.append(add(name + "product", f"isa = PBXFileReference; explicitFileType = {product_type}; path = {name}.{ext}; sourceTree = BUILT_PRODUCTS_DIR;"))
    files, sources, resources = [], [], []
    candidates = sorted(source_dir.rglob("*.swift"))
    if is_app:
        resource_dir = source_dir / "Resources"
        candidates += sorted(p for p in resource_dir.rglob("*") if p.is_file() and not p.name.startswith(".")
                             and p != fixture_source)
        candidates.append(storekit_fixture(name))
        product_resources = source_dir / "ProductManual" / "Resources"
        candidates += sorted(p for p in product_resources.rglob("*") if p.is_file() and not p.name.startswith("."))
        assets = source_dir / "Assets.xcassets"
        assets.mkdir(parents=True, exist_ok=True)
        if not (assets / "Contents.json").exists():
            (assets / "Contents.json").write_text('{"info":{"author":"xcode","version":1}}\n')
        candidates.append(assets)
    elif is_clip:
        shared = ROOT / SOURCE_NAMES[APP]
        candidates += [shared / filename for filename in (
            "PaperGeometry.swift", "EverydayMotionPlayback.swift", "Assets.xcassets",
        )]
    else:
        # UI test runners have a separate main bundle. The local StoreKit
        # fixture belongs to tests, and is excluded from release app bundles.
        candidates.append(storekit_fixture(name))
        if name == APP + "UITests":
            candidates.append(ROOT / SOURCE_NAMES[APP] / "AppReleaseIdentity.swift")
    for path in candidates:
        relative = path.relative_to(ROOT)
        if relative not in file_references:
            reference = add(str(relative), f"isa = PBXFileReference; lastKnownFileType = {file_type(path)}; path = {q(relative)}; sourceTree = SOURCE_ROOT;")
            file_references[relative] = reference
            files.append(reference)
        reference = file_references[relative]
        shared_member = is_clip or path.name == "AppReleaseIdentity.swift" and not is_app
        build_key = str(relative) + "build" + (name if shared_member else "")
        build = add(build_key, f"isa = PBXBuildFile; fileRef = {reference};")
        (sources if path.suffix == ".swift" else resources).append(build)
    if is_clip:
        for filename in ["Info.plist", CLIP_ENTITLEMENTS]:
            path = source_dir / filename
            relative = path.relative_to(ROOT)
            files.append(add(str(relative), f"isa = PBXFileReference; lastKnownFileType = {file_type(path)}; path = {q(relative)}; sourceTree = SOURCE_ROOT;"))
    source_groups.append(add(name + "group", f'isa = PBXGroup; children = {arr(files)}; name = {name}; sourceTree = "<group>";'))
    source_phase = add(name + "sources", f"isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {arr(sources)}; runOnlyForDeploymentPostprocessing = 0;")
    resource_phase = add(name + "resources", f"isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = {arr(resources)}; runOnlyForDeploymentPostprocessing = 0;")
    framework_phase = add(name + "frameworks", "isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;")
    phases = [source_phase, framework_phase, resource_phase]
    dependencies = []
    if is_app:
        embed_clip = add("embedClip", f"isa = PBXBuildFile; fileRef = {uid(CLIP + 'product')}; settings = {{ ATTRIBUTES = (RemoveHeadersOnCopy,); }};")
        phases.append(add("embedClipsPhase", f'isa = PBXCopyFilesBuildPhase; buildActionMask = 2147483647; dstPath = "$(CONTENTS_FOLDER_PATH)/AppClips"; dstSubfolderSpec = 16; files = {arr([embed_clip])}; name = "Embed App Clips"; runOnlyForDeploymentPostprocessing = 0;'))
    if not is_clip:
        dependency = CLIP if is_app else APP
        dependency_target = uid(dependency + "target")
        proxy = add(name + "proxy", f'isa = PBXContainerItemProxy; containerPortal = {uid("project")}; proxyType = 1; remoteGlobalIDString = {dependency_target}; remoteInfo = {dependency};')
        dependencies.append(add(name + "dependency", f'isa = PBXTargetDependency; target = {dependency_target}; targetProxy = {proxy};'))
    configs = []
    for config in ["Debug", "Release"]:
        settings = {
            "PRODUCT_NAME": "$(TARGET_NAME)",
            "PRODUCT_BUNDLE_IDENTIFIER": CLIP_BUNDLE if is_clip else BUNDLE + ("" if is_app else "." + name),
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
        compilation_conditions = ["$(inherited)"]
        if config == "Debug":
            compilation_conditions.append("DEBUG")
        if foliafold_update:
            compilation_conditions.append("FOLIAFOLD_UPDATE")
        if len(compilation_conditions) > 1:
            settings["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = " ".join(compilation_conditions)
        if is_application:
            settings.update({
                "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
                "INFOPLIST_KEY_CFBundleDisplayName": "Protacta",
                "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
                "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES",
                "INFOPLIST_KEY_UISupportedInterfaceOrientations": "UIInterfaceOrientationPortrait",
                "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad": "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight",
                "INFOPLIST_KEY_ITSAppUsesNonExemptEncryption": "NO",
                "MARKETING_VERSION": VERSION,
                "CURRENT_PROJECT_VERSION": BUILD,
            })
        if is_app:
            settings.update({
                "INFOPLIST_KEY_NSCameraUsageDescription": "Use the camera for paper guidance, tabletop 3D lessons, and manual alignment with flat everyday items. Images are processed on your device, not uploaded.",
                "INFOPLIST_KEY_NSMicrophoneUsageDescription": "Optionally use the microphone for hands-free English lesson commands such as Next step, Previous step and Show me again. Audio is not saved or uploaded by Protacta.",
                "INFOPLIST_KEY_NSSpeechRecognitionUsageDescription": "Optionally recognize English tutorial commands on your device. Protacta only enables voice control when on-device recognition is available.",
            })
            if config == "Release":
                settings["EXCLUDED_SOURCE_FILE_NAMES"] = "ProtactaTesting.storekit"
        elif is_clip:
            settings.update({
                "CODE_SIGN_ENTITLEMENTS": f"{CLIP}/{CLIP_ENTITLEMENTS}",
                "INFOPLIST_FILE": f"{CLIP}/Info.plist",
                "SKIP_INSTALL": "YES",
                "SUPPORTS_MACCATALYST": "NO",
                "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD": "NO",
            })
        elif name == APP + "Tests":
            settings.update({"TEST_HOST": f"$(BUILT_PRODUCTS_DIR)/{APP}.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/{APP}", "BUNDLE_LOADER": "$(TEST_HOST)"})
        else:
            settings["TEST_TARGET_NAME"] = APP
        body = " ".join(f"{key} = {q(value)};" for key, value in settings.items())
        configs.append(add(name + config, f"isa = XCBuildConfiguration; buildSettings = {{ {body} }}; name = {config};"))
    config_list = add(name + "configlist", f"isa = XCConfigurationList; buildConfigurations = {arr(configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;")
    target_type = {
        APP: "com.apple.product-type.application",
        CLIP: "com.apple.product-type.application.on-demand-install-capable",
        APP + "Tests": "com.apple.product-type.bundle.unit-test",
        APP + "UITests": "com.apple.product-type.bundle.ui-testing",
    }[name]
    add(name + "target", f'isa = PBXNativeTarget; buildConfigurationList = {config_list}; buildPhases = {arr(phases)}; buildRules = (); dependencies = {arr(dependencies)}; name = {name}; productName = {name}; productReference = {uid(name + "product")}; productType = {q(target_type)};')

product_group = add("products", f'isa = PBXGroup; children = {arr(products)}; name = Products; sourceTree = "<group>";')
main_group = add("main", f'isa = PBXGroup; children = {arr(source_groups + [product_group])}; sourceTree = "<group>";')
project_configs = []
for config in ["Debug", "Release"]:
    debug_format = "dwarf" if config == "Debug" else '"dwarf-with-dsym"'
    project_configs.append(add("project" + config, f"isa = XCBuildConfiguration; buildSettings = {{ CLANG_ENABLE_MODULES = YES; CLANG_ENABLE_OBJC_ARC = YES; DEBUG_INFORMATION_FORMAT = {debug_format}; SWIFT_COMPILATION_MODE = singlefile; }}; name = {config};"))
project_config_list = add("projectconfigs", f"isa = XCConfigurationList; buildConfigurations = {arr(project_configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;")
add("project", f'isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 2600; }}; buildConfigurationList = {project_config_list}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en,Base); mainGroup = {main_group}; productRefGroup = {product_group}; projectDirPath = ""; projectRoot = ""; targets = {arr([uid(n + "target") for n in TARGETS])};')

project = ROOT / PROJECT_NAME
project.mkdir(parents=True, exist_ok=True)
(project / "project.pbxproj").write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n' + "\n".join(objects) + f'\n}}; rootObject = {uid("project")}; }}\n')


def reference(name):
    extension = "app" if name in APPLICATION_TARGETS else "xctest"
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid(name + "target")}" BuildableName="{name}.{extension}" BlueprintName="{name}" ReferencedContainer="container:{PROJECT_NAME}"/>'


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
# Standalone Xcode project schemes resolve StoreKit references with a ../../ prefix.
fixture_path = Path("../..") / storekit_fixture(APP).relative_to(ROOT)
testing_scheme = scheme.replace("</LaunchAction>", f'<StoreKitConfigurationFileReference identifier="{fixture_path}"/></LaunchAction>')
(scheme_file.parent / f"{APP}-StoreKit.xcscheme").write_text(testing_scheme)
clip_scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.7">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="NO" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="NO" buildForAnalyzing="YES">{reference(CLIP)}</BuildActionEntry></BuildActionEntries></BuildAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES">
    <BuildableProductRunnable runnableDebuggingMode="0">{reference(CLIP)}</BuildableProductRunnable>
    <EnvironmentVariables><EnvironmentVariable key="_XCAppClipURL" value="https://appclip.apple.com/id?p={CLIP_BUNDLE}" isEnabled="YES"/></EnvironmentVariables>
  </LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference(CLIP)}</BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/>
</Scheme>
'''
(scheme_file.parent / f"{CLIP}.xcscheme").write_text(clip_scheme)
print(project)
print(f"Swift files: {sum(len(list((ROOT / SOURCE_NAMES[n]).rglob('*.swift'))) for n in TARGETS)}")
