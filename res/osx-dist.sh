#!/usr/bin/env bash

echo $MACOS_CODESIGN_IDENTITY
cargo install flutter_rust_bridge_codegen --version 1.80.1 --features uuid --locked
cd flutter; flutter pub get; cd -
~/.cargo/bin/flutter_rust_bridge_codegen --rust-input ./src/flutter_ffi.rs --dart-output ./flutter/lib/generated_bridge.dart --c-output ./flutter/macos/Runner/bridge_generated.h
./build.py --flutter --unix-file-copy-paste
rm -f unilink-control-$VERSION.dmg
# security find-identity -v
APP_NAME="UniLink Control"
APP_BUNDLE="./flutter/build/macos/Build/Products/Release/${APP_NAME}.app"
DMG_NAME="unilink-control-$VERSION.dmg"
codesign --force --options runtime -s $MACOS_CODESIGN_IDENTITY --deep --strict "$APP_BUNDLE" -vvv
create-dmg --icon "${APP_NAME}.app" 200 190 --hide-extension "${APP_NAME}.app" --window-size 800 400 --app-drop-link 600 185 "$DMG_NAME" "$APP_BUNDLE"
codesign --force --options runtime -s $MACOS_CODESIGN_IDENTITY --deep --strict "$DMG_NAME" -vvv
# notarize the UniLink Control dmg
rcodesign notary-submit --api-key-path ~/.p12/api-key.json  --staple "$DMG_NAME"
