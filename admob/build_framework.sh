#!/bin/bash
# Wraps the built library (bin/libpcadmob.ios.template_release.arm64.dylib) as a signed-ready framework inside an
# xcframework, which Godot's iOS export embeds: bin/libpcadmob.ios.template_release.xcframework
set -e
cd "$(dirname "$0")"
LIB=$(ls bin/libpcadmob.ios.template_release*.dylib | head -1)
NAME=libpcadmob
rm -rf build_fw && mkdir -p build_fw/$NAME.framework
cp "$LIB" build_fw/$NAME.framework/$NAME
install_name_tool -id @rpath/$NAME.framework/$NAME build_fw/$NAME.framework/$NAME
cat > build_fw/$NAME.framework/Info.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key><string>en</string>
	<key>CFBundleExecutable</key><string>$NAME</string>
	<key>CFBundleIdentifier</key><string>com.emeraldvortexgames.pcadmob</string>
	<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
	<key>CFBundleName</key><string>$NAME</string>
	<key>CFBundlePackageType</key><string>FMWK</string>
	<key>CFBundleShortVersionString</key><string>1.0</string>
	<key>CFBundleVersion</key><string>1</string>
	<key>CFBundleSupportedPlatforms</key><array><string>iPhoneOS</string></array>
	<key>MinimumOSVersion</key><string>14.0</string>
</dict>
</plist>
PLIST
rm -rf bin/$NAME.ios.template_release.xcframework
xcodebuild -create-xcframework -framework build_fw/$NAME.framework -output bin/$NAME.ios.template_release.xcframework
ls -R bin/$NAME.ios.template_release.xcframework | head -20
