#!/usr/bin/env bash
# Compila o PressStream e monta o bundle build/PressStream.app
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
APP="build/PressStream.app"

swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/PressStream" "$APP/Contents/MacOS/PressStream"
cp Support/Info.plist "$APP/Contents/Info.plist"

# Assinatura: usa um certificado "Apple Development" se existir (a permissão de
# gravação de tela continua valendo entre builds). Sem certificado, assina ad-hoc
# e o macOS pode pedir a permissão de novo depois de cada build.
IDENTITY="${SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | grep -m1 'Apple Development' | sed -E 's/.*"(.*)"/\1/' || true)"
fi
codesign --force --sign "${IDENTITY:--}" "$APP"

echo "✅ $APP pronto (assinado com: ${IDENTITY:-ad-hoc})"
