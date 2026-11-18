# OLED Pulse

A macOS menu bar app that stops LG OLED panels (C2, LG Flex, and similar) from automatically dimming when the picture doesn't change much.

LG's static-content protection (ASBL, alongside TPC/GSR) watches the overall picture level and gradually dims the screen when it stays roughly the same for a while. Dark-mode desktops, documents, and code editors trigger it constantly, and moving the mouse or scrolling isn't enough change to reset it.

OLED Pulse briefly bends the display's gamma curve on a timer. The change is large enough for the panel to count as new content but subtle enough to be easy to miss. With the defaults, every 180 seconds it brightens midtones over half a second and eases back over another half second. Pure black and pure white don't change.

## Requirements

- macOS 14 (Sonoma) or later
- Xcode Command Line Tools, for the Swift compiler (`xcode-select --install`)

## Install

Clone to home folder and install:

```bash
gh repo clone justicefreed/oled-display-dim-fix ~/oled-display-dim-fix && ~/oled-display-dim-fix/install.sh
```

Reinstall:

```bash
YOUR_PARENT_DIRECTORY/oled-display-dim-fix/install.sh
```

Or, with plain git over SSH:

```bash
git clone git@github.com:justicefreed/oled-display-dim-fix.git ~/oled-display-dim-fix && ~/oled-display-dim-fix/install.sh
```

The install script builds the app from source, ad-hoc signs it, copies it to `~/Applications/OLEDPulse.app`, launches it, and registers it to open at login. macOS may show a notification that a login item was added.

To update, pull the latest changes and run `./install.sh` again. Your settings are kept.

## Usage

Click the sun icon in the menu bar.

- **Pulsing Enabled**: overall on/off. The icon dims while it's off.
- **Pulse All Saved Displays Now**: pulses every connected saved display immediately.
- **Connected Displays**: every display currently attached. A checkmark means the display is saved and will be pulsed whenever it's connected. Each display's submenu has:
  - **Pulse This Display**: adds the display to, or removes it from, the saved list.
  - **Next pulse in XXs**: countdown to the next scheduled pulse.
  - **Test Pulse Now**: one pulse with the current settings.
  - **Mode**, **Depth**, **Ramp**, **Hold**, **Interval**: settings for this display, with presets and a **Custom…** entry.
  - **Reset to Defaults**.
- **Saved Displays (Not Connected)**: saved displays that aren't attached right now, with their settings and a **Forget** option.
- **Launch at Login**.

Displays are recognized by vendor, model, and serial number, so identical monitors share settings.

### Settings

| Setting | Default | Meaning |
|---|---|---|
| Mode | Gamma | **Gamma** raises the curve to the power `1 + depth`, which moves midtones and shadows while leaving black and white alone. **Scale** multiplies every level by `1 - depth`, like a brightness dip. |
| Depth | −0.3 | Strength of the pulse. In gamma mode, negative values brighten midtones and positive values darken them. |
| Ramp | 0.5 s | Fade time in and out. Gradual changes are much less noticeable than instant ones. |
| Hold | 0 s | Time held at full strength between the fade in and the fade out. |
| Interval | 180 s | Time between pulses. Keep it shorter than the time your panel takes to start dimming. |

To tune for your panel, lower Depth and Ramp until the dimming starts coming back, then step back up one notch.

### When pulses are skipped

Scheduled pulses are skipped while the system or displays are asleep, the screen is locked, the screensaver is running, or full-screen video is playing on that display. Full-screen video is detected heuristically: another app has a window covering the whole display while some app holds a "keep display awake" power assertion. Tools like `caffeinate` or Amphetamine hold the same assertion, so with one running, any full-screen app pauses pulsing on that display.

## Caveats

- Anything else that writes the display gamma table can conflict with pulses. That includes f.lux, BetterDisplay's software dimming, and some calibration tools. Night Shift works fine. macOS restores the gamma table automatically if the app quits or crashes mid-pulse.
- The app is ad-hoc signed and built locally, so it isn't notarized. That's fine for your own Mac, but don't distribute the built `.app`.

## Experimenting from the command line

`tools/GammaPulse.swift` is the standalone tool used to find the defaults. It pulses the first connected LG display:

```bash
swiftc -O tools/GammaPulse.swift -o gamma-pulse
./gamma-pulse --mode gamma --depth -0.3 --ramp 0.5 --hold 0 --interval 180
./gamma-pulse --once --depth 0.1 --hold 0.3   # single pulse, then exit
```

## Uninstall

1. In the menu, turn off **Launch at Login**, then choose **Quit OLED Pulse**.
2. Delete the app and its settings:

```bash
rm -rf ~/Applications/OLEDPulse.app
defaults delete io.github.justicefreed.OLEDPulse
```
