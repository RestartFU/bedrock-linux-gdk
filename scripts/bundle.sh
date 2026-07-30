#!/usr/bin/env bash
# Assemble a relocatable bundle from a staging tree.

set -euo pipefail

stage="${1:?staging dir}"
out="${2:?output dir}"
launcher="${3:?launcher template}"

arch_dir=/usr/lib/x86_64-linux-gnu
pixbuf_loaders="$arch_dir/gdk-pixbuf-2.0/2.10.0/loaders"

mkdir -p "$out"/{bin,lib,share,etc}
mkdir -p "$out/lib/gio/modules" "$out/lib/ossl-modules"
cp -a "$arch_dir"/ossl-modules/*.so "$out/lib/ossl-modules/" 2>/dev/null || true

install -Dm755 \
  "$stage/usr/bin/bedrock-linux-gdk" \
  "$out/bin/bedrock-linux-gdk"
install -Dm755 \
  "$stage/usr/bin/bedrock-linux-gdk-engine" \
  "$out/bin/bedrock-linux-gdk-engine"

mkdir -p "$out/lib/gdk-pixbuf-2.0/loaders"
cp -a "$pixbuf_loaders"/*.so "$out/lib/gdk-pixbuf-2.0/loaders/"

query_loaders=$(command -v gdk-pixbuf-query-loaders \
  || echo "$arch_dir/gdk-pixbuf-2.0/gdk-pixbuf-query-loaders")
"$query_loaders" \
  | sed "s|$pixbuf_loaders|@BUNDLE@/lib/gdk-pixbuf-2.0/loaders|g" \
  > "$out/etc/loaders.cache.in"

mapfile -t roots < <(printf '%s\n' \
  "$out/bin/bedrock-linux-gdk" \
  "$out/bin/bedrock-linux-gdk-engine" \
  "$out/lib/ossl-modules"/*.so \
  "$out/lib/gdk-pixbuf-2.0/loaders"/*.so \
  "$arch_dir"/libnss_files.so.2 \
  "$arch_dir"/libnss_dns.so.2)

for root in "${roots[@]}"; do
  [ -e "$root" ] || continue
  LD_LIBRARY_PATH="$out/lib" \
    ldd "$root" 2>/dev/null | awk '/=> \//{print $3}'
done | sort -u | while read -r library; do
  cp -Ln "$library" "$out/lib/" 2>/dev/null || true
done

for extra in "$arch_dir"/libnss_files.so.2 "$arch_dir"/libnss_dns.so.2; do
  [ -e "$extra" ] && cp -Ln "$extra" "$out/lib/" || true
done
cp -L "$arch_dir/ld-linux-x86-64.so.2" "$out/lib/ld-linux-x86-64.so.2"

mkdir -p "$out/share/glib-2.0/schemas"
cp -a /usr/share/glib-2.0/schemas/*.xml \
  "$out/share/glib-2.0/schemas/" 2>/dev/null || true
glib-compile-schemas "$out/share/glib-2.0/schemas"

mkdir -p "$out/share/icons"
cp -a /usr/share/icons/Adwaita "$out/share/icons/"
cp -a /usr/share/icons/hicolor "$out/share/icons/"
cp -a "$stage/usr/share/icons/hicolor/." "$out/share/icons/hicolor/"
gtk4-update-icon-cache -q -t -f "$out/share/icons/hicolor" 2>/dev/null || true

cp -a /usr/share/mime "$out/share/mime"
mkdir -p "$out/share/X11"
cp -a /usr/share/X11/xkb "$out/share/X11/xkb"
[ -d /usr/share/X11/locale ] \
  && cp -a /usr/share/X11/locale "$out/share/X11/locale"

mkdir -p "$out/share/locale-data"
cp -a /usr/lib/locale/C.utf8 "$out/share/locale-data/"

cp -a "$arch_dir"/gio/modules/*.so "$out/lib/gio/modules/" 2>/dev/null || true
for module in "$out/lib/gio/modules"/*.so; do
  [ -e "$module" ] || continue
  ldd "$module" 2>/dev/null | awk '/=> \//{print $3}'
done | sort -u | while read -r library; do
  base=$(basename "$library")
  [ -e "$out/lib/$base" ] || cp -aL "$library" "$out/lib/"
done

for library in "$arch_dir"/libEGL.so.1* "$arch_dir"/libEGL_mesa.so.0* \
               "$arch_dir"/libGLdispatch.so.0* "$arch_dir"/libgbm.so.1* \
               "$arch_dir"/libglapi.so.0* "$arch_dir"/libGLESv2.so.2* \
               "$arch_dir"/libGL.so.1* "$arch_dir"/libGLX.so.0*; do
  [ -e "$library" ] && cp -a "$library" "$out/lib/"
done
mkdir -p "$out/lib/dri"
cp -aL "$arch_dir"/dri/*.so "$out/lib/dri/" 2>/dev/null || true
for library in $(ldd "$arch_dir"/libEGL_mesa.so.0 "$out"/lib/dri/*.so \
  2>/dev/null | awk '/=> \//{print $3}' | sort -u); do
  base=$(basename "$library")
  [ -e "$out/lib/$base" ] || cp -a "$library" "$out/lib/"
done
cat > "$out/etc/egl_vendor.json.in" <<'JSON'
{
  "file_format_version": "1.0.0",
  "ICD": {"library_path": "@BUNDLE@/lib/libEGL_mesa.so.0"}
}
JSON

mkdir -p "$out/share/fonts"
for directory in \
  /usr/share/fonts/opentype/cantarell \
  /usr/share/fonts/truetype/dejavu \
  /usr/share/fonts/truetype/inter \
  /usr/share/fonts/opentype/inter \
  /usr/share/fonts/truetype/jetbrains-mono \
  /usr/share/fonts/truetype/noto; do
  [ -d "$directory" ] && cp -a "$directory" "$out/share/fonts/"
done

mkdir -p "$out/etc/fonts"
cp -rL /etc/fonts/conf.d "$out/etc/fonts/conf.d"
cat > "$out/etc/fonts.conf.in" <<'EOF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<fontconfig>
  <dir>@BUNDLE@/share/fonts</dir>
  <cachedir prefix="xdg">bedrock-linux-gdk/fontconfig</cachedir>
  <include ignore_missing="yes">@BUNDLE@/etc/fonts/conf.d</include>
</fontconfig>
EOF

mkdir -p "$out/etc/ssl/certs"
cp /etc/ssl/certs/ca-certificates.crt "$out/etc/ssl/certs/"
cp /etc/ssl/openssl.cnf "$out/etc/ssl/openssl.cnf"

mkdir -p "$out/share/applications"
cp -a "$stage/usr/share/applications/." "$out/share/applications/"

install -Dm755 "$launcher" "$out/bedrock-linux-gdk.sh"

printf 'bundle: %s libraries, %s\n' \
  "$(find "$out/lib" -maxdepth 1 -name '*.so*' | wc -l)" \
  "$(du -sh "$out" | cut -f1)"
