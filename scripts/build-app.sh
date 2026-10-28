#!/bin/zsh
# Builds a universal, signed Tuck.app and zips it into .build/Tuck-<version>.zip.
#   scripts/build-app.sh 1.2.0
# Signs ad-hoc unless SIGN_IDENTITY is set (e.g. "Developer ID Application: …").
# Embeds Sparkle; its public EdDSA key is below, the private one is in the keychain (account "tuck") and the SPARKLE_ED_KEY secret.
# Notarizes and staples when NOTARY_KEY (path to the .p8), NOTARY_KEY_ID and NOTARY_ISSUER_ID are set.
set -euo pipefail
cd "${0:A:h}/.."

version=${1:?usage: build-app.sh <version>}
app=.build/Tuck.app
zip=.build/Tuck-$version.zip
icon=Sources/Tuck/Resources/AppIcon.icns

swift build -c release --arch arm64 --arch x86_64
bin=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)

rm -rf $app $zip
mkdir -p $app/Contents/{MacOS,Resources,Frameworks}
cp $bin/Tuck $app/Contents/MacOS/
[[ -f $icon ]] && cp $icon $app/Contents/Resources/
cp -R $bin/Sparkle.framework $app/Contents/Frameworks/
rm -rf $app/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices  # only sandboxed apps need them

cat > $app/Contents/Info.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Tuck</string>
    <key>CFBundleIdentifier</key><string>io.techtheory.tuck</string>
    <key>CFBundleName</key><string>Tuck</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$version</string>
    <key>CFBundleVersion</key><string>$version</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>SUFeedURL</key><string>https://github.com/techtheoryio/tuck/releases/latest/download/appcast.xml</string>
    <key>SUPublicEDKey</key><string>uuNJfkoXelzKBm3i9sDqZ3SOLqr+ka8KOYKgAGnEXuI=</string>
    <key>SUEnableAutomaticChecks</key><true/>
    <key>SUAutomaticallyUpdate</key><true/>
</dict>
</plist>
EOF

# Inside out, no --deep: Sparkle's helpers, the framework, then the app.
sparkle=$app/Contents/Frameworks/Sparkle.framework/Versions/B
if [[ -n ${SIGN_IDENTITY:-} ]]; then
    sign=(codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY")
else
    sign=(codesign --force --sign -)
fi
$sign $sparkle/Autoupdate $sparkle/Updater.app
$sign $app/Contents/Frameworks/Sparkle.framework
$sign $app
codesign --verify --strict --verbose=2 $app

# ditto, not zip: plain zip mangles the signature.
ditto -c -k --keepParent $app $zip

if [[ -n ${NOTARY_KEY:-} ]]; then
    xcrun notarytool submit $zip --key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID" --wait
    xcrun stapler staple $app
    rm $zip && ditto -c -k --keepParent $app $zip  # re-zip so the download carries the stapled ticket
fi

echo $zip
