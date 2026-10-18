#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

mkdir -p .build/tmp .build/cache

echo "🔨 Building PowerPresenter (Release)..."
if [ -d "/Applications/Xcode.app/Contents/Developer" ]; then
    DEV_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
else
    DEV_DIR="${DEVELOPER_DIR:-$(xcode-select -p 2>/dev/null)}"
fi
TMPDIR="${DIR}/.build/tmp" \
SWIFT_MODULE_CACHE_PATH="${DIR}/.build/cache" \
CLANG_MODULE_CACHE_PATH="${DIR}/.build/cache" \
DEVELOPER_DIR="${DEV_DIR}" \
swift build --disable-sandbox -c release

APP_DIR="${DIR}/PowerPresenter.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
ENTITLEMENTS_FILE="${DIR}/.build/tmp/PowerPresenter.entitlements"

mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

# Copy compiled executable
cp "${DIR}/.build/out/Products/Release/PowerPresenter" "${MACOS_DIR}/PowerPresenter"
chmod +x "${MACOS_DIR}/PowerPresenter"

# Write Info.plist with Apple Events permissions
cat << 'EOF' > "${CONTENTS_DIR}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>PowerPresenter</string>
    <key>CFBundleIdentifier</key>
    <string>com.powerpresenter.app</string>
    <key>CFBundleName</key>
    <string>PowerPresenter</string>
    <key>CFBundleDisplayName</key>
    <string>PowerPresenter</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>2.0.0</string>
    <key>CFBundleVersion</key>
    <string>2</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>PowerPresenter communicates with Microsoft PowerPoint when available to assist with slide rendering.</string>
</dict>
</plist>
EOF

cat << 'EOF' > "${ENTITLEMENTS_FILE}"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.automation.apple-events</key>
    <true/>
</dict>
</plist>
EOF

codesign --force --deep --sign - --entitlements "${ENTITLEMENTS_FILE}" "${APP_DIR}" 2>/dev/null || true

echo "✅ Successfully built and signed ${APP_DIR}!"
