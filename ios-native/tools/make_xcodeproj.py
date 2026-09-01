#!/usr/bin/env python3
"""Generate an Xcode 15-compatible Eng.xcodeproj for the eng app, so it can be
opened in Xcode and Run on a device with automatic signing.

Independent of the swiftc OTA build (tools/ota/). Re-run after adding source
files. objectVersion 56 (Xcode 14/15 — NOT the FS-synchronized 77 that only
Xcode 16 opens).
"""
import os, uuid

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
ENG = os.path.join(REPO, "Eng")
PROJ_DIR = os.path.join(REPO, "Eng.xcodeproj")

TEAM = "GH6HRY4EWZ"
BUNDLE_ID = "com.coloristique.eng"
TARGET_NAME = "eng"
DEPLOYMENT_TARGET = "17.0"


def uid():
    return uuid.uuid4().hex[:24].upper()


# Collect Swift sources (paths relative to Eng/).
swift = []
for root, _dirs, files in os.walk(ENG):
    for f in sorted(files):
        if f.endswith(".swift"):
            swift.append(os.path.relpath(os.path.join(root, f), ENG))
swift.sort()

# Stable-ish ids.
ids = {k: uid() for k in [
    "proj", "maingroup", "enggroup", "prodgroup", "target", "prodfr",
    "sources", "frameworks", "resources", "projconflist", "targetconflist",
    "projdebug", "projrelease", "targetdebug", "targetrelease", "assetfr", "assetbf",
]}
fileref = {rel: uid() for rel in swift}
buildfile = {rel: uid() for rel in swift}


def q(s):  # quote a pbxproj string
    return '"%s"' % s


lines = []
lines.append("// !$*UTF8*$!")
lines.append("{")
lines.append("\tarchiveVersion = 1;")
lines.append("\tclasses = {\n\t};")
lines.append("\tobjectVersion = 56;")
lines.append("\tobjects = {")

# PBXBuildFile
lines.append("\n/* Begin PBXBuildFile section */")
for rel in swift:
    base = os.path.basename(rel)
    lines.append('\t\t%s /* %s in Sources */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };'
                 % (buildfile[rel], base, fileref[rel], base))
lines.append('\t\t%s /* Assets.xcassets in Resources */ = {isa = PBXBuildFile; fileRef = %s /* Assets.xcassets */; };'
             % (ids["assetbf"], ids["assetfr"]))
lines.append("/* End PBXBuildFile section */")

# PBXFileReference
lines.append("\n/* Begin PBXFileReference section */")
for rel in swift:
    base = os.path.basename(rel)
    lines.append('\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; name = %s; path = %s; sourceTree = "<group>"; };'
                 % (fileref[rel], base, q(base), q(rel)))
lines.append('\t\t%s /* Assets.xcassets */ = {isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>"; };'
             % ids["assetfr"])
lines.append('\t\t%s /* eng.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = eng.app; sourceTree = BUILT_PRODUCTS_DIR; };'
             % ids["prodfr"])
lines.append("/* End PBXFileReference section */")

# PBXFrameworksBuildPhase
lines.append("\n/* Begin PBXFrameworksBuildPhase section */")
lines.append('\t\t%s = {isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (\n\t\t); runOnlyForDeploymentPostprocessing = 0; };'
             % ids["frameworks"])
lines.append("/* End PBXFrameworksBuildPhase section */")

# PBXGroup
lines.append("\n/* Begin PBXGroup section */")
lines.append('\t\t%s = {isa = PBXGroup; children = (\n\t\t\t%s /* Eng */,\n\t\t\t%s /* Products */,\n\t\t); sourceTree = "<group>"; };'
             % (ids["maingroup"], ids["enggroup"], ids["prodgroup"]))
eng_children = "".join('\n\t\t\t%s /* %s */,' % (fileref[rel], os.path.basename(rel)) for rel in swift)
eng_children += '\n\t\t\t%s /* Assets.xcassets */,' % ids["assetfr"]
lines.append('\t\t%s /* Eng */ = {isa = PBXGroup; children = (%s\n\t\t); path = Eng; sourceTree = "<group>"; };'
             % (ids["enggroup"], eng_children))
lines.append('\t\t%s /* Products */ = {isa = PBXGroup; children = (\n\t\t\t%s /* eng.app */,\n\t\t); name = Products; sourceTree = "<group>"; };'
             % (ids["prodgroup"], ids["prodfr"]))
lines.append("/* End PBXGroup section */")

