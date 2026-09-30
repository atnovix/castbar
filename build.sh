#!/bin/zsh
# Bouwt CastBar.app (~/Applications) en wakeguard (~/.local/bin).
# Alleen opnieuw bouwen als de bron nieuwer is.
set -e
cd "${0:A:h}"
# Heeft de installatie van Command Line Tools de dubbele SwiftBridging-modulemap, gebruik dan een
# kloon zonder dat bestand in ~/.local/clt (zie README, "Problemen"); anders de gewone swiftc.
CLT=~/.local/clt
if [[ -x $CLT/usr/bin/swiftc ]]; then
  SWIFTC=($CLT/usr/bin/swiftc -sdk $CLT/SDKs/MacOSX.sdk -O)
else
  SWIFTC=(xcrun swiftc -O)
fi

APP=~/Applications/CastBar.app
BIN=$APP/Contents/MacOS/CastBar
if [[ ! -e $BIN || main.swift -nt $BIN || Mirroring.swift -nt $BIN || Claude.swift -nt $BIN || Info.plist -nt $BIN || Resources/atnovix.png -nt $BIN ]]; then
  mkdir -p $APP/Contents/MacOS $APP/Contents/Resources
  cp Info.plist $APP/Contents/
  cp Resources/* $APP/Contents/Resources/
  $SWIFTC main.swift Mirroring.swift Claude.swift -o $BIN
  # Eigen certificaat (login-sleutelhanger): het Toegankelijkheid-vinkje blijft dan geldig na een nieuwe build
  codesign --force --sign "CastBar Local Signing" --identifier nl.atmin.castbar $APP
  echo "gebouwd: $APP"
  launchctl kickstart -k gui/$(id -u)/nl.atmin.castbar 2>/dev/null || true
fi

WG=~/.local/bin/wakeguard
if [[ ! -e $WG || wakeguard.swift -nt $WG ]]; then
  mkdir -p ~/.local/bin
  $SWIFTC wakeguard.swift -o $WG
  echo "gebouwd: $WG"
  launchctl kickstart -k gui/$(id -u)/nl.atmin.wakeguard 2>/dev/null || true
fi
