#!/bin/bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
package_dir="$(cd -- "$script_dir/.." && pwd)"
repository_dir="$(cd -- "$package_dir/../.." && pwd)"
app_dir="$package_dir/dist/Grok Desktop.app"
grok_source="${GROK_BINARY:-$repository_dir/target/release/xai-grok-pager}"
if [[ "$grok_source" != /* ]]; then grok_source="$PWD/$grok_source"; fi
if [[ ! -f "$grok_source" || ! -x "$grok_source" ]]; then
    printf 'A bundled Grok executable is required: %s\nBuild the release harness first or set GROK_BINARY at build time.\n' "$grok_source" >&2
    exit 1
fi

swift "$script_dir/make-icon.swift" "$package_dir/Resources/AppIcon.icns" "$package_dir/Resources/GrokMark.svg"
swift build --package-path "$package_dir" --configuration release
binary_dir="$(swift build --package-path "$package_dir" --configuration release --show-bin-path)"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_dir/GrokDesktop" "$app_dir/Contents/MacOS/GrokDesktop"
chmod +x "$app_dir/Contents/MacOS/GrokDesktop"

cp "$grok_source" "$app_dir/Contents/Resources/grok"
chmod +x "$app_dir/Contents/Resources/grok"
/usr/bin/codesign --force --sign "${SIGN_IDENTITY:--}" "$app_dir/Contents/Resources/grok"
printf 'Bundled harness: %s\n' "$grok_source"
# Give changed artwork a new resource name so Finder and Dock can distinguish
# an in-place development rebuild from their cached icon for the same app.
icon_hash="$(/usr/bin/shasum -a 256 "$package_dir/Resources/AppIcon.icns" | /usr/bin/cut -c 1-12)"
icon_name="AppIcon-$icon_hash"
for stale_icon in "$app_dir/Contents/Resources"/AppIcon-*.icns; do
    if [[ -f "$stale_icon" ]]; then /bin/rm "$stale_icon"; fi
done
cp "$package_dir/Resources/AppIcon.icns" "$app_dir/Contents/Resources/$icon_name.icns"

cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleDisplayName</key><string>Grok Desktop</string>
    <key>CFBundleExecutable</key><string>GrokDesktop</string>
    <key>CFBundleIdentifier</key><string>ai.grok.build.desktop</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>Grok Desktop</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSMicrophoneUsageDescription</key><string>Grok Desktop uses the microphone only while you dictate a prompt.</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSSpeechRecognitionUsageDescription</key><string>When your account has no xAI voice credential, Grok Desktop transcribes your dictation on this Mac.</string>
</dict>
</plist>
PLIST

/usr/bin/plutil -replace CFBundleIconFile -string "$icon_name" "$app_dir/Contents/Info.plist"
/usr/bin/plutil -lint "$app_dir/Contents/Info.plist"
# Ad hoc signing makes the local app bundle self-contained. Set SIGN_IDENTITY to
# a Developer ID identity when producing a distributable (then notarize it).
/usr/bin/codesign --force --deep --sign "${SIGN_IDENTITY:--}" "$app_dir"
# Refresh only this bundle's registration; do not restart Dock or clear caches.
/usr/bin/touch "$app_dir"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app_dir"
printf 'Built %s\n' "$app_dir"
printf 'Launch with: open "%s"\n' "$app_dir"
