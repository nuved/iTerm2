#!/bin/zsh
# Copies the Development build to ~/Applications/iTerm2-RTL.app with its own bundle identifier and a stable signature, so macOS privacy grants (Screen Recording and the like) stay with it across rebuilds and never touch the stock app's grants.
# Usage: tools/rtl-install/install.sh [path to a built iTerm2.app]
# Run it after tools/build.sh. Quit iTerm2-RTL first: the script refuses to replace a running copy.
set -e
dest=~/Applications/iTerm2-RTL.app
bundle_id=com.googlecode.iterm2.rtl
src=$1
if [[ -z $src ]]; then
    src=$(ls -dt ~/Library/Developer/Xcode/DerivedData/iTerm2-*/Build/Products/Development/iTerm2.app 2>/dev/null | head -1)
fi
[[ -d $src ]] || { echo "No built iTerm2.app found. Run tools/build.sh first." >&2; exit 1 }
if pgrep -f "$dest/Contents/MacOS/iTerm2" > /dev/null; then
    echo "iTerm2-RTL is running. Quit it, then run this again." >&2
    exit 1
fi
identity=$(security find-identity -v -p codesigning | awk '/Apple Development/ {print $2; exit}')
[[ -n $identity ]] || { echo "No Apple Development signing identity in the keychain." >&2; exit 1 }
staging=$(mktemp -d)
ditto "$src" "$staging/iTerm2-RTL.app"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $bundle_id" "$staging/iTerm2-RTL.app/Contents/Info.plist"
codesign --force --deep --sign "$identity" "$staging/iTerm2-RTL.app"
codesign --verify --deep --strict "$staging/iTerm2-RTL.app"
if [[ -d $dest ]]; then
    mv "$dest" "$staging/previous.app"
fi
mv "$staging/iTerm2-RTL.app" "$dest"
rm -rf "$staging"
echo "Installed $dest"
echo "Start it with: open -n $dest --args -suite iTerm2-rtl"
