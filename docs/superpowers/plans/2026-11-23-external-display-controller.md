# External Display Controller Implementation Plan

> For agentic workers: use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task by task. Steps use checkbox (`- [ ]`) syntax.

Goal: a menu bar app that changes the brightness of an external DDC/CI display from a slider and from the keyboard brightness keys.

Architecture: three Swift targets and one C target. `DisplayCore` holds all logic that needs no hardware (DDC packets, step math, key decoding, routing, write coalescing) and carries the tests. `DisplayDDC` is a C wrapper over Apple's private `IOAVService` interface. The `ExternalDisplayController` executable joins them to AppKit, a status item and a `CGEventTap`.

Tech stack: Swift 6.2, AppKit, CoreGraphics, IOKit (private `IOAVService` symbols loaded with `dlsym`), Swift Testing. No third-party dependencies.

Spec: `docs/superpowers/specs/2026-11-19-external-display-controller-design.md`

## Global Constraints

- Swift tools version 6.2 and `platforms: [.macOS(.v26)]`, as the other packages.
- No third-party dependencies. The app is ad hoc signed and has `LSUIElement` set, so it has no Dock icon.
- Bundle identifier `io.github.greg-cook.external-display-controller`. Process name `ExternalDisplayController`. Directory `external-display-controller`.
- This version controls brightness only (VCP 0x10). It has no volume slider and no volume keys. The C wrapper takes the VCP code as a parameter so that a later change can add volume (0x62).
- A brightness key changes the display under the mouse pointer.
- If the pointer is on the built-in screen, the app passes the key on. If the pointer is on a display that does not answer DDC, the app also passes the key on. It passes both the key-down and the key-up event.
- If the app changes a display, it consumes both the key-down and the key-up event.
- One key step is 1/16 of the display's maximum value, and at least 1.
- A scan that finds no DDC answer from a display retries after 2 seconds and after 6 seconds. A scan never blocks the menu.
- If the private symbols fail to load, the menu says "DDC interface unavailable". If the scan finds no external display, the menu says "No external display found".
- DDC writes never run on the main thread.
- Run `shellcheck` over every shell script that changes. Commits follow Conventional Commits and go straight to `main` in the mac-utils repo.

## Review Focus

1. The display is unplugged or asleep during a key press: the write fails, the app does not crash, and the next scan recovers the display.
2. The user holds a brightness key down: the display receives the latest value and not a queue of old ones.
3. The user turns Accessibility off while the app runs: the tap is disabled, the keys pass through, and the menu says so.
4. Two external displays where only one answers DDC: a key with the pointer on the other one passes through.
5. The Mac wakes before the display is ready: the scan retries and the sliders appear without a restart.

Each line has its test in the task that owns the code (Tasks 1, 3 and 5), or a hardware check in Task 6.

## File Structure

```
external-display-controller/
  Package.swift
  Info.plist
  build-app.sh
  Sources/DisplayCore/            DDCPacket, BrightnessStep, LatestValueMailbox, MediaKeyDecoder, KeyRouting, ScanRetryPolicy
  Sources/DisplayDDC/             C wrapper over IOAVService (include/DisplayDDC.h, DisplayDDC.c)
  Sources/ExternalDisplayController/
    main.swift                    app delegate, status item, menu with sliders
    Displays.swift                scan, match to NSScreen, DisplayController
    KeyTap.swift                  CGEventTap and the Accessibility state
  Tests/DisplayCoreTests/
```

### Task 1: DisplayCore pure logic

Files:
- Create: `external-display-controller/Package.swift`, the `DisplayCore` sources and `Tests/DisplayCoreTests/DisplayCoreTests.swift`
- Create: empty placeholder sources so that `DisplayDDC` and `ExternalDisplayController` build (`DisplayDDC.c` with an include header, and a `main.swift` that is empty)

