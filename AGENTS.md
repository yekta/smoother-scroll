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
- `ScrollTuning.swift`: the settings turned into the numbers the animator runs on: the two lags a
  notch eases through (their times come from the animation time and the tail to head ratio), the
  acceleration curve and the glide.
- `ScrollAnimator.swift`: each notch moves a target that the content follows through two lags,
  landing exactly on it. A fast spin also leaves a glide, a speed that decays like a trackpad's
  momentum, which the content keeps to when it is faster. How fast the wheel spins is measured
  over its last few notches, since events can arrive bunched. While notches arrive, the events
  are a trackpad gesture (began, changed, ended); once they stop, its momentum. A notch the
  other way stops the motion first, as a finger on a trackpad does.

### Sources/SmootherScroll

- `ScrollEngine.swift`: the event tap and a display link, on one thread of their own. One wheel
  event is one notch (macOS's own wheel acceleration is dropped). Continuous events (trackpads,
  Magic Mouse) and scrolling with ⌘, ⌥ or ⌃ held pass through; Shift turns vertical into
  horizontal. The events it posts carry `marker` so the tap lets them through.
- `AppLookup.swift`: the app under the pointer, for the disabled apps.
- `AppModel.swift`: the settings, the login item and Accessibility access, which the engine
  needs and which is checked every second.
- `StatusItemController.swift`: the menu bar item, drawn from Lucide's `mouse` (`LucideMouse.swift`).
- `SettingsView.swift`, `SettingsWindowController.swift`: the settings, a grouped SwiftUI form
  of stock controls on a window of Liquid Glass over a heavy blur of the desktop, tinted black
  in dark mode and white in light (the blur alone before macOS 26). The system's Liquid Glass
  setting (Clear or Tinted, under Appearance) applies to it too. Its curve runs the animator with the settings as they are.
  While the window is open the app shows in the Dock. A screenshot of the window alone
  (`screencapture -l`) draws it over black; capture the screen around it to see the glass.
- `UpdateChecker.swift`: compares the version with the latest GitHub release and installs it:
  it downloads the zip itself, since a browser's download is quarantined and Gatekeeper blocks
  an app that isn't notarized, then swaps the app and restarts it.

### Resources, assets and scripts

- `Resources/AppIcon.icon`: the app icon, made for Icon Composer: Lucide's `mouse`, filled, white
  on Motile's dark tile. `assets/favicon.svg` is the same icon as a flat SVG.
- `scripts/build-app.sh`: builds `build/Smoother Scroll.app`, universal, signed with the Developer
  ID certificate named by `SIGN_IDENTITY`, or ad hoc without it. It stamps
  the binary with the SDK it was built with: SwiftPM stamps the deployment target's, and macOS
  then draws the app in the old style, without Liquid Glass.
- `scripts/release-version.sh`: the version of a commit: `VERSION` and the number of commits.
- `scripts/install.sh`: installs the latest release into /Applications with curl, which leaves
  it unquarantined. README.md tells users to install this way.

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

The app needs Accessibility access. A build is signed ad hoc, so each new build is a new app to
macOS: remove the old entry under System Settings → Privacy & Security → Accessibility and add
the new one.

`build.yml` tests and builds pull requests. On `main`, `release.yml` tests, builds and publishes
the app as a GitHub release. With the repository's signing secrets (`APPLE_CERTIFICATE` and
`APPLE_CERTIFICATE_PASSWORD`, the Developer ID Application certificate as a base64 .p12 and its
password; `APPLE_API_KEY`, `APPLE_API_KEY_ID` and `APPLE_API_ISSUER_ID`, an App Store Connect API
key) it signs and notarizes the app; without them it signs it ad hoc.

## Commit Messages

Commit messages start with the part of the system they touched, followed by a short imperative
sentence describing the change:

    core: Glide on after a fast spin
    app: Disable smoothing in the app under the pointer

The parts are `core` and `app`. Use `ci` for the workflows and scripts and `docs` for README.md
and AGENTS.md.

The title should be concise. The description explains the work in more detail (only if
required) while still being concise. Use simple language, do not try to sound smart.
