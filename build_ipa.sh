#!/usr/bin/env bash
#
# 生成「未签名 IPA」，用于全能签 / Sideloadly / AltStore 等第三方签名平台自签。
#
# 用法：
#   ./build_ipa.sh                          # 默认 Bundle ID (com.example.probe)
#   BUNDLE_ID=com.yourname.probe ./build_ipa.sh   # 自定义 Bundle ID
#
# 产物：build/Probe-unsigned.ipa
#
set -euo pipefail

cd "$(dirname "$0")"

SCHEME="Probe"
PROJECT="Probe.xcodeproj"
CONFIG="Release"
OUT_DIR="build"
ARCHIVE_PATH="$OUT_DIR/Probe.xcarchive"
IPA_NAME="Probe-unsigned.ipa"

if ! command -v xcodebuild >/dev/null 2>&1; then
    echo "错误：未找到 xcodebuild。iOS 应用必须在 macOS + Xcode 上编译。" >&2
    exit 1
fi

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

echo "==> [1/4] 编译（已完全关闭代码签名）"
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -sdk iphoneos \
    -destination "generic/platform=iOS" \
    -archivePath "$ARCHIVE_PATH" \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    DEVELOPMENT_TEAM="" \
    PROVISIONING_PROFILE_SPECIFIER="" \
    ${BUNDLE_ID:+PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID"} \
    clean archive \
    | tail -n 25

APP_PATH="$ARCHIVE_PATH/Products/Applications/$SCHEME.app"
if [ ! -d "$APP_PATH" ]; then
    echo "错误：未找到编译产物：$APP_PATH" >&2
    exit 1
fi

echo "==> [2/4] 清除签名残留（第三方平台要求干净的二进制）"
rm -rf "$APP_PATH/_CodeSignature"
rm -f  "$APP_PATH/embedded.mobileprovision"
find "$APP_PATH" -name "_CodeSignature" -type d -exec rm -rf {} + 2>/dev/null || true
find "$APP_PATH" -name "embedded.mobileprovision" -delete 2>/dev/null || true
/usr/bin/codesign --remove-signature "$APP_PATH" >/dev/null 2>&1 || true

# 校验：确认已无签名
if /usr/bin/codesign -dv "$APP_PATH" >/dev/null 2>&1; then
    echo "警告：仍检测到签名，已尝试移除，若签名失败请手动检查" >&2
else
    echo "    已确认：无签名"
fi

echo "==> [3/4] 打包为 IPA（Payload/ 结构）"
mkdir -p "$OUT_DIR/Payload"
cp -R "$APP_PATH" "$OUT_DIR/Payload/"
(cd "$OUT_DIR" && /usr/bin/zip -qry "$IPA_NAME" Payload)

echo "==> [4/4] 完成"
IPA_PATH="$OUT_DIR/$IPA_NAME"
ls -lh "$IPA_PATH" | awk '{print "    文件: " $9 "\n    大小: " $5}'
echo "    结构预览:"
unzip -l "$IPA_PATH" | head -n 12

echo ""
echo "把这个 IPA 直接拖进全能签即可签名安装。"
