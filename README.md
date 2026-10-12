<img src="assets/favicon.svg" width="64" height="64" alt="">

# Smoother Scroll

Makes a mouse wheel on the Mac scroll like a trackpad. A free, open-source alternative to SmoothScroll, under the MIT license.

<img src="docs/settings.png" width="500" alt="The settings window">

- **Smooth notches.** Each notch of the wheel eases in and out and lands exactly where it should, in pixels instead of lines.
- **Momentum.** Spin the wheel fast and the page glides on after you stop, like a flick on a trackpad. A notch the other way stops it, like a finger on the trackpad.
- **Acceleration.** A fast spin covers more ground; slow, deliberate notches stay precise.
- **Feels like a trackpad to apps.** The events carry a trackpad's scroll phases, so pages stretch at their edges and spring back.
- **Leaves the rest alone.** Trackpads and the Magic Mouse scroll as they did. Scrolling with ⌘, ⌥ or ⌃ held goes to the app as it was, for zooming. Shift scrolls sideways.
- **Per app.** Turn it off for apps that want the wheel's own steps, like CAD and 3D tools, from the menu bar or the settings.
- **Native.** A menu bar app with a plain macOS settings window that draws how your settings scroll as you change them. It starts at login and hides from the menu bar if you want.

## Install

1. Download `SmootherScroll.zip` from the [latest release](https://github.com/yekta/smoother-scroll/releases/latest), unzip it and move **Smoother Scroll** to Applications.
2. The app isn't notarized, so remove the quarantine macOS puts on downloads once:

   ```sh
   xattr -dr com.apple.quarantine "/Applications/Smoother Scroll.app"
   ```

3. Open it and allow it under **System Settings → Privacy & Security → Accessibility**. It needs this to change the wheel's scroll events.

Every new version is a new app to macOS: after an update, remove Smoother Scroll from the Accessibility list with − and add it again. **Check for Updates…** in its menu says when there is one.

## Settings

| Setting | What it does |
| --- | --- |
| Step size | How far one notch scrolls, in points |
| Animation time | How long one notch takes to settle |
| Acceleration | How much further a fast spin goes |
| Momentum | How long a fast spin glides on after the wheel stops. Off makes every notch land exactly |
| Behave like a trackpad | Sends a trackpad's scroll phases, for the stretch at the edges. Turn it off if an app misbehaves |
| Tail to head ratio | How much longer a notch eases out than in |
| Maximum acceleration | The most a notch can be multiplied by |

The defaults are a SmoothScroll setup (250 px steps over 350 ms, tail to head ratio 2) with a trackpad's momentum added.

## Building

Needs Xcode 26 or later.

```sh
scripts/build-app.sh --open   # builds build/Smoother Scroll.app and opens it
swift test                    # tests how scrolling moves
```

Every push to `main` is built and published as a [GitHub release](https://github.com/yekta/smoother-scroll/releases).

## License

MIT. The mouse is [Lucide](https://lucide.dev)'s `mouse` icon, under the ISC license.
