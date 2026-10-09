#!/bin/zsh
# Takes the App Store screenshots on the 6.9" iPhone and 13" iPad simulators.
#   Tools/screenshots.sh            both devices
#   Tools/screenshots.sh iphone     one of them
# The scenes come from the Debug build's launch arguments (see Autoplay in test/App/GameSession.swift);
# `swift run traitors-sim --scenes` finds seeds for others. Output goes to docs/app-store-screenshots/.
set -e
root=${0:A:h:h}
bundle=com.aaronbrennan.traitors
out=$root/docs/app-store-screenshots
build=${TMPDIR:-/tmp}/traitors-screenshots

typeset -A device folder
device=(iphone "iPhone 18 Pro Max" ipad "iPad Pro 13-inch (M5)")
folder=(iphone iphone-6.9 ipad ipad-13)

# name | seconds to wait before the picture | launch arguments
shots=(
  "01-role-reveal|7|-seed 7 -role traitor -stopPhase roleReveal -ceremony settled"
  "02-round-table|14|-seed 3 -role faithful -stopPhase roundTable -stopDay 2"
  "03-great-hall|16|-seed 3 -role faithful -stopPhase mission -stopDay 1 -mission greatHall -arenaBots 1"
  "04-shipwreck-dive|22|-seed 3 -role faithful -stopPhase mission -stopDay 1 -mission shipwreckDive -arenaBots 1"
  "05-kite-race|22|-seed 3 -role faithful -stopPhase mission -stopDay 1 -mission kiteRace -arenaBots 1"
  "06-sheep-round-up|22|-seed 3 -role faithful -stopPhase mission -stopDay 1 -mission sheepRoundUp -arenaBots 1"
  "07-banishment|7|-seed 2 -role faithful -stopPhase voteReveal -stopDay 1 -ceremony settled"
  "08-night|7|-seed 1 -role traitor -stopPhase night -stopDay 1 -stopNight murder"
  "09-game-over|8|-seed 2 -role faithful -stopPhase gameOver -endingSeenSeed 2"
)

(( $# )) || set -- iphone ipad
for kind in "$@"; do
  name=$device[$kind]
  [[ -n $name ]] || { echo "unknown device: $kind (iphone or ipad)"; exit 1 }
  xcrun simctl boot "$name" 2>/dev/null || true
  xcrun simctl bootstatus "$name" >/dev/null
  if [[ ! -d $build/Build/Products/Debug-iphonesimulator/test.app ]]; then
    xcodebuild -project $root/test.xcodeproj -scheme test -configuration Debug \
      -destination "platform=iOS Simulator,name=$name" -derivedDataPath $build build | tail -3
  fi
  xcrun simctl install "$name" $build/Build/Products/Debug-iphonesimulator/test.app
  xcrun simctl status_bar "$name" override --time "9:41" --batteryState charged --batteryLevel 100 \
    --wifiBars 3 --cellularBars 4 --dataNetwork wifi
  mkdir -p $out/$folder[$kind]
  for shot in $shots; do
    parts=("${(@s:|:)shot}")
    xcrun simctl terminate "$name" $bundle 2>/dev/null || true
    xcrun simctl launch "$name" $bundle -mute 1 -autoplay 1 ${=parts[3]} >/dev/null
    sleep $parts[2]
    xcrun simctl io "$name" screenshot $out/$folder[$kind]/$parts[1].png 2>/dev/null
    echo "$folder[$kind]/$parts[1].png"
  done
  xcrun simctl terminate "$name" $bundle 2>/dev/null || true
  xcrun simctl status_bar "$name" clear
  swift $root/Tools/flatten-png.swift $out/$folder[$kind]/*.png
done
