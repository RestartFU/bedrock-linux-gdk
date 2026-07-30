# syntax=docker/dockerfile:1
#
# Docker is the supported build environment. The exported bundle includes its
# complete GTK/libadwaita library closure and runs on glibc x86_64 systems,
# including NixOS hosts without a conventional /lib64 loader.

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

RUN set -eux; \
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