Interfaces:
- Produces (all `public`, in `DisplayCore`):
  - `struct VCPValue: Equatable, Sendable { current: UInt16; maximum: UInt16 }`
  - `enum DDCPacket { static let chipAddress: UInt32 = 0x37; static let dataAddress: UInt32 = 0x51; static func setVCP(code: UInt8, value: UInt16) -> [UInt8]; static func getVCPRequest(code: UInt8) -> [UInt8]; static func parseGetReply(_ bytes: [UInt8], code: UInt8) -> VCPValue? }`
  - `enum Direction { case up, down }` and `enum BrightnessStep { static func next(current: Int, maximum: Int, direction: Direction) -> Int }`
  - `final class LatestValueMailbox<Value: Sendable>: @unchecked Sendable { func put(_ value: Value) -> Bool; func take() -> Value? }`. If the caller must start a drain, `put` returns true.
  - `struct MediaKeyEvent: Equatable { key: Direction; isDown: Bool; isRepeat: Bool }` and `enum MediaKeyDecoder { static func decode(data1: Int) -> MediaKeyEvent? }`
  - `enum KeyAction: Equatable { case passThrough; case consume(displayID: UInt32) }` and `enum KeyRouting { static func decide(pointerDisplay: UInt32?, controllable: Set<UInt32>) -> KeyAction }`
  - `enum ScanRetryPolicy { static let delays: [Double] }`

- [ ] Step 1: write the failing tests in `DisplayCoreTests.swift` with Swift Testing:
  - `setVCP(code: 0x10, value: 50)` equals `[0x84, 0x03, 0x10, 0x00, 0x32, 0x9A]`. The last byte is `0x6E ^ 0x51` XOR every earlier byte.
  - `getVCPRequest(code: 0x10)` equals `[0x82, 0x01, 0x10, 0xAC]`.
  - `parseGetReply([0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x32, 0x00], code: 0x10)` equals `VCPValue(current: 50, maximum: 100)`. A reply with result byte `0x01`, or with a different code in byte 4, returns nil.
  - `BrightnessStep.next`: (50, 100, up) is 56. (98, 100, up) is 100. (3, 100, down) is 0. (7, 15, up) is 8.
  - `LatestValueMailbox`: `put(1)` is true, `put(2)` is false, `take()` is 2, `take()` is nil, then `put(3)` is true.
  - `MediaKeyDecoder.decode(data1: (2 << 16) | (0xA << 8))` is up and down-pressed. `(3 << 16) | (0xB << 8)` is down and released. `(3 << 16) | (0xA << 8) | 0x1` has `isRepeat` true. Key code 0 (sound up) returns nil.
  - `KeyRouting.decide`: pointer on a controllable display is `.consume` with that ID. Pointer on a display that is not in the set is `.passThrough`. A nil pointer display is `.passThrough`. An empty set is `.passThrough`.
  - `ScanRetryPolicy.delays` equals `[2, 6]`.
- [ ] Step 2: run `swift test` in `external-display-controller`. Expected: FAIL to compile, because the types do not exist.
- [ ] Step 3: implement the interfaces above in `Sources/DisplayCore/`, one file per type. `parseGetReply` reads the maximum from bytes 6 and 7 and the current value from bytes 8 and 9, as m1ddc does. It skips the checksum, because Task 2 decides whether the reply checksum is reliable on this display.
- [ ] Step 4: run `swift test`. Expected: all tests pass.
- [ ] Step 5: commit `feat(external-display-controller): add display logic and tests`.

### Task 2: DDC wrapper and hardware spike

Files:
- Create: `Sources/DisplayDDC/include/DisplayDDC.h`, `Sources/DisplayDDC/DisplayDDC.c`
- Modify: `Sources/ExternalDisplayController/main.swift` (a temporary `probe` command)

Interfaces:
- Produces (C, in `DisplayDDC.h`):
  - `bool DDCInterfaceAvailable(void)`: if `dlsym` finds `IOAVServiceCreateWithService`, `IOAVServiceReadI2C` and `IOAVServiceWriteI2C`, it returns true.
  - `size_t DDCCopyExternalServices(DDCService *_Nullable *_Nullable *_Nonnull out)` and `void DDCFreeServices(DDCService *_Nullable *_Nullable services, size_t count)`. An external service is a `DCPAVServiceProxy` whose `Location` property is `External`.
  - `bool DDCWrite(DDCService *_Nonnull service, uint32_t chip, uint32_t offset, const uint8_t *_Nonnull bytes, size_t length)` and `bool DDCRead(DDCService *_Nonnull service, uint32_t chip, uint32_t offset, uint8_t *_Nonnull out, size_t length)`
  - `bool DDCServiceIdentity(DDCService *_Nonnull service, char *_Nonnull out, size_t capacity)`: text that identifies the display behind the service, chosen in Step 2.
