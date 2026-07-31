# Bedrock Linux GDK

Native Crystal/GTK4 launcher for Minecraft Bedrock Windows GDK on Linux.

## Install

Nightly:

```sh
curl -fsSL https://github.com/RestartFU/bedrock-linux-gdk/releases/download/nightly/install.sh | sh
```

Latest stable release:

```sh
curl -fsSL https://github.com/RestartFU/bedrock-linux-gdk/releases/latest/download/install.sh | sh -s -- --release
```

Open **Bedrock Linux GDK** from GNOME search.

## Use

1. Add a Microsoft account and complete browser sign-in.
2. Choose a Minecraft version.
3. Press **Play**. Missing game files install automatically.

Signing in never downloads or starts Minecraft.

Each Microsoft account gets its own profile, worlds, credentials, and Wine
prefix. Minecraft downloads are shared between accounts. Multiple accounts can
run simultaneously.

Use **Uninstall** to remove the selected game version without deleting
accounts or worlds. Folder button opens that account's `com.mojang` game data.

Data lives in:

```text
${XDG_DATA_HOME:-~/.local/share}/bedrock-linux-gdk
```

## Requirements

- x86_64 Linux with Vulkan
- `curl`, `tar`, and `unzip`
- Docker for source builds

## Build and test

```sh
make build
make test
```

Docker is the supported build toolchain. Bundle runs on normal glibc
distributions and NixOS.

## Releases

Nightly builds publish automatically. Stable releases use the manually
triggered `release` workflow with patch, minor, or major version increments.

## Uninstall launcher

```sh
curl -fsSL https://github.com/RestartFU/bedrock-linux-gdk/releases/download/nightly/install.sh | sh -s -- --uninstall
```

## License

MIT. Bundled WineGDK component remains LGPL-2.1.