# PBXNativeTarget
lines.append("\n/* Begin PBXNativeTarget section */")
lines.append('\t\t%s /* eng */ = {isa = PBXNativeTarget; buildConfigurationList = %s; buildPhases = (\n\t\t\t%s /* Sources */,\n\t\t\t%s /* Frameworks */,\n\t\t\t%s /* Resources */,\n\t\t); buildRules = (\n\t\t); dependencies = (\n\t\t); name = eng; productName = eng; productReference = %s /* eng.app */; productType = "com.apple.product-type.application"; };'
             % (ids["target"], ids["targetconflist"], ids["sources"], ids["frameworks"], ids["resources"], ids["prodfr"]))
lines.append("/* End PBXNativeTarget section */")

# PBXProject
lines.append("\n/* Begin PBXProject section */")
lines.append('\t\t%s = {isa = PBXProject; attributes = { BuildIndependentTargetsInParallel = 1; LastSwiftUpdateCheck = 1540; LastUpgradeCheck = 1540; TargetAttributes = { %s = { CreatedOnToolsVersion = 15.4; }; }; }; buildConfigurationList = %s; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (\n\t\t\ten,\n\t\t\tBase,\n\t\t); mainGroup = %s; productRefGroup = %s /* Products */; projectDirPath = ""; projectRoot = ""; targets = (\n\t\t\t%s /* eng */,\n\t\t); };'
             % (ids["proj"], ids["target"], ids["projconflist"], ids["maingroup"], ids["prodgroup"], ids["target"]))
lines.append("/* End PBXProject section */")

# PBXResourcesBuildPhase
lines.append("\n/* Begin PBXResourcesBuildPhase section */")
lines.append('\t\t%s /* Resources */ = {isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (\n\t\t\t%s /* Assets.xcassets in Resources */,\n\t\t); runOnlyForDeploymentPostprocessing = 0; };'
             % (ids["resources"], ids["assetbf"]))
lines.append("/* End PBXResourcesBuildPhase section */")

# PBXSourcesBuildPhase
lines.append("\n/* Begin PBXSourcesBuildPhase section */")
src_files = "".join('\n\t\t\t%s /* %s in Sources */,' % (buildfile[rel], os.path.basename(rel)) for rel in swift)
lines.append('\t\t%s /* Sources */ = {isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (%s\n\t\t); runOnlyForDeploymentPostprocessing = 0; };'
             % (ids["sources"], src_files))
lines.append("/* End PBXSourcesBuildPhase section */")

# XCBuildConfiguration
proj_common = {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "YES",
    "CLANG_ANALYZER_NONNULL": "YES",
    "CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION": "YES_AGGRESSIVE",
    "CLANG_CXX_LANGUAGE_STANDARD": '"gnu++20"',
    "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES",
    "CLANG_ENABLE_OBJC_WEAK": "YES",
    "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES",
    "CLANG_WARN_UNGUARDED_AVAILABILITY": "YES_AGGRESSIVE",
    "COPY_PHASE_STRIP": "NO",
    "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
    "GCC_C_LANGUAGE_STANDARD": "gnu17",
    "GCC_NO_COMMON_BLOCKS": "YES",
    "IPHONEOS_DEPLOYMENT_TARGET": DEPLOYMENT_TARGET,
    "LOCALIZATION_PREFERS_STRING_CATALOGS": "YES",
    "MTL_FAST_MATH": "YES",
    "SDKROOT": "iphoneos",
}
proj_debug = dict(proj_common, **{
    "DEBUG_INFORMATION_FORMAT": "dwarf",
    "ENABLE_TESTABILITY": "YES",
    "GCC_DYNAMIC_NO_PIC": "NO",
    "GCC_OPTIMIZATION_LEVEL": "0",
    "GCC_PREPROCESSOR_DEFINITIONS": '(\n\t\t\t\t\t"DEBUG=1",\n\t\t\t\t\t"$(inherited)",\n\t\t\t\t)',
    "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
    "ONLY_ACTIVE_ARCH": "YES",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": '"DEBUG $(inherited)"',
    "SWIFT_OPTIMIZATION_LEVEL": '"-Onone"',
})
proj_release = dict(proj_common, **{
    "DEBUG_INFORMATION_FORMAT": '"dwarf-with-dsym"',
    "ENABLE_NS_ASSERTIONS": "NO",
    "MTL_ENABLE_DEBUG_INFO": "NO",
    "SWIFT_COMPILATION_MODE": "wholemodule",
    "SWIFT_OPTIMIZATION_LEVEL": '"-O"',
    "VALIDATE_PRODUCT": "YES",
})
target_common = {
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": "1",
    "DEVELOPMENT_TEAM": TEAM,
    "ENABLE_PREVIEWS": "YES",
    "GENERATE_INFOPLIST_FILE": "YES",
    "INFOPLIST_KEY_CFBundleDisplayName": "eng",
    "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
    "INFOPLIST_KEY_UISupportedInterfaceOrientations": '"UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight"',
    "IPHONEOS_DEPLOYMENT_TARGET": DEPLOYMENT_TARGET,
    "LD_RUNPATH_SEARCH_PATHS": '(\n\t\t\t\t\t"$(inherited)",\n\t\t\t\t\t"@executable_path/Frameworks",\n\t\t\t\t)',
    "MARKETING_VERSION": "1.0",
    "OTHER_LDFLAGS": '(\n\t\t\t\t\t"$(inherited)",\n\t\t\t\t\t"-lsqlite3",\n\t\t\t\t)',
    "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID,
    "PRODUCT_NAME": '"$(TARGET_NAME)"',
    "SWIFT_EMIT_LOC_STRINGS": "YES",
    "SWIFT_VERSION": "5.0",
    "TARGETED_DEVICE_FAMILY": "1",
}