- Consumes: `DDCPacket` from Task 1.

- [ ] Step 1: implement the wrapper. Resolve the three private symbols with `dlsym(RTLD_DEFAULT, ...)` after the package links IOKit. Call `IOAVServiceReadI2C` after a pause of about 50 ms from the write, because the display needs time to answer.
- [ ] Step 2: add a temporary `probe` argument to `main.swift`. For each external service it prints the registry properties of the service and its parents. It also prints the `CGDirectDisplayID` list with vendor, product and serial numbers. Last, it prints the result of a brightness read built with `DDCPacket`.
- [ ] Step 3: run `swift run ExternalDisplayController probe` with the Lenovo connected. Expected: one external service and a brightness reading with a maximum such as 100.
- [ ] Step 4: read the probe output and write a comment at the top of `DisplayDDC.c`. The comment names the property that links a service to a display. The spec expects the EDID vendor, product and serial numbers. The comment also states whether the reply checksum is correct. If the byte offsets differ, fix `parseGetReply` and its test.
- [ ] Step 5: if the symbols are missing or the read always fails, stop and report. Do not continue to Task 3, because the whole design rests on this step.
- [ ] Step 6: commit `feat(external-display-controller): add ddc wrapper`.

### Task 3: Displays and the write queue

Files:
- Create: `Sources/ExternalDisplayController/Displays.swift`

Interfaces:
- Consumes: the Task 1 and Task 2 interfaces.
- Produces:
  - `final class DisplayController: @unchecked Sendable` with `init(service: OpaquePointer, identity: String)`, `func readBrightness(completion: @escaping @Sendable (VCPValue?) -> Void)` and `func setBrightness(_ value: Int)`. Writes go through `LatestValueMailbox<Int>` and a serial `DispatchQueue`. A failed write is dropped with a log line.
  - `struct ExternalDisplay { let displayID: CGDirectDisplayID; let name: String; let controller: DisplayController; var cached: VCPValue }`
  - `@MainActor final class DisplayStore { var displays: [ExternalDisplay]; var state: State; func scan() }` with `enum State { case interfaceUnavailable, noExternalDisplay, ready }`.
  - `func screenID(for point: NSPoint) -> CGDirectDisplayID?` and `func controllableID(for displayID: CGDirectDisplayID) -> CGDirectDisplayID?`, which maps a mirrored screen to the external member of its set.

- [ ] Step 1: implement `scan()`. Read the maximum of each display. If a display does not answer, schedule a retry after each delay in `ScanRetryPolicy.delays`. Scan again on `NSApplication.didChangeScreenParametersNotification` and `NSWorkspace.didWakeNotification`.
- [ ] Step 2: if exactly one external service and one external screen exist and no property matches, pair them. Log the fallback.
- [ ] Step 3: extend the `probe` command to call `setBrightness`, and run it on hardware. Expected: the Lenovo changes brightness, and 20 rapid calls end on the last value.
- [ ] Step 4: commit `feat(external-display-controller): scan displays and queue writes`.

### Task 4: Menu bar item and sliders

Files:
- Modify: `Sources/ExternalDisplayController/main.swift` (remove `probe`, add the app)

Interfaces:
- Consumes: `DisplayStore`, `DisplayController`.
- Produces: `final class AppController: NSObject, NSMenuDelegate` that owns the status item (SF Symbol `sun.max`), the store and, after Task 5, the key tap.

- [ ] Step 1: build the menu in `menuNeedsUpdate`. For each display, add a title item with its name and an item whose view is an `NSSlider` from 0 to the display maximum. For the other states, add the two disabled lines from Global Constraints.
- [ ] Step 2: in `menuWillOpen`, call `readBrightness` for each display. When the answer arrives, update that display's slider. A slider action calls `setBrightness`.
- [ ] Step 3: add a Quit item. Run `swift run ExternalDisplayController`. Expected: a status item appears, the slider moves the Lenovo, and the slider shows a value that you set with the display's own buttons.
- [ ] Step 4: commit `feat(external-display-controller): add menu bar sliders`.

### Task 5: Brightness key tap

Files:
- Create: `Sources/ExternalDisplayController/KeyTap.swift`
- Modify: `Sources/ExternalDisplayController/main.swift`

