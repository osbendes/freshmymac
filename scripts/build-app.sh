#!/bin/zsh
# Release derlemesi yapıp build/FreshMyMac.app paketini (widget uzantısıyla birlikte) oluşturur.
#   ./scripts/build-app.sh            → build/FreshMyMac.app
#   ./scripts/build-app.sh --install  → ayrıca ~/Applications'a kurar ve widget'ı kaydeder
set -euo pipefail
cd "$(dirname "$0")/.."

# Kendi kimliğinizle derlemek için: BUNDLE_ID=com.ornek.FreshMyMac ./scripts/build-app.sh
BUNDLE_ID="${BUNDLE_ID:-com.osbendes.FreshMyMac}"
VERSION="0.2.0"
ARCH="$(uname -m)"
SDK="$(xcrun --show-sdk-path --sdk macosx)"
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
SDK_BUILD="$(xcrun --sdk macosx --show-sdk-build-version)"
XCODE_BUILD="$(xcodebuild -version | awk '/Build version/{print $3}')"
XCODE_VERSION="$(xcodebuild -version | awk '/^Xcode/{split($2,v,"."); printf "%d%d%02d", v[1]/10, v[1]%10, v[2]}')"

# Xcode'un her pakete eklediği platform anahtarları. ExtensionFoundation, uzantının
# türünü belirlerken bunlara bakıyor; eksik olunca widget açılışta çöküyor.
PLATFORM_KEYS="    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleDevelopmentRegion</key><string>tr</string>
    <key>CFBundleSupportedPlatforms</key><array><string>MacOSX</string></array>
    <key>DTPlatformName</key><string>macosx</string>
    <key>DTPlatformVersion</key><string>$SDK_VERSION</string>
    <key>DTPlatformBuild</key><string>$SDK_BUILD</string>
    <key>DTSDKName</key><string>macosx$SDK_VERSION</string>
    <key>DTSDKBuild</key><string>$SDK_BUILD</string>
    <key>DTXcode</key><string>$XCODE_VERSION</string>
    <key>DTXcodeBuild</key><string>$XCODE_BUILD</string>
    <key>DTCompiler</key><string>com.apple.compilers.llvm.clang.1_0</string>
    <key>BuildMachineOSBuild</key><string>$(sw_vers -buildVersion)</string>"

# İmza kimliği: SIGN_IDENTITY ile verilebilir; yoksa Keychain'deki ilk "Apple Development"
# sertifikası kullanılır. Hiçbiri yoksa ad-hoc imzalanır (widget galeride görünmez).
SIGN_ID="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | grep -m1 "Apple Development" | sed -E 's/.*"(.*)"/\1/' || true)}"
if [[ -z "$SIGN_ID" ]]; then
    SIGN_ID="-"
    echo "Uyarı: Apple Development sertifikası bulunamadı, ad-hoc imzalanıyor. Widget galeride görünmeyebilir."
else
    echo "İmza: $SIGN_ID"
fi

swift build -c release
BIN="$(swift build -c release --show-bin-path)/FreshMyMac"
APP="build/FreshMyMac.app"
WIDGET="$APP/Contents/PlugIns/FreshMyMacWidget.appex"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$WIDGET/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/FreshMyMac"
[[ -f Resources/AppIcon.icns ]] || swift scripts/make-icon.swift
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>FreshMyMac</string>
$PLATFORM_KEYS
    <key>CFBundleDisplayName</key><string>FreshMyMac</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>FreshMyMac</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>2</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key><string>$BUNDLE_ID</string>
            <key>CFBundleURLSchemes</key><array><string>freshmymac</string></array>
        </dict>
    </array>
</dict>
</plist>
PLIST

