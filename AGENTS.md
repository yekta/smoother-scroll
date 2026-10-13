## What is this?

Smoother Scroll is a Mac menu bar app that makes a mouse wheel scroll like a trackpad. It
catches the wheel's scroll events with an event tap and posts smooth, pixel-precise ones in
their place: each notch eases in and out, a fast spin speeds up and glides on after the wheel
stops, and the events carry a trackpad's scroll phases, so views rubber-band at their edges. A
trackpad's and a Magic Mouse's own events are left alone. It is an open-source alternative to
SmoothScroll, under the MIT license.

| Part | Where | What it does |
| --- | --- | --- |
| Core (`Sources/ScrollCore`) | Inside the app | The settings and the animator: notches in, scroll events out. No AppKit, so it is tested on its own |
| App (`Sources/SmootherScroll`) | The user's Mac | The event tap, the menu bar item and the settings window |

## Repo Structure:

### Sources/ScrollCore

- `ScrollSettings.swift`: everything the user tunes, saved as JSON. A setting missing from what
  was saved takes its default.
- `ScrollTuning.swift`: the settings turned into the numbers the animator runs on: the easing
  (Apple's ease in, ease out, or ease in and out, whose halves the tail to head ratio stretches;
  1 is Apple's as it is), the acceleration
  curve (none up to 3 notches a second, then growing with the spin's speed) and the glide.
- `CubicBezier.swift`: Core Animation's timing curves, with Apple's control points.
- `ScrollAnimator.swift`: each notch is a pulse, its step eased over the animation time; pulses
  add up, as in SmoothScroll. How fast the wheel spins is measured over the last few notches by
  the mouse's own timestamps (events reach the tap bunched), and sets each notch's multiplier. A
  notch the other way drops what is left, unless it comes within `reversalGuard` of the last
  one: a wheel spun fast bounces back a tick, and taking that as a reversal threw the spin's
  distance away. Off by default: a glide after a fast spin, like a
  trackpad's momentum, and a trackpad's scroll phases (began, changed, ended, then momentum),
  so views rubber-band at their edges.

### Sources/SmootherScroll

- `ScrollEngine.swift`: the event tap and a display link, on one thread of their own. One wheel
  event is as many whole notches as the mouse's report says (one without it) along its main axis,
  timed by the event's timestamp: macOS sends a slow notch as about a tenth of a line and a fast
  one as many lines, and our acceleration replaces that. Continuous events (trackpads,
  Magic Mouse) and scrolling with ⌘, ⌥ or ⌃ held pass through; Shift turns vertical into
  horizontal. The events it posts carry `marker` so the tap lets them through.
- `WheelReader.swift`: the wheel's own counts, read from the mouse over IOKit HID on the engine's
  thread. A fast spin sends several notches in one report, which macOS folds into one event; each
  event is matched to its report by timestamp and counts as that many notches. Needs Input
  Monitoring access; without it an event is one notch.
- `WheelLog.swift`: with `logWheelEvents` set in the app's defaults, writes what each wheel event
  says to ~/Library/Logs/Smoother Scroll/wheel.log; README.md tells users how.
- `AppLookup.swift`: the app under the pointer, for the disabled apps.
- `AppModel.swift`: the settings, the login item, and Accessibility and Input Monitoring access,
  checked every second: the engine needs the first, the wheel's counts the second.
- `StatusItemController.swift`: the menu bar item, drawn from Lucide's `mouse` (`LucideMouse.swift`).
  A click drops the settings down from it in a popover; a right click shows a short menu. The
  popover's size is fixed before it shows (one that resizes as it opens lands off screen), and
  its window is made key, or its controls draw in their inactive grey.
- `SettingsView.swift`: the settings, a grouped SwiftUI form of stock controls with plain names,
  nothing drawn of our own. For a screenshot, open the panel with a real click on the menu bar
  item (opened any other way it shows inactive, in grey) over the bare desktop wallpaper, with
  no windows or icons behind it, and capture the screen around it: `screencapture -l` draws a
  window alone over black, without its glass.
- `Updater.swift`: checks the latest GitHub release at launch and every six hours. A newer one
  shows at the top of the menu and in the settings; installing it downloads the zip, checks it
  is signed by the team (44R7KF7645), swaps the app and restarts it.

### Resources, assets and scripts

- `Resources/AppIcon.icon`: the app icon, made for Icon Composer: Lucide's `mouse`, filled, white
  on Motile's dark tile. `assets/favicon.svg` is the same icon as a flat SVG.
- `scripts/build-app.sh`: builds `build/Smoother Scroll.app`, universal, signed with the Developer
  ID certificate named by `SIGN_IDENTITY`, or ad hoc without it. It stamps
  the binary with the SDK it was built with: SwiftPM stamps the deployment target's, and macOS
  then draws the app in the old style, without Liquid Glass.
- `scripts/release-version.sh`: the version of a commit: `VERSION` and the number of commits.
- `scripts/install.sh`: installs the latest release into /Applications from Terminal.

## General Rules:

- Keep it simple. Do not overcomplicate things.
- Scrolling must never stutter. Nothing runs on the engine's thread but the tap and the frames;
  nothing slow runs in the tap, which macOS turns off when it is late.
- How scrolling feels belongs in `ScrollCore`, where it is tested, not in the engine.
- The app looks like the current macOS: stock AppKit and SwiftUI controls in the system's
  colours on tinted glass, no colours of our own, the Lucide mouse for the app.
- Do not leave paragraphs of comments on top of the code. Prefer clear names; keep the comments
  that are needed concise. Comments move with the code.
- Use guard statement patterns in any code you write.
- Do not write useless tests; tests cover input/output behaviour.
- Reinvent the wheel but do not reinvent the car. A simple problem gets no new library.
- Do not insert yourself into our code, commits or PRs in any way.
- Never commit or push unless asked to.
- After you make code changes, run the checks below and fix what they raise.

## Development

Needs a Mac with Xcode 26 or later (for the icon).

    scripts/build-app.sh --open      # builds and opens build/Smoother Scroll.app
    swift test                       # the core's tests

The app needs Accessibility access, and Input Monitoring for the wheel's counts. A local build is
signed ad hoc, so each one is a new app to macOS: remove the old entry under System Settings →
Privacy & Security → Accessibility (and Input Monitoring) and add the new one. Releases are signed
with the Developer ID, so their access stays through updates.

`build.yml` tests and builds pull requests. On `main`, `release.yml` tests, builds and publishes
the app as a GitHub release. With the repository's signing secrets (`APPLE_CERTIFICATE` and
`APPLE_CERTIFICATE_PASSWORD`, the Developer ID Application certificate as a base64 .p12 and its
password; `APPLE_API_KEY`, `APPLE_API_KEY_ID` and `APPLE_API_ISSUER_ID`, an App Store Connect API
key) it signs and notarizes the app; without them it signs it ad hoc. They come from
`~/apple-signing` on the dev machine, whose README.md says which file is which secret.

## Commit Messages

Commit messages start with the part of the system they touched, followed by a short imperative
sentence describing the change:

    core: Glide on after a fast spin
    app: Disable smoothing in the app under the pointer

The parts are `core` and `app`. Use `ci` for the workflows and scripts and `docs` for README.md
and AGENTS.md.

The title should be concise. The description explains the work in more detail (only if
required) while still being concise. Use simple language, do not try to sound smart.
