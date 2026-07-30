#!/bin/sh
#
# One-line nightly install:
#
#   curl -fsSL https://github.com/RestartFU/bedrock-linux-gdk/releases/download/nightly/install.sh | sh
#
# Latest tagged release:
#
#   curl -fsSL https://github.com/RestartFU/bedrock-linux-gdk/releases/latest/download/install.sh | sh -s -- --release

set -eu

REPO=RestartFU/bedrock-linux-gdk
CHANNEL=nightly
SOURCE=
UNINSTALL=no

say () { printf '%s\n' "$*"; }
die () { printf 'install: %s\n' "$*" >&2; exit 1; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --release|--stable) CHANNEL=release ;;
    --from) [ "$#" -ge 2 ] || die "--from needs a directory."
            SOURCE=$2
            shift ;;
    --from=*) SOURCE=${1#--from=} ;;
    --uninstall) UNINSTALL=yes ;;
    *) die "unknown argument: $1" ;;
  esac
  shift
done

if [ "$CHANNEL" = release ]; then
  NAME=bedrock-linux-gdk
  APP_ID=com.restartfu.BedrockLinuxGdk
  ASSET=bedrock-linux-gdk-linux-x86_64.tar.gz
  BASE="https://github.com/$REPO/releases/latest/download"
else
  NAME=bedrock-linux-gdk-nightly
  APP_ID=com.restartfu.BedrockLinuxGdk.Nightly
  ASSET=bedrock-linux-gdk-nightly-linux-x86_64.tar.gz
  BASE="https://github.com/$REPO/releases/download/nightly"
fi

DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
OPT="$HOME/.local/opt/$NAME"
BIN="$HOME/.local/bin/$NAME"
DESKTOP="$DATA_HOME/applications/$APP_ID.desktop"
ICON_THEME="$DATA_HOME/icons/hicolor"
ICON_DIR="$ICON_THEME/512x512/apps"

uninstall () {
  rm -rf "$OPT"
  rm -f "$BIN" "$DESKTOP" "$ICON_DIR/$APP_ID.png"
  say "Removed $NAME. BedrockOnLinux game data was not touched."
  exit 0
}

[ "$UNINSTALL" = yes ] && uninstall

[ "$(uname -s)" = Linux ] \
  || die "Linux build cannot install on $(uname -s)."
case "$(uname -m)" in
  x86_64|amd64) ;;
  *) die "only x86_64 is published; found $(uname -m)." ;;
esac

for process_exe in /proc/[0-9]*/exe; do
  executable=$(readlink "$process_exe" 2>/dev/null || true)
  case "$executable" in
    "$OPT"/*)
      die "$NAME is running. Quit it, then rerun installer."
      ;;
  esac
done

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT INT TERM

if [ -n "$SOURCE" ]; then
  [ -x "$SOURCE/bedrock-linux-gdk.sh" ] \
    || die "$SOURCE is not a built bundle."
  [ -f "$SOURCE/share/applications/$APP_ID.desktop" ] \
    || die "$SOURCE is not a $CHANNEL build."
  say "Installing local $CHANNEL build…"
  cp -a "$SOURCE" "$WORK/$NAME"
else
  command -v curl >/dev/null 2>&1 || die "curl is required."
  command -v tar >/dev/null 2>&1 || die "tar is required."
  command -v sha256sum >/dev/null 2>&1 \
    || die "sha256sum is required."

  say "Downloading $CHANNEL build…"
  curl -fsSL --proto '=https' --tlsv1.2 \
    -o "$WORK/$ASSET" "$BASE/$ASSET" \
    || die "cannot download $BASE/$ASSET"
  curl -fsSL --proto '=https' --tlsv1.2 \
    -o "$WORK/$ASSET.sha256" "$BASE/$ASSET.sha256" \
    || die "cannot download checksum"

  (cd "$WORK" && sha256sum -c "$ASSET.sha256" >/dev/null) \
    || die "download checksum mismatch."

  tar -xzf "$WORK/$ASSET" -C "$WORK"
  [ -x "$WORK/$NAME/bedrock-linux-gdk.sh" ] \
    || die "archive payload is invalid."
fi

mkdir -p \
  "$(dirname "$OPT")" \
  "$(dirname "$BIN")" \
  "$(dirname "$DESKTOP")" \
  "$ICON_DIR"

NEW="$OPT.new.$$"
OLD="$OPT.old.$$"
rm -rf "$NEW" "$OLD"
mv "$WORK/$NAME" "$NEW"

if [ -e "$OPT" ]; then
  mv "$OPT" "$OLD"
fi
if ! mv "$NEW" "$OPT"; then
  [ ! -e "$OLD" ] || mv "$OLD" "$OPT"
  die "could not activate new bundle."
fi
rm -rf "$OLD"

ln -sfn "$OPT/bedrock-linux-gdk.sh" "$BIN"
cp -f \
  "$OPT/share/icons/hicolor/512x512/apps/$APP_ID.png" \
  "$ICON_DIR/$APP_ID.png"
sed \
  -e "s|^Exec=.*|Exec=$BIN|" \
  -e "s|^Icon=.*|Icon=$APP_ID|" \
  "$OPT/share/applications/$APP_ID.desktop" > "$DESKTOP"
chmod 0644 "$DESKTOP" "$ICON_DIR/$APP_ID.png"

for cache in gtk4-update-icon-cache gtk-update-icon-cache; do
  if command -v "$cache" >/dev/null 2>&1; then
    "$cache" -q -f -t "$ICON_THEME" 2>/dev/null || true
    break
  fi
done
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$DATA_HOME/applications" 2>/dev/null || true
fi
touch "$ICON_DIR" "$ICON_THEME" "$DATA_HOME/applications" 2>/dev/null || true

VERSION=$("$BIN" --version 2>/dev/null || echo "$NAME")
say ""
say "Installed $VERSION."
say "  app      $OPT"
say "  command  $BIN"
say ""
say "Open it from GNOME search, or run: $NAME"
