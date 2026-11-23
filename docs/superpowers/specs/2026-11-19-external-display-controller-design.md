# External Display Controller: design

## Intent

Greg uses an external monitor (today a Lenovo T24h-20) on an Apple silicon Mac. macOS changes only the
built-in screen with the keyboard brightness keys. Greg wants those keys to change the external display
too, and wants a slider in the menu bar. The app talks to the display over DDC/CI (a control channel
inside the display cable). This version controls brightness only. Volume control comes in a later change.

The app goes into the mac-utils repo as `external-display-controller`, beside Menu Bar Manager, Menu Bar
Stats and Claude Usage. It is installed on both of Greg's Macs (`personal` and `work`) by the existing
chezmoi script in the dotfiles repo.

## Goals

- The brightness keys (F1 and F2) on any keyboard change the brightness of the external display under the
  mouse pointer. The app cannot tell which keyboard sent a key, and does not need to.
- One menu bar item holds a brightness slider for each external display that answers DDC.
- It follows the mac-utils pattern: a Swift package with no third-party dependencies and a background app
  with no Dock icon. `install.sh` builds it and signs it ad hoc. It has no configuration files.

## Non-goals

- No preferences window.
- No volume control, no volume slider and no volume keys. Greg has no display with speakers to test with,
  so a later change adds volume after he can test it.
- No contrast, color, input source or power control.
- No control of the built-in screen. macOS keeps that.
- No Intel Mac support. Both machines are Apple silicon.
- No Mac App Store build, no notarization.
- No on-screen brightness HUD. macOS draws none for an external display, and the menu bar slider shows the
  value.

## Anti-goals

- If the pointer is on the built-in screen, or no external display answers DDC, the app must pass the
  brightness key on. A dead key is worse than no app.
- The app must not wedge a display. A bad DDC write must fail quietly and leave the display usable.
- The app must not spend measurable CPU while idle, like the other mac-utils.

## Constraints

- Apple silicon has no public DDC API. The app uses Apple's private `IOAVService` interface, reached
  through a small C target, as Menu Bar Stats does for temperature. A macOS update can break it. When it
  breaks, the app must still start, show a clear line in its menu, and let the keys pass through.
- Catching media keys needs an event tap, and an event tap needs the Accessibility permission. The app is
  signed ad hoc, so macOS asks again after each rebuild. The README already explains this for Menu Bar
  Manager and needs one more row.
- Both machines run macOS 26 or later. Menu Bar Stats targets macOS 26, so this app targets macOS 26.
- Swift 6.2, tools version 6.2, as the other packages.

## Approaches considered

1. Call the private `IOAVService` interface from a small C wrapper. No dependencies. A macOS update can
   break it. Greg chose this one.
2. Run the `m1ddc` tool as a child process. Less code, but it adds a dependency and breaks the rule that
   mac-utils has none.
3. Ask BetterDisplay to do the work. This needs a second app and a licence.

## Decisions made with Greg

- The key to display rule: a brightness key changes the display under the mouse pointer. On the built-in
  screen, the key passes through to macOS.
- The menu has one brightness slider for each external display, with the display name above it.
- This version has no volume control. Greg chose this because he cannot test volume on a display with
  speakers, and a wrong match to the sound output can change the volume of a normal output.

## Design

Package layout, following the other apps:

```
external-display-controller/
  Package.swift
  Info.plist                      LSUIElement, id io.github.greg-cook.external-display-controller
  build-app.sh                    builds ExternalDisplayController.app into build/
  Sources/DisplayDDC/             C target: IOAVService wrapper, DDC read and write of one VCP code
  Sources/ExternalDisplayController/
    main.swift                    status item, menu, sliders
    Displays.swift                finds external displays, matches an IOAVService to each screen
    KeyTap.swift                  CGEventTap for the brightness media keys
```

Behavior:

- DDC code: brightness is VCP 0x10. The app reads its maximum and treats a failed read as "not
  supported". The C wrapper takes the VCP code as a parameter, so a later change can add volume (0x62).
- Matching a display to its DDC service: find the `IOAVService` for each `DCPAVServiceProxy` whose
  location is external, and match it to an `NSScreen` by the display's vendor, product and serial numbers.
- Key handling: the event tap sees the system-defined media key events. For a brightness key with the
  pointer on a supported external display, the app changes the value by one step (1/16 of the range, as
  macOS does) and consumes the event. In every other case it passes the event on.
- Writes are sent from a serial queue and coalesced, so a held key or a dragged slider sends the latest
  value and not a queue of old ones. DDC is slow, so the app never blocks the main thread on it.
- When the menu opens, the app reads the slider values from the display. A change made with the display's
  own buttons then shows correctly.
- When the screen configuration changes or the Mac wakes, the app scans for displays again.
- If the event tap cannot be created because Accessibility is off, the menu says so and offers a link to
  the setting, as Menu Bar Manager does. The sliders still work.

Calls made by the author (a reviewer raised each one, and Greg accepted the design with these in place):

- The event tap is an active tap, so it can consume events. If the pointer is on a supported external
  display, the app consumes both the key-down and the key-up event. The built-in screen then keeps its
  brightness. If the app passes the key on, it passes both events.
- If the pointer is on a display that does not answer DDC, the app passes the key on. A mirrored set
  counts as one display, and it uses the DDC service of the external member.
- The app keeps the last known value for each display and reads the display again on the first key press
  after a scan, after the menu closes, and after 30 seconds without a key press. This keeps a key press
  fast and stops the value from drifting.
- A scan that finds no DDC answer from a display tries again after 2 seconds and after 6 seconds, because
  displays are often not ready just after a wake. A scan never blocks the menu.
- If the private symbols fail to load, the menu says "DDC interface unavailable". If the scan finds no
  external display, the menu says "No external display found".
- Greg verifies the work on `personal` first. On `work`, he grants Accessibility once after the first
  install.

Wiring in the other repos:

- `mac-utils/install.sh` accepts `external-display-controller`. The process name is
  `ExternalDisplayController`.
- `mac-utils/README.md` gets a section, a row in the app and permission tables, a line in How they work and
  Limitations, and an entry in Project layout.
- The dotfiles repo adds `home/Library/LaunchAgents/io.github.greg-cook.external-display-controller.plist`
  and adds the app to the loops in `home/.chezmoiscripts/run_after_70-mac-utils.sh`. This is a separate
  commit in a separate repo, made after the app works.

## Left to the builder

- The exact step size, the menu layout, the icon symbol and colors.
- Whether to apply a short delay between DDC writes. Many displays need one.
- Which tests to write for hardware code. Pure logic such as step math and coalescing must have tests.
