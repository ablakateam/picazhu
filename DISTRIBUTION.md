# PICAZHU — Distribution & Signing Guide

_Reference for when a paid Apple Developer account is set up._

## Current state (ad-hoc)

| Property | Value |
|---|---|
| Bundle ID | `com.picazhu.mac` |
| Binary | Single Mach-O arm64, 8.5 MB |
| Linking | All static (GRDB, PicazhuKit modules) |
| Frameworks | None bundled — all system |
| System deps | Foundation, SwiftUI, AppKit, AVFoundation, Vision, ImageIO, CoreServices, CryptoKit, QuickLookThumbnailing, QuickLookUI, sqlite3 |
| Signing | Ad-hoc (`codesign --sign -`) |
| Hardened runtime | Yes (Release builds) |
| Sandbox | Yes |
| Min macOS | 15.0 Sequoia |
| Architecture | arm64 only |
| Gatekeeper | Blocked on first launch — requires right-click → Open |

## Step 1: Apple Developer Program

- Enroll at https://developer.apple.com/programs/ ($99/year)
- This gives you a **Developer ID Application** certificate for direct distribution
- Also gives **Mac App Store** distribution certificates if you want MAS later

## Step 2: Create signing identity

```bash
# After enrollment, Xcode auto-creates certificates.
# Verify your Developer ID cert exists:
security find-identity -v -p codesigning | grep "Developer ID Application"

# Expected output:
# 1) ABCDEF1234... "Developer ID Application: Your Name (TEAMID)"
```

## Step 3: Update Xcode project

In `PICAZHU.xcodeproj` build settings (both Debug and Release):

```
CODE_SIGN_STYLE = Manual
CODE_SIGN_IDENTITY = Developer ID Application
DEVELOPMENT_TEAM = <your 10-char Team ID>
PROVISIONING_PROFILE_SPECIFIER = (leave empty for Developer ID)
```

Or switch `CODE_SIGN_STYLE = Automatic` and set your team — Xcode handles the rest.

## Step 4: Build signed release

```bash
cd /Users/danglad/Desktop/PICAZHU

xcodebuild -project PICAZHU.xcodeproj \
  -scheme PICAZHU \
  -configuration Release \
  -derivedDataPath build/DerivedData \
  CODE_SIGN_IDENTITY="Developer ID Application" \
  DEVELOPMENT_TEAM="XXXXXXXXXX" \
  build

cp -R build/DerivedData/Build/Products/Release/PICAZHU.app build/PICAZHU.app
```

## Step 5: Notarize

Notarization is required for Developer ID distribution on macOS 10.15+. Without it, Gatekeeper blocks the app.

```bash
# Create a ZIP for notarization
ditto -c -k --keepParent build/PICAZHU.app build/PICAZHU.zip

# Submit for notarization
xcrun notarytool submit build/PICAZHU.zip \
  --apple-id "your@email.com" \
  --team-id "XXXXXXXXXX" \
  --password "app-specific-password" \
  --wait

# Staple the ticket to the app (so it works offline)
xcrun stapler staple build/PICAZHU.app
```

**App-specific password:** Generate at https://appleid.apple.com → Sign-In and Security → App-Specific Passwords.

**Typical notarization time:** 2–15 minutes. Apple scans for malware, checks entitlements, and validates code signing.

## Step 6: Create DMG for distribution

```bash
# Simple DMG
hdiutil create -volname "PICAZHU" \
  -srcfolder build/PICAZHU.app \
  -ov -format UDZO \
  build/PICAZHU.dmg

# Or use create-dmg for a pretty DMG with background image + Applications symlink:
# brew install create-dmg
create-dmg \
  --volname "PICAZHU" \
  --volicon "pikazhu_logo.icns" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 100 \
  --icon "PICAZHU.app" 150 200 \
  --app-drop-link 450 200 \
  --hide-extension "PICAZHU.app" \
  build/PICAZHU.dmg \
  build/PICAZHU.app
```

## Step 7: Universal binary (optional, for Intel Macs)

Currently arm64 only. To support Intel Macs:

```bash
# Build for both architectures
xcodebuild -project PICAZHU.xcodeproj \
  -scheme PICAZHU \
  -configuration Release \
  -destination 'platform=macOS,arch=x86_64' \
  -derivedDataPath build/DerivedData-x86 \
  build

xcodebuild -project PICAZHU.xcodeproj \
  -scheme PICAZHU \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/DerivedData-arm64 \
  build

# Lipo into universal binary
lipo -create \
  build/DerivedData-x86/Build/Products/Release/PICAZHU.app/Contents/MacOS/PICAZHU \
  build/DerivedData-arm64/Build/Products/Release/PICAZHU.app/Contents/MacOS/PICAZHU \
  -output build/PICAZHU.app/Contents/MacOS/PICAZHU

# Re-sign after lipo
codesign --force --sign "Developer ID Application: ..." \
  --entitlements App/PicazhuMacApp.entitlements \
  --options runtime \
  build/PICAZHU.app
```

