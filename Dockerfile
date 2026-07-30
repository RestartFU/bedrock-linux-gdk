# syntax=docker/dockerfile:1
#
# Docker is the supported build environment. The exported bundle includes its
# complete GTK/libadwaita library closure and runs on glibc x86_64 systems,
# including NixOS hosts without a conventional /lib64 loader.

FROM debian:bullseye-slim@sha256:cba95a21c96c1f5fc2470081829363eed57706634f7dc26e8c6712934303d57a AS winegdk-runtime

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      bison \
      build-essential \
      ca-certificates \
      flex \
      g++-mingw-w64-x86-64 \
      gcc-mingw-w64-x86-64 \
      git \
      pkg-config \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /source
RUN git init \
 && git remote add origin https://github.com/LukasPAH/WineGDK.git \
 && git fetch --depth=1 origin 75637b674e1f191e65753663c4c0c32bea05ba6e \
 && test "$(git rev-parse FETCH_HEAD)" = 75637b674e1f191e65753663c4c0c32bea05ba6e \
 && git checkout --detach FETCH_HEAD
COPY patches/winegdk-launcher-auth.patch /tmp/winegdk-launcher-auth.patch
RUN git apply --unidiff-zero --check /tmp/winegdk-launcher-auth.patch \
 && git apply --unidiff-zero /tmp/winegdk-launcher-auth.patch

WORKDIR /build
RUN /source/configure \
      --enable-win64 \
      --without-alsa \
      --without-cups \
      --without-dbus \
      --without-fontconfig \
      --without-freetype \
      --without-gphoto \
      --without-gstreamer \
      --without-krb5 \
      --without-netapi \
      --without-oss \
      --without-pcap \
      --without-pulse \
      --without-sane \
      --without-sdl \
      --without-udev \
      --without-usb \
      --without-v4l2 \
      --without-wayland \
      --without-x \
 && make -j2 dlls/xgameruntime/x86_64-windows/xgameruntime.dll

RUN mkdir -p /runtime/out \
 && install -m0644 \
      /build/dlls/xgameruntime/x86_64-windows/xgameruntime.dll \
      /runtime/out/xgameruntime.dll \
 && install -m0644 /source/COPYING.LIB /runtime/out/COPYING.WineGDK

FROM crystallang/crystal:1.21.0@sha256:32b7b908a8c3625ebd629053daf48b6f469deaf74aeb71ad101895096b1665fa AS toolchain

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      gir1.2-adw-1 \
      gir1.2-gtk-4.0 \
      gobject-introspection \
      libgirepository1.0-dev \
      libgtk-4-dev \
      libadwaita-1-dev \
 && rm -rf /var/lib/apt/lists/*

FROM toolchain AS crystal

ARG PROFILE=default
ARG COMMIT=

WORKDIR /src
COPY shard.yml shard.lock ./
RUN shards install --production --frozen
COPY bindings ./bindings
RUN ./bin/gi-crystal

COPY src ./src
COPY spec ./spec

RUN test "$PROFILE" = default || test "$PROFILE" = nightly \
 && BEDROCK_BUILD_PROFILE="$PROFILE" BEDROCK_BUILD_COMMIT="$COMMIT" \
      crystal spec --error-trace \
 && mkdir -p /crystal-build \
 && BEDROCK_BUILD_PROFILE="$PROFILE" BEDROCK_BUILD_COMMIT="$COMMIT" \
      crystal build src/bedrock_linux_gdk.cr \
        --release --no-debug -o /crystal-build/bedrock-linux-gdk \
 && BEDROCK_BUILD_PROFILE="$PROFILE" BEDROCK_BUILD_COMMIT="$COMMIT" \
      crystal build src/bedrock_linux_gdk_engine.cr \
        --release --no-debug -o /crystal-build/bedrock-linux-gdk-engine \
 && /crystal-build/bedrock-linux-gdk --version

FROM crystal AS test

FROM debian:trixie-slim@sha256:020c0d20b9880058cbe785a9db107156c3c75c2ac944a6aa7ab59f2add76a7bd AS bundle-tools

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      adwaita-icon-theme \
      ca-certificates \
      desktop-file-utils \
      file \
      fontconfig \
      fonts-cantarell \
      fonts-dejavu-core \
      fonts-inter \
      fonts-jetbrains-mono \
      fonts-noto-color-emoji \
      glib-networking \
      libegl-mesa0 \
      libegl1 \
      libgl1-mesa-dri \
      libadwaita-1-dev \
      libgtk-4-dev \
      libssl-dev \
      libx11-data \
      librsvg2-common \
      openssl \
      patchelf \
      shared-mime-info \
      xkb-data \
 && rm -rf /var/lib/apt/lists/*

FROM bundle-tools AS staging

ARG PROFILE=default

WORKDIR /src
COPY data ./data
COPY scripts/bundle.sh /usr/local/bin/bundle.sh
COPY scripts/bedrock-linux-gdk.sh /usr/local/share/bedrock-linux-gdk.sh
COPY --from=crystal /crystal-build/bedrock-linux-gdk /stage/usr/bin/bedrock-linux-gdk
COPY --from=crystal /crystal-build/bedrock-linux-gdk-engine /stage/usr/bin/bedrock-linux-gdk-engine
COPY --from=winegdk-runtime /runtime/out /stage/usr/libexec/bedrock-linux-gdk

RUN set -eux; \
    install -m0755 /usr/bin/openssl /stage/usr/bin/openssl; \
    test "$PROFILE" = default || test "$PROFILE" = nightly; \
    if [ "$PROFILE" = nightly ]; then \
      app_id=com.restartfu.BedrockLinuxGdk.Nightly; \
      app_name='Bedrock Linux GDK (Nightly)'; \
    else \
      app_id=com.restartfu.BedrockLinuxGdk; \
      app_name='Bedrock Linux GDK'; \
    fi; \
    install -d \
      /stage/usr/share/applications \
      /stage/usr/share/icons/hicolor/512x512/apps; \
    sed \
      -e "s|^Name=.*|Name=$app_name|" \
      -e "s|^Icon=.*|Icon=$app_id|" \
      -e "s|^StartupWMClass=.*|StartupWMClass=$app_id|" \
      data/com.restartfu.BedrockLinuxGdk.desktop \
      > "/stage/usr/share/applications/$app_id.desktop"; \
    install -m0644 \
      data/icons/hicolor/512x512/apps/com.restartfu.BedrockLinuxGdk.png \
      "/stage/usr/share/icons/hicolor/512x512/apps/$app_id.png"; \
    desktop-file-validate "/stage/usr/share/applications/$app_id.desktop"; \
    bash /usr/local/bin/bundle.sh \
      /stage /out /usr/local/share/bedrock-linux-gdk.sh

FROM scratch AS bundle

COPY --from=staging /out /