Interfaces:
- Consumes: `MediaKeyDecoder`, `KeyRouting`, `BrightnessStep`, `DisplayStore`.
- Produces: `@MainActor final class KeyTap` with `init(onBrightnessKey: @escaping (CGDirectDisplayID, Direction) -> Void)`, `func start() -> Bool` and `var isActive: Bool`. If `AXIsProcessTrusted()` is false, `start()` returns false.

- [ ] Step 1: create an active `CGEventTap` (`.cgSessionEventTap`, `.headInsertEventTap`, `.defaultTap`) for system-defined events (type 14). Convert with `NSEvent(cgEvent:)`, accept subtype 8 only, and decode `data1` with `MediaKeyDecoder`.
- [ ] Step 2: for a key-down or a repeat, call `KeyRouting.decide` with the display under `NSEvent.mouseLocation` and the controllable set. For `.consume`, compute the value with `BrightnessStep.next` from the cached value. Then call `setBrightness` and update the cache and the slider. Return nil to drop the event, and drop the matching key-up as well. For `.passThrough`, return the event unchanged.
- [ ] Step 3: if the tap reports `tapDisabledByTimeout` or `tapDisabledByUserInput`, enable it again, and if that fails, set `isActive` false. The menu then shows "Keys need Accessibility" with a link to `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`, and the keys pass through.
- [ ] Step 4: on hardware, grant Accessibility and press F1 and F2 with the pointer on the Lenovo. Expected: the Lenovo changes by 1/16 steps and the built-in screen does not change. With the pointer on the built-in screen, the built-in screen changes as usual.
- [ ] Step 5: commit `feat(external-display-controller): change brightness with the keyboard keys`.

### Task 6: Packaging, README and hardware acceptance

Files:
- Create: `external-display-controller/Info.plist`, `external-display-controller/build-app.sh`, `external-display-controller/.gitignore`
- Modify: `install.sh`, `README.md`

- [ ] Step 1: copy `claude-usage/Info.plist` and `claude-usage/build-app.sh`, and change the names, the identifier and the executable. Use icon symbol `sun.max` and colors `F2C14E` and `D9822B` with `scripts/make-icon.swift`. Copy `.gitignore` from `menu-bar-stats`.
- [ ] Step 2: add `external-display-controller` and `ExternalDisplayController` to the three places in `install.sh` (the argument match, the name map and both usage lines).
- [ ] Step 3: update `README.md` in six places. Add a row to the app table and a section for the app. Add a row to the Permissions table (Accessibility, for the keys only). Add a paragraph to How they work about DDC over the private `IOAVService` interface. Add a line to Limitations (brightness only, private API). Add the app to Project layout.
- [ ] Step 4: run `shellcheck install.sh external-display-controller/build-app.sh`, then `./install.sh external-display-controller`. Expected: no shellcheck output and `Installed /Applications/ExternalDisplayController.app`.
- [ ] Step 5: hardware acceptance on `personal`. Make sure that each item works, and record the result in the commit body. The items are the slider, F1 and F2 with the pointer on the Lenovo, and F1 and F2 with the pointer on the built-in screen. Also test a held key, an unplug and replug of the display, a sleep and wake of the Mac, and Accessibility turned off and on.
- [ ] Step 6: commit `feat(external-display-controller): add install script and readme`.

### Task 7: Dotfiles wiring

Files (in `~/code/greg-cook/dotfiles`):
- Create: `home/Library/LaunchAgents/io.github.greg-cook.external-display-controller.plist`
- Modify: `home/.chezmoiscripts/run_after_70-mac-utils.sh`, `docs/decisions.md`

- [ ] Step 1: after Task 6 is pushed to the mac-utils `main` branch, copy the Claude Usage plist and change the label and the path. In the chezmoi script, add `external-display-controller` to the `for` list and `ExternalDisplayController` to the process `case`. Update the description comment at the top of the script.
- [ ] Step 2: add the app to the mac-utils paragraph in `docs/decisions.md`.
- [ ] Step 3: run `shellcheck home/.chezmoiscripts/run_after_70-mac-utils.sh`. Render into a throwaway home as `CLAUDE.md` describes and make sure that the plist appears. Do not apply to the real `$HOME`.
- [ ] Step 4: commit `feat(mac-utils): install external display controller` and push to `main`.
