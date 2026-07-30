# Bedrock Linux GDK

Native Crystal launcher for Minecraft Bedrock Windows GDK on Linux.

Built with the same application stack as
[`RestartFU/xd`'s Crystal rewrite](https://github.com/RestartFU/xd/tree/rewrite/crystal-unified-daemon):

- Crystal
- GTK4 through `gtk4.cr`
- libadwaita through `gi-crystal`
- custom modern-black GTK CSS
- Shards

Runtime work uses a small command protocol (`versions`, `setup`, `play`,
`login`, `doctor`, `repair`, `update`). Launcher UI and runtime state remain
separate, making long-running game processes non-blocking and independently
testable.

## Features

- Native GTK4/libadwaita interface
- Stable and preview Minecraft version picker
- Install, update and launch workflows
- Microsoft sign-in status and login
- Independent concurrent sessions with separate accounts, prefixes, worlds
  and game files
- Compatible GDK runtime settings editor
- System, network and Wine-prefix diagnostics
- Live activity output with cancellation
- Native runtime discovery
- Original simplified portal-stack app icon

Concurrent sessions intentionally use separate game data roots. Independent
roots cost more disk space, but prevent account, prefix, world and runtime-lock
collisions during simultaneous play.

## Requirements

- Crystal 1.19 or newer
- Shards
- GTK 4.10 or newer
- libadwaita 1.4 or newer
- `gobject-introspection`
- A compatible GDK runtime

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

## Publishing stable releases

Open **Actions → release → Run workflow**, then choose:

- `patch` for `0.0.1`
- `minor` for `0.1.0`
- `major` for `1.0.0`

The workflow updates every version source, commits the bump to `main`, creates
an annotated tag, runs Docker tests/build, checksums the bundle and publishes
a normal GitHub release. Direct `vX.Y.Z` tag pushes remain supported when the
tag already matches the source version.

## Runtime selection

Discovery order:

1. `BEDROCK_LINUX_GDK_BACKEND=/absolute/path/to/runtime`
2. Native `bedrock-linux-gdk-engine` from `PATH`
3. Compatible native runtime registered through a Linux desktop entry

Runtime state stays in launcher-owned session storage for each command.

## Data compatibility

The app reads and merges the backend's existing `settings.json`; unknown keys
are preserved. All launcher-managed state lives under `bedrock-linux-gdk`:

- Native: `${XDG_DATA_HOME:-~/.local/share}/bedrock-linux-gdk`
- Extra sessions: `<data root>/sessions/<session>`

Every runtime command receives its session root through
`BEDROCK_LINUX_GDK_HOME`. Existing runtime state outside `bedrock-linux-gdk`
is not reused, modified or locked.

## License

MIT
