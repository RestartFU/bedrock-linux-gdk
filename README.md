# Bedrock Linux GDK

Native Crystal launcher for Minecraft Bedrock Windows GDK on Linux.

Built with the same application stack as
[`RestartFU/xd`'s Crystal rewrite](https://github.com/RestartFU/xd/tree/rewrite/crystal-unified-daemon):

- Crystal
- GTK4 through `gtk4.cr`
- libadwaita through `gi-crystal`
- custom modern-black GTK CSS
- Meson and Shards

The client intentionally keeps
[BedrockOnLinux](https://github.com/Wyze3306/BedrockOnLinux) as its execution
backend. Login, WineGDK setup, archive verification, prefix safety, GPU
mitigations and multiplayer pre-auth stay in the reviewed backend instead of
being duplicated in UI code.

## Features

- Native GTK4/libadwaita interface
- Stable and preview Minecraft version picker
- Install, update and launch workflows
- Microsoft sign-in status and login
- Independent concurrent sessions with separate accounts, prefixes, worlds
  and game files
- Compatible BedrockOnLinux settings editor
- System, network and Wine-prefix diagnostics
- Live activity output with cancellation
- Native and Flatpak backend discovery
- Original modern voxel portal-block app icon

Concurrent sessions intentionally use separate game data roots. BedrockOnLinux
profiles share multi-gigabyte assets and therefore serialize launches for
runtime safety; bypassing that lock risks cross-session repair/update races.
Independent roots cost more disk space but make simultaneous play safe.

## Requirements

- Crystal 1.19 or newer
- Shards
- GTK 4.10 or newer
- libadwaita 1.4 or newer
- `gobject-introspection`
- A working BedrockOnLinux installation

## Build

Docker is the supported build environment. Host only needs Docker:

```sh
make build
./dist/bedrock-linux-gdk.sh
```

Build output is a relocatable x86_64 bundle containing Crystal, GTK4,
libadwaita and their complete runtime library closure. It runs on regular
glibc distributions and NixOS.

## One-line install

Rolling nightly:

```sh
curl -fsSL https://github.com/RestartFU/bedrock-linux-gdk/releases/download/nightly/install.sh | sh
```

Latest tagged release:

```sh
curl -fsSL https://github.com/RestartFU/bedrock-linux-gdk/releases/latest/download/install.sh | sh -s -- --release
```

Local bundle:

```sh
./scripts/install.sh --from ./dist
```

Uninstall nightly:

```sh
curl -fsSL https://github.com/RestartFU/bedrock-linux-gdk/releases/download/nightly/install.sh | sh -s -- --uninstall
```

## Tests

```sh
make test
```

Tests also run entirely in Docker.

## Updates

Header update button checks current channel. Release builds track latest
semantic release; nightly builds track rolling `nightly` commit. Clicking an
available update exits cleanly and reruns same atomic installer.

## Backend selection

Discovery order:

1. `BEDROCK_LINUX_GDK_BACKEND=/absolute/path/to/bedrock-on-linux`
2. Native `bedrock-on-linux` from `PATH`
3. `io.github.wyze3306.BedrockOnLinux` Flatpak

The Flatpak invocation does not hard-code `stable` or `master`, so it works
with either installation channel.

## Data compatibility

The app reads and merges the backend's existing `settings.json`; unknown keys
are preserved. It also follows `BOL_HOME`, XDG paths, Flatpak private paths and
the backend's persistent `install_location` pointer.

## License

MIT
