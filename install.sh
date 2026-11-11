#!/usr/bin/env bash
# Builds an app, installs it to /Applications and (re)starts it.
#   ./install.sh menu-bar-manager|menu-bar-stats [--login]
# --login also installs a LaunchAgent that starts the app at login.
#   ./install.sh --uninstall menu-bar-manager|menu-bar-stats
set -euo pipefail
cd "$(dirname "$0")"

uninstall=false
login=false
dir=
for arg in "$@"; do
    case $arg in
        --uninstall) uninstall=true ;;
        --login) login=true ;;
        menu-bar-manager|menu-bar-stats) dir=$arg ;;
        *) echo "usage: $0 [--uninstall] [--login] menu-bar-manager|menu-bar-stats" >&2; exit 2 ;;
    esac
done
[[ -n $dir ]] || { echo "usage: $0 [--uninstall] [--login] menu-bar-manager|menu-bar-stats" >&2; exit 2; }

case $dir in
    menu-bar-manager) name=MenuBarManager ;;
    menu-bar-stats) name=MenuBarStats ;;
esac
label=io.github.greg-cook.$dir
plist=$HOME/Library/LaunchAgents/$label.plist

stop() {
    launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
    pkill -x "$name" || true
}

if $uninstall; then
    stop
    rm -f "$plist"
    rm -rf "/Applications/$name.app"
    echo "Removed $name"
    exit 0
fi

"./$dir/build-app.sh"
stop
rm -rf "/Applications/$name.app"
cp -R "$dir/build/$name.app" /Applications/

if $login; then
    mkdir -p "$(dirname "$plist")"
    cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$label</string>
	<key>ProgramArguments</key>
	<array>
		<string>/Applications/$name.app/Contents/MacOS/$name</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
</dict>
</plist>
PLIST
    launchctl bootstrap "gui/$(id -u)" "$plist"
else
    open "/Applications/$name.app"
fi
echo "Installed /Applications/$name.app"