# --- Widget uzantısı ---
# Xcode uzantı hedefleri gibi: giriş noktası _NSExtensionMain olmalı; yoksa ExtensionFoundation
# uzantı türünü belirleyemez ve widget açılışta çöker.
# -emit-const-values-path: AppIntents metadata'sı için derleyicinin çıkardığı sabit değerler.
INTERMEDIATE="build/intermediates/widget"
mkdir -p "$INTERMEDIATE" "$WIDGET/Contents/Resources"
WIDGET_SOURCES=(Widget/*.swift Sources/FreshMyMac/Shared/*.swift)
printf '%s\n' '["AppIntent","AppEntity","AppEnum","TransientEntity","EntityQuery","DynamicOptionsProvider","AppShortcutsProvider","AppIntentsPackage","_IntentValueRepresentable","AnyResolverProviding","_AssistantIntentsProvider"]' > "$INTERMEDIATE/protocols.json"

swiftc -O -wmo -parse-as-library -module-name FreshMyMacWidget -application-extension \
    -target "$ARCH-apple-macos14.0" -sdk "$SDK" \
    -emit-const-values-path "$INTERMEDIATE/FreshMyMacWidget.swiftconstvalues" \
    -Xfrontend -const-gather-protocols-file -Xfrontend "$INTERMEDIATE/protocols.json" \
    -Xlinker -e -Xlinker _NSExtensionMain -Xlinker -application_extension \
    "${WIDGET_SOURCES[@]}" \
    -o "$WIDGET/Contents/MacOS/FreshMyMacWidget"

# Widget'taki seçim kutuları (AppIntent) için Xcode'un ürettiği Metadata.appintents paketi.
printf '%s\n' "${WIDGET_SOURCES[@]:A}" > "$INTERMEDIATE/sources.txt"
echo "$PWD/$INTERMEDIATE/FreshMyMacWidget.swiftconstvalues" > "$INTERMEDIATE/constvalues.txt"
xcrun appintentsmetadataprocessor \
    --output "$WIDGET/Contents/Resources" \
    --toolchain-dir "$(dirname "$(dirname "$(dirname "$(xcrun -f swiftc)")")")" \
    --module-name FreshMyMacWidget \
    --sdk-root "$SDK" \
    --xcode-version "$XCODE_BUILD" \
    --platform-family macOS \
    --deployment-target 14.0 \
    --bundle-identifier "$BUNDLE_ID.Widget" \
    --target-triple "$ARCH-apple-macos14.0" \
    --binary-file "$WIDGET/Contents/MacOS/FreshMyMacWidget" \
    --source-file-list "$INTERMEDIATE/sources.txt" \
    --swift-const-vals-list "$INTERMEDIATE/constvalues.txt" \
    --force

cat > "$WIDGET/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>FreshMyMacWidget</string>
$PLATFORM_KEYS
    <key>CFBundleDisplayName</key><string>FreshMyMac</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID.Widget</string>
    <key>CFBundleExecutable</key><string>FreshMyMacWidget</string>
    <key>CFBundlePackageType</key><string>XPC!</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>2</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSExtension</key>
    <dict>
        <key>NSExtensionPointIdentifier</key><string>com.apple.widgetkit-extension</string>
    </dict>
</dict>
</plist>
PLIST

# İç paket önce, dış paket sonra imzalanır.
codesign --force --sign "$SIGN_ID" --timestamp=none --entitlements Widget/FreshMyMacWidget.entitlements "$WIDGET"
codesign --force --sign "$SIGN_ID" --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"
echo "Hazır: $APP"

if [[ "${1:-}" == "--install" ]]; then
    DEST="$HOME/Applications/FreshMyMac.app"
    mkdir -p "$HOME/Applications"
    pkill -x FreshMyMac 2>/dev/null || true
    rm -rf "$DEST"
    cp -R "$APP" "$DEST"
    LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
    # Widget'taki freshmymac:// adresleri derleme kopyasını değil kurulu kopyayı açsın.
    "$LSREGISTER" -u "$APP" 2>/dev/null || true
    "$LSREGISTER" -f "$DEST"
    pluginkit -a "$DEST/Contents/PlugIns/FreshMyMacWidget.appex"
    # Widget galerisinin yeni imzayı görmesi için widget sunucusunu yeniden başlat (kendiliğinden açılır).
    killall chronod 2>/dev/null || true
    echo "Kuruldu: $DEST"
fi
