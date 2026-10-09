# -*- coding: utf-8 -*-
"""
生成 ZhuJiTown.xcodeproj（标准 Xcode 工程，不依赖 xcodegen / CocoaPods / SwiftPM）。
用法： python3 scripts/make_xcodeproj.py
扫描 ZhuJiTown/ 下的 Swift 源文件与资源，自动写入工程文件。
"""
import os
import re
import struct
import zlib
import hashlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP_DIR = os.path.join(ROOT, "ZhuJiTown")
OUT_DIR = os.path.join(ROOT, "ZhuJiTown.xcodeproj")
PROJECT_NAME = "ZhuJiTown"
BUNDLE_ID = "com.zhujitown.app"
TEAM_MARKER = ""  # 留空则由 Xcode / xcodebuild 自动选择
DEPLOY_TARGET = "16.0"
SWIFT_VERSION = "5.0"

SUB_DIRS = ["App", "Model", "Network", "Parser", "ViewModel", "UI"]
RESOURCE_DIR = "Resources"


def obj_id(seed: str) -> str:
    """稳定 24 位十六进制 ID"""
    h = hashlib.sha1(seed.encode("utf-8")).hexdigest().upper()
    return h[:24]


def indent(text: str, level: int = 1) -> str:
    pad = "\t" * level
    return "\n".join(pad + line if line else "" for line in text.split("\n"))


def collect_sources():
    groups = []
    for sub in SUB_DIRS:
        path = os.path.join(APP_DIR, sub)
        if not os.path.isdir(path):
            continue
        files = sorted(f for f in os.listdir(path) if f.endswith(".swift"))
        if files:
            groups.append((sub, sub, files))
    return groups


# ---------------------------------------------------------------- AppIcon 生成

