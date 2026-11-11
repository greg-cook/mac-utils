# mac-utils

Small, dependency-free menu bar utilities for macOS, written in Swift and
built from source with the Swift Package Manager.

| App | What it does | Needs |
| --- | --- | --- |
| [Menu Bar Manager](#menu-bar-manager) | Hides the menu bar icons of the apps you choose, behind a chevron | macOS 27 |
| [Menu Bar Stats](#menu-bar-stats) | Shows CPU use, network throughput and CPU temperature in the menu bar | macOS 26 |

Both are background apps with no Dock icon or window, use almost no CPU while
idle, collect nothing and make no network connections of their own.

> **Read this first.** Each app relies on a private, undocumented macOS
> interface, because Apple offers no public way to do what it does. They work
> today, but a macOS update can break them. See [How they work](#how-they-work)
> and [Limitations](#limitations). They are not signed with a developer
> certificate or notarised, so you build them yourself rather than download a
> binary.

## Contents

- [Requirements](#requirements)
- [Install](#install)
- [Menu Bar Manager](#menu-bar-manager)
- [Menu Bar Stats](#menu-bar-stats)
- [Permissions](#permissions)
- [Start at login](#start-at-login)
- [Update and uninstall](#update-and-uninstall)
- [How they work](#how-they-work)
- [Limitations](#limitations)
- [Troubleshooting](#troubleshooting)
- [Project layout](#project-layout)
- [Development](#development)
- [Licence](#licence)

## Requirements

- An Apple silicon Mac. Menu Bar Stats' temperature reading is Apple silicon
  only; the rest has not been tried on Intel.
- macOS 27 for Menu Bar Manager, macOS 26 for Menu Bar Stats.
- A Swift 6.2 toolchain: Xcode 26 or later, or the Command Line Tools
  (`xcode-select --install`). The icon is drawn at build time with
  `swift` and `iconutil`, both included.

## Install

```bash
git clone https://github.com/greg-cook/mac-utils.git
cd mac-utils
./install.sh menu-bar-manager
./install.sh menu-bar-stats
```

`install.sh` builds a release binary, wraps it in an app bundle signed ad hoc
for local use, copies it to `/Applications`, and starts it. It replaces and
restarts the app if it is already installed.

Add `--login` to also start the app every time you log in, see
[Start at login](#start-at-login):

```bash
./install.sh --login menu-bar-manager
```

To build without installing, run `menu-bar-manager/build-app.sh` or
`menu-bar-stats/build-app.sh`. The app is written to that folder's `build/`
directory.

## Menu Bar Manager

Hides the icons you do not need every day. A chevron sits in the menu bar:

- **Click** it to show or hide the hidden icons.
- **Right-click** it for a menu of the running apps that have a menu bar icon.
  A tick means the app's icon is hidden. Choose an app to hide or show it.
- The hidden icons **hide again by themselves** five seconds after the pointer
  leaves the menu bar. The timer waits while any menu is open.

macOS's own items (Control Centre, clock and so on) and the chevron itself are
never hidden.

### Choosing what stays visible

The list of apps that stay visible is a plain text file, one
[bundle identifier](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleidentifier)
per line:

```
~/.config/menu-bar-manager/visible-apps
```

```text
# Anything after a # is ignored.
com.1password.1password            # 1Password
com.knollsoft.Rectangle            # Rectangle
# org.pqrs.Karabiner-Console-User-Server  # commented out, so this icon is hidden
```

Everything **not** listed is hidden. An empty or missing file hides every
third-party icon.

- Find an app's identifier with `osascript -e 'id of app "App Name"'`.
- The file is read each time the icons hide, so edits apply without a restart.
- The right-click menu edits this file for you. It comments a line out or back
  in, and appends a line for an app it has not seen, leaving your other
  comments alone. If you keep the file in a dotfiles repo, commit the change.

The right-click menu needs the [Accessibility permission](#permissions). Hiding
itself does not.

## Menu Bar Stats

Three separate menu bar items, refreshed every 3 seconds, plus an
[optional clock](#optional-clock):

| Item | Shows |
| --- | --- |
| CPU | Share of time all cores were busy |
| Network | Upload and download rates, in bits per second |
| Temperature | The hottest CPU die sensor, in °C |

Click **CPU** or **Network** for the five busiest processes by that measure.
The list refreshes while the menu is open and costs nothing while it is closed.
Click any item for **Quit**.

The network figure counts Wi-Fi and wired (`en*`) interfaces only. VPN tunnels
carry the same bytes that cross a physical interface, so including them would
count every byte twice.

### Optional clock

Create `~/.config/menu-bar-stats/clock` and Menu Bar Stats adds a fourth item
with the time in a zone of your choice, such as `London 14:05`. Click it for the
full date and zone. The file holds an
[IANA time zone identifier](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones)
on its first line that is not a comment:

```bash
mkdir -p ~/.config/menu-bar-stats
echo 'Europe/London' > ~/.config/menu-bar-stats/clock
```

```text
# Anything after a # is ignored.
America/New_York    # shown as "New York"
```

- The name in the menu bar is the last part of the identifier, with underscores
  turned into spaces.
- An empty file shows the time in the Mac's own zone.
- An unrecognised identifier shows no clock and logs a message.
- The file is read when the app starts, so restart the app after changing it.
- Only one clock is supported.

## Permissions

| App | Permission | Why | Required? |
| --- | --- | --- | --- |
| Menu Bar Manager | Accessibility | The right-click menu asks each app whether it has a menu bar icon | Only for the right-click menu |
| Menu Bar Stats | None | | |

To grant it, open the right-click menu and choose **Allow Accessibility to List
Apps…**, or go to System Settings → Privacy & Security → Accessibility.

The apps are signed ad hoc, so macOS sees every rebuild as a different app and
may ask again. If the switch is on but the menu still asks, switch it off and on
again, or remove the app from the list and re-add it.

## Start at login

`./install.sh --login <app>` writes a LaunchAgent to
`~/Library/LaunchAgents/io.github.greg-cook.<app>.plist` and loads it. You can
instead add the app under System Settings → General → Login Items.

## Update and uninstall

Update by pulling and running `install.sh` again:

```bash
git pull
./install.sh menu-bar-manager
```

Uninstall removes the app, its LaunchAgent and nothing else:

```bash
./install.sh --uninstall menu-bar-manager
```

Your `~/.config/menu-bar-*` files are left in place.

## How they work

**Menu Bar Manager** uses the menu bar restriction that macOS 27 introduced for
exam lockdown mode. It is an allow-list: while active, only the apps on it keep
their icons. The app loads Apple's private `MenuBarClientCore` framework at
runtime and activates a restriction listing the bundle identifiers from
`visible-apps`, plus its own. Hiding is therefore real: the icons are removed,
not pushed off-screen. Showing them again, or quitting the app, lifts the
restriction.

This is used rather than the common approach of an oversized status item
because macOS 27 drops an over-wide status item instead of letting it push other
icons off the bar. If the framework is missing or changed, the app still starts;
the chevron beeps and hiding is unavailable.

macOS 27 also draws every app's icon inside one system window, so the window
list cannot say whose icon is whose. The right-click menu works around this by
asking each running app, through Accessibility, whether it has an *extras menu
bar*, which only apps with a menu bar icon do. That is why it needs the
permission.

**Menu Bar Stats** reads:

- **CPU:** `host_statistics` with `HOST_CPU_LOAD_INFO`, the same counters
  Activity Monitor uses. Public API.
- **Network:** `getifaddrs` byte counters on `en*` interfaces. Public API.
- **Temperature:** the maximum across the CPU die sensors, read through
  IOKit's private HID event API. Apple silicon has no public temperature API,
  and the public HID client lists the sensors but returns no readings.
- **Top processes:** `/bin/ps` for CPU and `/usr/bin/nettop` for network,
  started only while a menu is open. `ps` is setuid root, so it can see system
  daemons that the app itself cannot; `nettop` is the only source of
  per-process traffic, as no public API reports it.

## Limitations

- **Private APIs.** A macOS update can change or remove them. When that
  happens the affected feature stops working (Manager cannot hide; Stats shows
  `–°` for temperature) rather than crashing the app. Please open an issue
  with your macOS version.
- **One list.** Manager has a single list of visible apps. There is no
  per-display or per-space setting.
- **No Intel temperature**, and no fan speed, disk, memory or battery readings.
- **No preferences window.** Everything is configured with the files above.
- **Not for the Mac App Store.** Private APIs rule that out, and the apps are
  not notarised.

## Troubleshooting

**Menu Bar Manager's chevron beeps and nothing hides.**
Check the log: `log show --last 5m --predicate 'eventMessage CONTAINS "MenuBarManager"'`.
A message that the restriction API is unavailable means macOS no longer has the
interface (or you are on a release older than macOS 27).

**An icon I listed is hidden anyway, or one I did not list is showing.**
The identifier is probably wrong. Confirm it with `osascript -e 'id of app "Name"'`.
Some apps have a helper that owns the icon, with its own identifier.

**The right-click menu only offers "Allow Accessibility to List Apps…".**
See [Permissions](#permissions); the grant is lost on each rebuild.

**Temperature shows `–°`.**
The sensors could not be read. This is expected on Intel Macs and may mean macOS
changed the private interface.

**Menu bar items are in the wrong order.**
macOS positions items itself. Hold Cmd and drag an item to move it; the
position is remembered.

**The build fails with a platform or tools-version error.**
Check `swift --version` is 6.2 or later and run `xcode-select -p` to confirm it
points at a current Xcode or Command Line Tools.

## Project layout

```
install.sh                     build, install, start, uninstall
scripts/make-icon.swift        draws an app icon from an SF Symbol
menu-bar-manager/
  Package.swift
  Info.plist
  build-app.sh                 builds MenuBarManager.app into build/
  Sources/MenuBarManager/      the app (AppKit)
  Sources/MenuBarRestriction/  Objective-C wrapper for the private restriction API
menu-bar-stats/
  Package.swift
  Info.plist
  build-app.sh                 builds MenuBarStats.app into build/
  Sources/MenuBarStats/        the app (AppKit): samplers, drawing, menus
  Sources/DieSensors/          C wrapper for the private temperature API
```

Each app is its own Swift package with no third-party dependencies. The app
bundles are identified as `io.github.greg-cook.menu-bar-manager` and
`io.github.greg-cook.menu-bar-stats`.

## Development

```bash
cd menu-bar-stats
swift build              # debug build
swift run MenuBarStats   # run without installing
```

Quit any installed copy first. Two copies would show duplicate items.

Run `shellcheck` over any shell script you change. Pull requests are welcome;
for anything larger than a fix, please open an issue first. Because the apps
rely on private APIs, say which macOS version you tested on.

## Licence

[MIT](LICENSE) © Greg Cook
