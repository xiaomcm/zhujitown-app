#!/usr/bin/env bash
# 免开发者证书的 IPA：xcodebuild 编译不签名的 .app，再打 Payload.zip。
# 产出的 ipa 可用 AltStore / Sideloadly / 巨魔(TrollStore) 之类的工具签名后装到手机，
# 也可以在越狱机上直接安装。
#
# 用法（在 Mac 上）：
#   bash scripts/build_unsigned_ipa.sh
#
set -euo pipefail

cd "$(dirname "$0")/.."

PROJECT="ZhuJiTown.xcodeproj"
SCHEME="ZhuJiTown"
CONFIG="Release"
BUNDLE_ID="com.zhujitown.app"
VERSION="1.0.0"
BUILD_DIR="build"
OUT_DIR="outputs"

echo "==> 清理旧的编译产物"
rm -rf "$BUILD_DIR" "$OUT_DIR"
mkdir -p "$BUILD_DIR" "$OUT_DIR"

echo "==> 编译 iPhone 版 .app（不签名）"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$BUILD_DIR" \
  ONLY_ACTIVE_ARCH=NO \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  AD_HOC_CODE_SIGNING_ALLOWED=YES \
  SWIFT_COMPILATION_MODE=wholemodule \
  build 2>&1 | tail -25

APP=""
for cand in \
  "$BUILD_DIR/Build/Products/Release-iphoneos/$SCHEME.app" \
  "$BUILD_DIR/Build/Products/$CONFIG-iphoneos/$SCHEME.app"; do
  [ -d "$cand" ] && APP="$cand" && break
done

if [ -z "$APP" ]; then
  APP="$(find "$BUILD_DIR/Build/Products" -maxdepth 2 -type d -name '*.app' | head -n 1)"
fi

if [ -z "$APP" ] || [ ! -d "$APP" ]; then
  echo "!! 没有找到 .app，检查上面的 xcodebuild 输出"
  exit 1
fi

echo "==> 打包：$APP"
STAGE="$BUILD_DIR/ipa-stage"
rm -rf "$STAGE"
mkdir -p "$STAGE/Payload"
cp -R "$APP" "$STAGE/Payload/"

IPA="$OUT_DIR/ZhuJiTown-v${VERSION}-unsigned.ipa"
rm -f "$IPA"
(cd "$STAGE" && zip -qry "../../$IPA" Payload)

echo "==> 完成：$IPA"
ls -lh "$IPA"
echo
echo "下一步：用 AltStore / Sideloadly 选择这个 ipa 安装到你的 iPhone（它们会自动用你的 Apple ID 免费签名）。"
