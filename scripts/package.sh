#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

echo "🔨 1. Building latest release binary..."
./scripts/build_app.sh

echo "📦 2. Creating macOS Disk Image (DMG)..."
DMG_STAGING=".build/dmg_staging"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"

cp -R PowerPresenter.app "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"
rm -f PowerPresenter.dmg

hdiutil create -volname "PowerPresenter" -srcfolder "$DMG_STAGING" -ov -format UDZO PowerPresenter.dmg
rm -rf "$DMG_STAGING"

echo "🤐 3. Creating ZIP distribution archive..."
rm -f PowerPresenter.zip
ditto -c -k --sequesterRsrc --keepParent PowerPresenter.app PowerPresenter.zip

echo "✨ Packaging Complete!"
echo "   - DMG installer: ${DIR}/PowerPresenter.dmg"
echo "   - ZIP archive:   ${DIR}/PowerPresenter.zip"
