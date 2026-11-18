#!/bin/zsh
# Builds OLED Pulse from source, installs it to ~/Applications, and launches it.
set -euo pipefail
cd "${0:A:h}"

macos_major=$(sw_vers -productVersion | cut -d. -f1)
if (( macos_major < 14 )); then
  echo "OLED Pulse requires macOS 14 or later (found $(sw_vers -productVersion))." >&2
  exit 1
fi

if ! xcrun --find swiftc >/dev/null 2>&1; then
  echo "The Swift compiler was not found. Install the Xcode Command Line Tools with:" >&2
  echo "  xcode-select --install" >&2
  exit 1
fi

./OLEDPulse/build.sh install
echo "OLED Pulse is running in the menu bar and will launch at login."