Note: Ollama itself only supports Apple Silicon (M-series). So Intel Macs can browse but not do local AI.

## Step 8: Auto-update (future)

Options:

| Framework | Approach |
|---|---|
| **Sparkle** (recommended) | Add `github.com/sparkle-project/Sparkle` as SPM dep. Host an `appcast.xml` on GitHub Pages or S3. Sparkle checks for updates on launch, downloads DMG, replaces app in-place. Industry standard for non-MAS Mac apps. |
| **GitHub Releases** | Manual: user downloads new DMG from releases page. No auto-update. |
| **Mac App Store** | Full MAS submission. Apple handles updates. Requires strict sandbox compliance review. |

To add Sparkle:
1. Add to `Package.swift`: `.package(url: "https://github.com/sparkle-project/Sparkle", from: "2.0.0")`
2. Add `SUFeedURL` to Info.plist pointing to your appcast.xml
3. Add `SPUStandardUpdaterController` to the app delegate
4. Add entitlement: `com.apple.security.network.client` (already present)

## Mac App Store checklist (if pursuing MAS)

These items need attention for MAS review:

- [ ] Replace ad-hoc signing with MAS distribution certificate
- [ ] Add `com.apple.security.app-sandbox = YES` (already present)
- [ ] Remove `com.apple.security.network.client` if not needed (needed for Ollama)
- [ ] Verify no private API usage
- [ ] Add privacy descriptions in Info.plist for any protected resources
- [ ] Screenshots (1280×800 and 1440×900 minimum)
- [ ] App Store Connect metadata (description, category, keywords, support URL)
- [ ] Review Ollama dependency — MAS reviewers may flag it as requiring a third-party daemon. Consider making AI features fully optional with clear messaging.
- [ ] Test sandbox thoroughly — security-scoped bookmarks must work under strict MAS sandbox

## Entitlements reference

Current `App/PicazhuMacApp.entitlements`:

```xml
com.apple.security.app-sandbox = YES
com.apple.security.files.user-selected.read-only = YES
com.apple.security.files.bookmarks.app-scope = YES
com.apple.security.network.client = YES
```

These are the minimum required. No additional entitlements needed for Developer ID distribution. MAS may require justification for `network.client` (used for Ollama communication).

## Build automation script

Save as `scripts/build-release.sh`:

```bash
#!/bin/bash
set -e

TEAM_ID="${TEAM_ID:?Set TEAM_ID env var}"
APPLE_ID="${APPLE_ID:?Set APPLE_ID env var}"
APP_PASSWORD="${APP_PASSWORD:?Set APP_PASSWORD env var (app-specific password)}"

cd "$(dirname "$0")/.."

echo "Building..."
xcodebuild -project PICAZHU.xcodeproj \
  -scheme PICAZHU \
  -configuration Release \
  -derivedDataPath build/DerivedData \
  CODE_SIGN_IDENTITY="Developer ID Application" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  build

rm -rf build/PICAZHU.app
cp -R build/DerivedData/Build/Products/Release/PICAZHU.app build/PICAZHU.app

echo "Notarizing..."
ditto -c -k --keepParent build/PICAZHU.app build/PICAZHU.zip
xcrun notarytool submit build/PICAZHU.zip \
  --apple-id "$APPLE_ID" \
  --team-id "$TEAM_ID" \
  --password "$APP_PASSWORD" \
  --wait
xcrun stapler staple build/PICAZHU.app
rm build/PICAZHU.zip

echo "Creating DMG..."
rm -f build/PICAZHU.dmg
hdiutil create -volname "PICAZHU" \
  -srcfolder build/PICAZHU.app \
  -ov -format UDZO \
  build/PICAZHU.dmg

# Notarize the DMG too
xcrun notarytool submit build/PICAZHU.dmg \
  --apple-id "$APPLE_ID" \
  --team-id "$TEAM_ID" \
  --password "$APP_PASSWORD" \
  --wait
xcrun stapler staple build/PICAZHU.dmg

echo "Done: build/PICAZHU.dmg"
```

Usage:
```bash
TEAM_ID=XXXXXXXXXX APPLE_ID=you@email.com APP_PASSWORD=xxxx-xxxx-xxxx-xxxx bash scripts/build-release.sh
```

## Cost summary

| Item | Cost | Frequency |
|---|---|---|
| Apple Developer Program | $99 | Annual |
| Code signing certificate | Included | Auto-renews with membership |
| Notarization | Free | Per-submission |
| Hosting (GitHub Pages for appcast) | Free | — |
| Sparkle framework | Free (open source) | — |

## Quick reference: ad-hoc build (current, no developer account)

```bash
cd /Users/danglad/Desktop/PICAZHU
xcodebuild -project PICAZHU.xcodeproj -scheme PICAZHU \
  -configuration Release -derivedDataPath build/DerivedData build
rm -rf build/PICAZHU.app
cp -R build/DerivedData/Build/Products/Release/PICAZHU.app build/PICAZHU.app
xattr -dr com.apple.quarantine build/PICAZHU.app
open build/PICAZHU.app
```
