#!/bin/sh
# Relocatable bundle launcher. Starts the bundled loader and library closure
# without exporting LD_LIBRARY_PATH into host tools started by the launcher.

set -eu

if ! pwd -P >/dev/null 2>&1; then
  cd "${HOME:-/}" 2>/dev/null || cd /
fi

HERE=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
RUNTIME="${XDG_RUNTIME_DIR:-/tmp}/bedrock-linux-gdk-$(id -u)/$(basename "$HERE")"
mkdir -p "$RUNTIME"

sed "s|@BUNDLE@|$HERE|g" "$HERE/etc/loaders.cache.in" \
  > "$RUNTIME/loaders.cache"
sed "s|@BUNDLE@|$HERE|g" "$HERE/etc/fonts.conf.in" \
  > "$RUNTIME/fonts.conf"
sed "s|@BUNDLE@|$HERE|g" "$HERE/etc/egl_vendor.json.in" \
  > "$RUNTIME/egl_vendor.json"

# Preserve values needed by host subprocesses before isolating GTK.
export BEDROCK_HOST_XDG_DATA_DIRS="${XDG_DATA_DIRS-}"
export BEDROCK_HOST_LANG="${LANG-}"
export BEDROCK_HOST_LC_ALL="${LC_ALL-}"

unset GIO_EXTRA_MODULES GI_TYPELIB_PATH GTK_PATH GTK_MODULES GTK_IM_MODULE_FILE
unset GTK_EXE_PREFIX GTK_DATA_PREFIX LOCALE_ARCHIVE GTK_THEME
unset NIX_GSETTINGS_OVERRIDES_DIR

export GIO_MODULE_DIR="$HERE/lib/gio/modules"
export GTK_IM_MODULE=gtk-im-context-simple
export FONTCONFIG_PATH="$HERE/etc/fonts"
export FONTCONFIG_FILE="$RUNTIME/fonts.conf"
export XKB_CONFIG_ROOT="$HERE/share/X11/xkb"
export XLOCALEDIR="$HERE/share/X11/locale"
export LC_ALL=C.UTF-8
export LANG=C.UTF-8
export LOCPATH="$HERE/share/locale-data"
export GDK_PIXBUF_MODULE_FILE="$RUNTIME/loaders.cache"
export GSETTINGS_SCHEMA_DIR="$HERE/share/glib-2.0/schemas"
export XDG_DATA_DIRS="$HERE/share:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
export XCURSOR_PATH="$HERE/share/icons:${XCURSOR_PATH:-$HOME/.icons:/usr/share/icons}"
export GSETTINGS_BACKEND="${GSETTINGS_BACKEND:-keyfile}"
export SSL_CERT_FILE="$HERE/etc/ssl/certs/ca-certificates.crt"
export OPENSSL_CONF="$HERE/etc/ssl/openssl.cnf"
export OPENSSL_MODULES="$HERE/lib/ossl-modules"
export GSK_RENDERER="${GSK_RENDERER:-ngl}"
export __EGL_VENDOR_LIBRARY_FILENAMES="$RUNTIME/egl_vendor.json"
export LIBGL_DRIVERS_PATH="$HERE/lib/dri"
export PATH="$HERE/bin:$PATH"
export BEDROCK_LINUX_GDK_RUNTIME_DIR="$HERE/libexec/bedrock-linux-gdk"

exec "$HERE/lib/ld-linux-x86-64.so.2" \
  --library-path "$HERE/lib" \
  "$HERE/bin/bedrock-linux-gdk" "$@"
