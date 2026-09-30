#!/bin/zsh
# Installeert toetsenbordverlichting, CastBar en WakeGuard voor de huidige gebruiker
# en laat ze automatisch starten bij het inloggen.
set -e
cd "${0:A:h}"

./tools/make-cert.sh

mkdir -p ~/.local/bin ~/Library/LaunchAgents ~/Library/Logs
cp kbd-backlight.js ~/.local/bin/

./build.sh

for f in launchagents/*.plist; do
  dest=~/Library/LaunchAgents/${f:t}
  sed "s|__HOME__|$HOME|g" $f > $dest
  launchctl bootout gui/$(id -u) $dest 2>/dev/null || true
  launchctl bootstrap gui/$(id -u) $dest
  echo "gestart: ${f:t:r}"
done

# Synchrone weergave vast in de menubalk (CastBar bedient AirPlay via dat menu)
defaults write com.apple.controlcenter "NSStatusItem Visible ScreenMirroring" -bool true
killall ControlCenter 2>/dev/null || true

echo
echo "Klaar. Zet CastBar aan bij Systeeminstellingen > Privacy en beveiliging > Toegankelijkheid."
