#!/usr/bin/env bash
# 用你自己的 Apple 开发者证书导出正式签名的 IPA。
#
# 前置：Mac 上 Xcode 已登录 Apple ID / 已导入开发证书。
# 用法：
#   bash scripts/build_signed_ipa.sh [development|adhoc|appstore]
#
set -euo pipefail

MODE="${1:-development}"

cd "$(dirname "$0")/.."

PROJECT="ZhuJiTown.xcodeproj"
SCHEME="ZhuJiTown"
BUNDLE_ID="com.zhujitown.app"
VERSION="1.0.0"
BUILD_DIR="build"
ARCHIVE="$BUILD_DIR/$SCHEME.xcarchive"
OUT_DIR="outputs"

case "$MODE" in
  development) EXPORT_PLIST="ExportOptions-Development.plist"; SUFFIX="dev" ;;
  adhoc)       EXPORT_PLIST="ExportOptions-AdHoc.plist";       SUFFIX="adhoc" ;;
  appstore)    EXPORT_PLIST="ExportOptions-AppStore.plist";    SUFFIX="appstore" ;;
  *) echo "未知模式：$MODE（可选 development / adhoc / appstore）"; exit 1 ;;
esac

mkdir -p "$BUILD_DIR" "$OUT_DIR"

# 没填 provisioningProfiles 名字时用纯自动签名更高效；这里允许用环境变量覆盖 teamID（如 -arch x86_64 CI）
if [ -n "${TEAM_ID:-}" ]; then
  REAL_PLIST="$BUILD_DIR/$(basename "$EXPORT_PLIST" .plist)-filled.plist"
  sed "s/YOUR_TEAM_ID/${TEAM_ID}/g" "$EXPORT_PLIST" > "$REAL_PLIST"
  EXPORT_PLIST="$REAL_PLIST"
  echo "==> 使用 teamID：${TEAM_ID}"
fi

echo "==> 1/2 Archive（$MODE）"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  archive 2>&1 | tail -25

echo "==> 2/2 导出 IPA"
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$EXPORT_PLIST" \
  -exportPath "$OUT_DIR/$MODE" \
  -allowProvisioningUpdates 2>&1 | tail -20

echo
echo "==> 产物目录：$OUT_DIR/$MODE"
find "$OUT_DIR/$MODE" -name '*.ipa' -maxdepth 1 2>/dev/null | head
echo "提示：如果你在 Xcode 里改了 Bundle Identifier，需要同步修改 $EXPORT_PLIST 与 Info.plist。"
