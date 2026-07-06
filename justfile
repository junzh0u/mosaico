sim := "iPhone 17"
bundle_id := "info.junz.mosaico"

generate:
    xcodegen generate

build: generate
    xcodebuild -project Mosaico.xcodeproj -scheme Mosaico \
      -destination 'platform=iOS Simulator,name={{sim}}' \
      -derivedDataPath build build

run: build
    xcrun simctl boot "{{sim}}" 2>/dev/null || true
    open -a Simulator
    xcrun simctl install "{{sim}}" build/Build/Products/Debug-iphonesimulator/Mosaico.app
    xcrun simctl launch "{{sim}}" {{bundle_id}}

build-device: generate
    xcodebuild -project Mosaico.xcodeproj -scheme Mosaico \
      -destination 'generic/platform=iOS' \
      -derivedDataPath build -allowProvisioningUpdates build

run-device: build-device
    xcrun devicectl device install app \
      --device "$(xcrun devicectl list devices --hide-headers --columns Identifier | awk 'NF {print $1; exit}')" \
      build/Build/Products/Debug-iphoneos/Mosaico.app

clean:
    rm -rf build Mosaico.xcodeproj
