#!/bin/zsh
# Builds OLEDPulse.app into ./build. Pass "install" to copy it to ~/Applications and (re)launch it.
set -euo pipefail
cd "${0:A:h}"

APP=build/OLEDPulse.app
rm -rf $APP
mkdir -p $APP/Contents/MacOS
swiftc -O Sources/*.swift -o $APP/Contents/MacOS/OLEDPulse
cp Info.plist $APP/Contents/
codesign --force --sign - $APP

if [[ ${1:-} == install ]]; then
  pkill -x OLEDPulse || true
  while pgrep -x OLEDPulse >/dev/null; do sleep 0.1; done
  mkdir -p ~/Applications
  rm -rf ~/Applications/OLEDPulse.app
  cp -R $APP ~/Applications/
  open ~/Applications/OLEDPulse.app
  echo "Installed to ~/Applications/OLEDPulse.app"
fi
