#!/usr/bin/env bash
# 打包 WorkTimeRecorder.app 到 dist/。
# 用法：./scripts/build_app.sh [release|debug]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIG="${1:-release}"
echo "==> 构建（${CONFIG}）"
swift build -c "$CONFIG" --product WorkTimeRecorder

BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
BIN="$BIN_DIR/WorkTimeRecorder"

echo "==> 生成应用图标"
"$BIN" --render-icons "$ROOT/Assets"
iconutil -c icns "$ROOT/Assets/AppIcon.iconset" -o "$ROOT/Assets/AppIcon.icns"

echo "==> 组装 .app"
APP="$ROOT/dist/WorkTimeRecorder.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/WorkTimeRecorder"
cp "$ROOT/Assets/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$ROOT/Assets/Info.plist" "$APP/Contents/Info.plist"
chmod +x "$APP/Contents/MacOS/WorkTimeRecorder"

if command -v codesign >/dev/null 2>&1; then
  codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 || echo "（ad-hoc 签名跳过，本地可直接运行）"
fi

echo "==> 自检"
"$APP/Contents/MacOS/WorkTimeRecorder" --self-check

echo "完成：$APP"