def write_png(path: str, size: int, top=(255, 138, 61), bottom=(240, 78, 40)):
    """手写 PNG：竖向渐变的不透明方块（AppIcon 不能有 alpha）"""
    rows = []
    for y in range(size):
        t = y / max(size - 1, 1)
        r = int(top[0] + (bottom[0] - top[0]) * t)
        g = int(top[1] + (bottom[1] - top[1]) * t)
        b = int(top[2] + (bottom[2] - top[2]) * t)
        row = bytearray([0])  # filter type 0
        row += bytes([r, g, b]) * size
        rows.append(bytes(row))
    raw = b"".join(rows)

    def chunk(tag: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(png)


# (文件名, idiom, size(点), scale) → 对应像素 = 点 × 倍率
IPHONE_MAP = [
    ("icon-iphone-20@2x.png", "iphone", "20x20", "2x"),
    ("icon-iphone-20@3x.png", "iphone", "20x20", "3x"),
    ("icon-iphone-29@2x.png", "iphone", "29x29", "2x"),
    ("icon-iphone-29@3x.png", "iphone", "29x29", "3x"),
    ("icon-iphone-40@2x.png", "iphone", "40x40", "2x"),
    ("icon-iphone-40@3x.png", "iphone", "40x40", "3x"),
    ("icon-iphone-60@2x.png", "iphone", "60x60", "2x"),
    ("icon-iphone-60@3x.png", "iphone", "60x60", "3x"),
    ("icon-ipad-20@1x.png", "ipad", "20x20", "1x"),
    ("icon-ipad-20@2x.png", "ipad", "20x20", "2x"),
    ("icon-ipad-29@1x.png", "ipad", "29x29", "1x"),
    ("icon-ipad-29@2x.png", "ipad", "29x29", "2x"),
    ("icon-ipad-40@1x.png", "ipad", "40x40", "1x"),
    ("icon-ipad-40@2x.png", "ipad", "40x40", "2x"),
    ("icon-ipad-76@1x.png", "ipad", "76x76", "1x"),
    ("icon-ipad-76@2x.png", "ipad", "76x76", "2x"),
    ("icon-ipad-83.5@2x.png", "ipad", "83.5x83.5", "2x"),
    ("icon-store-1024.png", "ios-marketing", "1024x1024", "1x"),
]


def px_of(size: str, scale: str) -> int:
    return int(round(float(size.split("x")[0]) * float(scale.rstrip("x"))))


def ensure_assets():
    assets = os.path.join(APP_DIR, RESOURCE_DIR, "Assets.xcassets")
    icon_dir = os.path.join(assets, "AppIcon.appiconset")
    os.makedirs(icon_dir, exist_ok=True)

    for fn, idiom, size, scale in IPHONE_MAP:
        write_png(os.path.join(icon_dir, fn), px_of(size, scale))

    images = "\n".join(
        '      {\n        "filename" : "%s",\n        "idiom" : "%s",\n'
        '        "scale" : "%s",\n        "size" : "%s"\n      }%s'
        % (fn, idiom, scale, size, "," if i < len(IPHONE_MAP) - 1 else "")
        for i, (fn, idiom, size, scale) in enumerate(IPHONE_MAP)
    )
    appicon_json = (
        '{\n  "images" : [\n%s\n  ],\n  "info" : {\n'
        '    "author" : "xcode",\n    "version" : 1\n  }\n}\n' % images
    )
    with open(os.path.join(icon_dir, "Contents.json"), "w", encoding="utf-8") as f:
        f.write(appicon_json)

    accent = (
        '{\n  "colors" : [\n    {\n      "idiom" : "universal"\n    }\n  ],\n'
        '  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  }\n}\n'
    )
    accent_dir = os.path.join(assets, "AccentColor.colorset")
    os.makedirs(accent_dir, exist_ok=True)
    with open(os.path.join(accent_dir, "Contents.json"), "w", encoding="utf-8") as f:
        f.write(accent)

    root_json = (
        '{\n  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  }\n}\n'
    )
    with open(os.path.join(assets, "Contents.json"), "w", encoding="utf-8") as f:
        f.write(root_json)
    return assets


# ---------------------------------------------------------------- Info.plist

INFO_PLIST = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>zh_CN</string>
	<key>CFBundleDisplayName</key>
	<string>主机镇</string>
	<key>CFBundleExecutable</key>
	<string>$(EXECUTABLE_NAME)</string>
	<key>CFBundleIdentifier</key>
	<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
	<key>CFBundleName</key>
	<string>$(PRODUCT_NAME)</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>CFBundleURLTypes</key>
	<array>
		<dict>
			<key>CFBundleTypeRole</key>
			<string>Viewer</string>
			<key>CFBundleURLName</key>
			<string>com.zhujitown.app</string>
			<key>CFBundleURLSchemes</key>
			<array>
				<string>zhujitown</string>
			</array>
		</dict>
	</array>
	<key>ITSAppUsesNonExemptEncryption</key>
	<false/>
	<key>LSRequiresIPhoneOS</key>
	<true/>
	<key>NSAppTransportSecurity</key>
	<dict>
		<key>NSAllowsArbitraryLoads</key>
		<true/>
	</dict>
	<key>UIAppSupportsIndirectInputEvents</key>
	<true/>
	<key>UILaunchScreen</key>
	<dict/>
	<key>UIRequiredDeviceCapabilities</key>
	<array>
		<string>arm64</string>
	</array>
	<key>UISupportedInterfaceOrientations</key>
	<array>
		<string>UIInterfaceOrientationPortrait</string>
	</array>
	<key>UISupportedInterfaceOrientations~ipad</key>
	<array>
		<string>UIInterfaceOrientationPortrait</string>
		<string>UIInterfaceOrientationPortraitUpsideDown</string>
		<string>UIInterfaceOrientationLandscapeLeft</string>
		<string>UIInterfaceOrientationLandscapeRight</string>
	</array>
</dict>
</plist>
"""


def ensure_info_plist():
    path = os.path.join(APP_DIR, "Info.plist")
    with open(path, "w", encoding="utf-8") as f:
        f.write(INFO_PLIST)
    return path


# ---------------------------------------------------------------- pbxproj

def build_pbxproj(sources):
    project_ref = obj_id("project")
    target_ref = obj_id("target")
    main_group_ref = obj_id("group-main")
    products_group_ref = obj_id("group-products")
    app_group_ref = obj_id("group-app")
    app_file_ref = obj_id("file-app-product")
    info_ref = obj_id("file-info-plist")
    assets_ref = obj_id("file-assets")

    project_conf_list = obj_id("conflist-project")
    target_conf_list = obj_id("conflist-target")
    conf_project_debug = obj_id("conf-project-debug")
    conf_project_release = obj_id("conf-project-release")
    conf_target_debug = obj_id("conf-target-debug")
    conf_target_release = obj_id("conf-target-release")
    sources_phase = obj_id("phase-sources")
    frameworks_phase = obj_id("phase-frameworks")
    resources_phase = obj_id("phase-resources")

    lines = []
    a = lines.append

    a("// !$*UTF8*$!")
    a("{")
    a("\tarchiveVersion = 1;")
    a("\tclasses = {")
    a("\t};")
    a("\tobjectVersion = 56;")
    a("\tobjects = {")

    # ---- PBXBuildFile
    a("")
    a("/* Begin PBXBuildFile section */")
    for folder, _, files in sources:
        for f in files:
            file_id = obj_id("file-%s-%s" % (folder, f))
            a("\t\t%s /* %s in Sources */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };"
              % (obj_id("build-%s-%s" % (folder, f)), f, file_id, f))
    a("\t\t%s /* Assets.xcassets in Resources */ = {isa = PBXBuildFile; fileRef = %s /* Assets.xcassets */; };"
      % (obj_id("build-assets"), assets_ref))
    a("/* End PBXBuildFile section */")

    # ---- PBXFileReference
    a("")
    a("/* Begin PBXFileReference section */")
    a("\t\t%s /* %s.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = %s.app; sourceTree = BUILT_PRODUCTS_DIR; };"
      % (app_file_ref, PROJECT_NAME, PROJECT_NAME))
    a("\t\t%s /* Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = \"<group>\"; };"
      % info_ref)
    a("\t\t%s /* Assets.xcassets */ = {isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = \"<group>\"; };"
      % assets_ref)
    for folder, _, files in sources:
        for f in files:
            file_id = obj_id("file-%s-%s" % (folder, f))
            a("\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = %s; sourceTree = \"<group>\"; };"
              % (file_id, f, f))
    a("/* End PBXFileReference section */")

    # ---- PBXFrameworksBuildPhase
    a("")
    a("/* Begin PBXFrameworksBuildPhase section */")
    a("\t\t%s /* Frameworks */ = {\n\t\t\tisa = PBXFrameworksBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};" % frameworks_phase)
    a("/* End PBXFrameworksBuildPhase section */")

    # ---- PBXGroup
    a("")
    a("/* Begin PBXGroup section */")
    a("\t\t%s = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\t%s /* %s */,\n\t\t\t\t%s /* Products */,\n\t\t\t);\n\t\t\tsourceTree = \"<group>\";\n\t\t};"
      % (main_group_ref, app_group_ref, PROJECT_NAME, products_group_ref))

    children_lines = []
    for folder, _, files in sources:
        group_id = obj_id("group-%s" % folder)
        file_ids = "\n".join(
            "\t\t\t\t\t%s /* %s */," % (obj_id("file-%s-%s" % (folder, f)), f)
            for f in files
        )
        a("\t\t%s /* %s */ = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n%s\n\t\t\t);\n\t\t\tpath = %s;\n\t\t\tsourceTree = \"<group>\";\n\t\t};"
          % (group_id, folder, file_ids, folder))
        children_lines.append("\t\t\t\t%s /* %s */," % (group_id, folder))
    children_lines.append("\t\t\t\t%s /* Resources */," % obj_id("group-Resources"))

    a("\t\t%s /* %s */ = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n%s\n\t\t\t\t%s /* Info.plist */,\n\t\t\t);\n\t\t\tpath = %s;\n\t\t\tsourceTree = \"<group>\";\n\t\t};"
      % (app_group_ref, PROJECT_NAME, "\n".join(children_lines), info_ref, PROJECT_NAME))

    a("\t\t%s /* Resources */ = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\t%s /* Assets.xcassets */,\n\t\t\t);\n\t\t\tpath = Resources;\n\t\t\tsourceTree = \"<group>\";\n\t\t};"
      % (obj_id("group-Resources"), assets_ref))

    a("\t\t%s /* Products */ = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\t%s /* %s.app */,\n\t\t\t);\n\t\t\tname = Products;\n\t\t\tsourceTree = \"<group>\";\n\t\t};"
      % (products_group_ref, app_file_ref, PROJECT_NAME))
    a("/* End PBXGroup section */")

    # ---- PBXNativeTarget
    a("")
    a("/* Begin PBXNativeTarget section */")
    team_attr = "\n\t\t\t\t\tProvisioningStyle = Automatic;"
    a("\t\t%s /* %s */ = {\n\t\t\tisa = PBXNativeTarget;\n\t\t\tbuildConfigurationList = %s /* Build configuration list for PBXNativeTarget \"%s\" */;\n\t\t\tbuildPhases = (\n\t\t\t\t%s /* Sources */,\n\t\t\t\t%s /* Frameworks */,\n\t\t\t\t%s /* Resources */,\n\t\t\t);\n\t\t\tbuildRules = (\n\t\t\t);\n\t\t\tdependencies = (\n\t\t\t);\n\t\t\tname = %s;\n\t\t\tproductName = %s;\n\t\t\tproductReference = %s /* %s.app */;\n\t\t\tproductType = \"com.apple.product-type.application\";\n\t\t};"
      % (target_ref, PROJECT_NAME, target_conf_list, PROJECT_NAME,
         sources_phase, frameworks_phase, resources_phase,
         PROJECT_NAME, PROJECT_NAME, app_file_ref, PROJECT_NAME))
    a("/* End PBXNativeTarget section */")

    # ---- PBXProject
    a("")
    a("/* Begin PBXProject section */")
    a("\t\t%s /* Project object */ = {\n\t\t\tisa = PBXProject;\n\t\t\tattributes = {\n\t\t\t\tBuildIndependentTargetsInParallel = 1;\n\t\t\t\tLastSwiftUpdateCheck = 1520;\n\t\t\t\tLastUpgradeCheck = 1520;\n\t\t\t\tTargetAttributes = {\n\t\t\t\t\t%s = {\n\t\t\t\t\t\tCreatedOnToolsVersion = 15.2;\n%s\n\t\t\t\t\t};\n\t\t\t\t};\n\t\t\t};\n\t\t\tbuildConfigurationList = %s /* Build configuration list for PBXProject \"%s\" */;\n\t\t\tcompatibilityVersion = \"Xcode 14.0\";\n\t\t\tdevelopmentRegion = zh_CN;\n\t\t\thasScannedForEncodings = 0;\n\t\t\tknownRegions = (\n\t\t\t\ten,\n\t\t\t\tBase,\n\t\t\t\tzh_CN,\n\t\t\t);\n\t\t\tmainGroup = %s;\n\t\t\tproductRefGroup = %s /* Products */;\n\t\t\tprojectDirPath = \"\";\n\t\t\tprojectRoot = \"\";\n\t\t\ttargets = (\n\t\t\t\t%s /* %s */,\n\t\t\t);\n\t\t};"
      % (project_ref, target_ref, team_attr.strip("\n"), project_conf_list,
         PROJECT_NAME, main_group_ref, products_group_ref, target_ref, PROJECT_NAME))
    a("/* End PBXProject section */")

    # ---- PBXResourcesBuildPhase
    a("")
    a("/* Begin PBXResourcesBuildPhase section */")
    a("\t\t%s /* Resources */ = {\n\t\t\tisa = PBXResourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t\t%s /* Assets.xcassets in Resources */,\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};"
      % (resources_phase, obj_id("build-assets")))
    a("/* End PBXResourcesBuildPhase section */")

    # ---- PBXSourcesBuildPhase
    a("")
    a("/* Begin PBXSourcesBuildPhase section */")
    src_lines = "\n".join(
        "\t\t\t\t%s /* %s in Sources */," % (obj_id("build-%s-%s" % (folder, f)), f)
        for folder, _, files in sources for f in files
    )
    a("\t\t%s /* Sources */ = {\n\t\t\tisa = PBXSourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n%s\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};"
      % (sources_phase, src_lines))
    a("/* End PBXSourcesBuildPhase section */")

    # ---- XCBuildConfiguration
    a("")
    a("/* Begin XCBuildConfiguration section */")

    project_common = {
        "ALWAYS_SEARCH_USER_PATHS": "NO",
        "CLANG_ANALYZER_NONNULL": "YES",
        "CLANG_ENABLE_MODULES": "YES",
        "CLANG_ENABLE_OBJC_ARC": "YES",
        "COPY_PHASE_STRIP": "NO",
        "ENABLE_STRICT_OBJC_MSGSEND": "YES",
        "GCC_C_LANGUAGE_STANDARD": "gnu11",
        "GCC_NO_COMMON_BLOCKS": "YES",
        "IPHONEOS_DEPLOYMENT_TARGET": DEPLOY_TARGET,
        "SDKROOT": "iphoneos",
        "SUPPORTED_PLATFORMS": '"iphoneos iphonesimulator"',
        "SWIFT_VERSION": SWIFT_VERSION,
    }
    project_debug = dict(project_common)
    project_debug.update({
        "DEBUG_INFORMATION_FORMAT": "dwarf",
        "ENABLE_TESTABILITY": "YES",
        "GCC_OPTIMIZATION_LEVEL": "0",
        "GCC_PREPROCESSOR_DEFINITIONS": '(\n\t\t\t\t\t"DEBUG=1",\n\t\t\t\t\t"$(inherited)",\n\t\t\t\t)',
        "ONLY_ACTIVE_ARCH": "YES",
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": '"DEBUG $(inherited)"',
        "SWIFT_OPTIMIZATION_LEVEL": '"-Onone"',
    })
    project_release = dict(project_common)
    project_release.update({
        "DEBUG_INFORMATION_FORMAT": '"dwarf-with-dsym"',
        "ENABLE_NS_ASSERTIONS": "NO",
        "SWIFT_COMPILATION_MODE": "wholemodule",
        "SWIFT_OPTIMIZATION_LEVEL": '"-O"',
        "VALIDATE_PRODUCT": "YES",
    })

    target_common = {
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
        "CODE_SIGN_STYLE": "Automatic",
        "CURRENT_PROJECT_VERSION": "1",
        "GENERATE_INFOPLIST_FILE": "NO",
        "INFOPLIST_FILE": "ZhuJiTown/Info.plist",
        "LD_RUNPATH_SEARCH_PATHS": '(\n\t\t\t\t\t"@executable_path/Frameworks",\n\t\t\t\t)',
        "MARKETING_VERSION": "1.0.0",
        "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID,
        "PRODUCT_NAME": "$(TARGET_NAME)",
        "SWIFT_EMIT_LOC_STRINGS": "YES",
        "SWIFT_VERSION": SWIFT_VERSION,
        "TARGETED_DEVICE_FAMILY": '"1,2"',
    }
    if TEAM_MARKER:
        target_common["DEVELOPMENT_TEAM"] = TEAM_MARKER

    target_debug = dict(target_common)
    target_release = dict(target_common)
    target_debug["CODE_SIGN_IDENTITY"] = '"Apple Development"'
    target_release["CODE_SIGN_IDENTITY"] = '"Apple Development"'

    def conf_block(ref, name, settings, is_target):
        body = "\n".join(
            "\t\t\t\t%s = %s;" % (k, v) for k, v in sorted(settings.items())
        )
        return (
            "\t\t%s /* %s */ = {\n\t\t\tisa = XCBuildConfiguration;\n"
            "\t\t\tbuildSettings = {\n%s\n\t\t\t};\n\t\t\tname = %s;\n\t\t};"
            % (ref, name, body, name)
        )

    a(conf_block(conf_project_debug, "Debug", project_debug, False))
    a(conf_block(conf_project_release, "Release", project_release, False))
    a(conf_block(conf_target_debug, "Debug", target_debug, True))
    a(conf_block(conf_target_release, "Release", target_release, True))
    a("/* End XCBuildConfiguration section */")

    # ---- XCConfigurationList
    a("")
    a("/* Begin XCConfigurationList section */")
    a("\t\t%s /* Build configuration list for PBXProject \"%s\" */ = {\n\t\t\tisa = XCConfigurationList;\n\t\t\tbuildConfigurations = (\n\t\t\t\t%s /* Debug */,\n\t\t\t\t%s /* Release */,\n\t\t\t);\n\t\t\tdefaultConfigurationIsVisible = 0;\n\t\t\tdefaultConfigurationName = Release;\n\t\t};"
      % (project_conf_list, PROJECT_NAME, conf_project_debug, conf_project_release))
    a("\t\t%s /* Build configuration list for PBXNativeTarget \"%s\" */ = {\n\t\t\tisa = XCConfigurationList;\n\t\t\tbuildConfigurations = (\n\t\t\t\t%s /* Debug */,\n\t\t\t\t%s /* Release */,\n\t\t\t);\n\t\t\tdefaultConfigurationIsVisible = 0;\n\t\t\tdefaultConfigurationName = Release;\n\t\t};"
      % (target_conf_list, PROJECT_NAME, conf_target_debug, conf_target_release))
    a("/* End XCConfigurationList section */")

    a("\t};")
    a("\trootObject = %s /* Project object */;" % project_ref)
    a("}")
    return "\n".join(lines) + "\n"


SCHEME_TEMPLATE = """<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1520"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "%(target)s"
               BuildableName = "%(name)s.app"
               BlueprintName = "%(name)s"
               ReferencedContainer = "container:%(name)s.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "%(target)s"
            BuildableName = "%(name)s.app"
            BlueprintName = "%(name)s"
            ReferencedContainer = "container:%(name)s.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "%(target)s"
            BuildableName = "%(name)s.app"
            BlueprintName = "%(name)s"
            ReferencedContainer = "container:%(name)s.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""


def ensure_scheme(target_ref: str):
    scheme_dir = os.path.join(OUT_DIR, "xcshareddata", "xcschemes")
    os.makedirs(scheme_dir, exist_ok=True)
    path = os.path.join(scheme_dir, "%s.xcscheme" % PROJECT_NAME)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(SCHEME_TEMPLATE % {"target": target_ref, "name": PROJECT_NAME})
    return path


def main():
    sources = collect_sources()
    total = sum(len(f) for _, _, f in sources)
    print("Swift 源文件：%d 个" % total)

    assets = ensure_assets()
    print("资源：%s" % os.path.relpath(assets, ROOT))

    info = ensure_info_plist()
    print("Info.plist：%s" % os.path.relpath(info, ROOT))

    os.makedirs(OUT_DIR, exist_ok=True)
    pbx = build_pbxproj(sources)
    pbx_path = os.path.join(OUT_DIR, "project.pbxproj")
    with open(pbx_path, "w", encoding="utf-8", newline="\n") as f:
        f.write(pbx)
    print("工程：%s (%d 字节)" % (os.path.relpath(pbx_path, ROOT), len(pbx)))

    # scheme：命令行 xcodebuild archive 必须要有
    import xml.etree.ElementTree as ET
    scheme_path = ensure_scheme(obj_id("target"))
    ET.parse(scheme_path)  # XML 合法性校验
    try:
        ET.parse(os.path.join(APP_DIR, "Info.plist"))
    except ET.ParseError as e:
        print("Info.plist XML 错误：%s" % e)
    print("Scheme：%s" % os.path.relpath(scheme_path, ROOT))

    # 校验大括号平衡 + 对象数
    assert pbx.count("{") == pbx.count("}"), "pbxproj 大括号不平衡"
    print("校验通过：大括号平衡，对象 %d 个" % pbx.count("= {"))


if __name__ == "__main__":
    main()