def emit_config(cid, name, settings):
    body = "".join("\n\t\t\t\t%s = %s;" % (k, v) for k, v in settings.items())
    return ('\t\t%s /* %s */ = {isa = XCBuildConfiguration; buildSettings = {%s\n\t\t\t}; name = %s; };'
            % (cid, name, body, name))


lines.append("\n/* Begin XCBuildConfiguration section */")
lines.append(emit_config(ids["projdebug"], "Debug", proj_debug))
lines.append(emit_config(ids["projrelease"], "Release", proj_release))
lines.append(emit_config(ids["targetdebug"], "Debug", target_common))
lines.append(emit_config(ids["targetrelease"], "Release", target_common))
lines.append("/* End XCBuildConfiguration section */")

# XCConfigurationList
lines.append("\n/* Begin XCConfigurationList section */")
lines.append('\t\t%s /* Build configuration list for PBXProject */ = {isa = XCConfigurationList; buildConfigurations = (\n\t\t\t%s /* Debug */,\n\t\t\t%s /* Release */,\n\t\t); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; };'
             % (ids["projconflist"], ids["projdebug"], ids["projrelease"]))
lines.append('\t\t%s /* Build configuration list for PBXNativeTarget */ = {isa = XCConfigurationList; buildConfigurations = (\n\t\t\t%s /* Debug */,\n\t\t\t%s /* Release */,\n\t\t); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; };'
             % (ids["targetconflist"], ids["targetdebug"], ids["targetrelease"]))
lines.append("/* End XCConfigurationList section */")

lines.append("\t};")
lines.append("\trootObject = %s;" % ids["proj"])
lines.append("}")

os.makedirs(PROJ_DIR, exist_ok=True)
with open(os.path.join(PROJ_DIR, "project.pbxproj"), "w") as f:
    f.write("\n".join(lines) + "\n")

# Workspace metadata + a shared scheme so Xcode shows the run target immediately.
ws = os.path.join(PROJ_DIR, "project.xcworkspace")
os.makedirs(ws, exist_ok=True)
with open(os.path.join(ws, "contents.xcworkspacedata"), "w") as f:
    f.write('<?xml version="1.0" encoding="UTF-8"?>\n<Workspace version="1.0">\n'
            '   <FileRef location = "self:">\n   </FileRef>\n</Workspace>\n')

schemes = os.path.join(PROJ_DIR, "xcshareddata", "xcschemes")
os.makedirs(schemes, exist_ok=True)
scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "1540" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{ids['target']}" BuildableName = "eng.app" BlueprintName = "eng" ReferencedContainer = "container:Eng.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{ids['target']}" BuildableName = "eng.app" BlueprintName = "eng" ReferencedContainer = "container:Eng.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{ids['target']}" BuildableName = "eng.app" BlueprintName = "eng" ReferencedContainer = "container:Eng.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug"></AnalyzeAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES"></ArchiveAction>
</Scheme>
'''
with open(os.path.join(schemes, "eng.xcscheme"), "w") as f:
    f.write(scheme)

print("wrote %s (%d Swift files)" % (PROJ_DIR, len(swift)))
