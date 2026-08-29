#!/usr/bin/env bash
# Build an UNSIGNED .ipa for sideloading with SideStore/AltStore.
#
# SideStore re-signs the app with your own Apple ID on-device, so the ipa
# must go out unsigned — do not codesign it here.
#
# Output: build/MealPicker.ipa  (AirDrop it to the phone, open in SideStore)
set -euo pipefail

cd "$(dirname "$0")/.."

flutter build ios --release --no-codesign

cd build/ios/iphoneos
rm -rf Payload ../../MealPicker.ipa
mkdir -p Payload
cp -R Runner.app Payload/
zip -qry ../../MealPicker.ipa Payload
rm -rf Payload

cd ../../..
echo
echo "Built: $(pwd)/build/MealPicker.ipa"
ls -lh build/MealPicker.ipa
