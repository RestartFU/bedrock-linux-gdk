#!/usr/bin/env bash
# Keep every project version source synchronized for stable releases.

set -euo pipefail

cd "$(dirname "$0")/.."

bump="${1:-}"
dry_run="${2:-}"

case "$bump" in
  patch|minor|major) ;;
  *)
    printf 'usage: %s {patch|minor|major} [--dry-run]\n' "$0" >&2
    exit 2
    ;;
esac

if [[ -n "$dry_run" && "$dry_run" != --dry-run ]]; then
  printf 'unknown argument: %s\n' "$dry_run" >&2
  exit 2
fi

current=$(sed -nE \
  's/^[[:space:]]*VERSION = "([0-9]+\.[0-9]+\.[0-9]+)"/\1/p' \
  src/bedrock_linux_gdk/version.cr)

if [[ ! "$current" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  printf 'cannot read current semantic version\n' >&2
  exit 1
fi

major="${BASH_REMATCH[1]}"
minor="${BASH_REMATCH[2]}"
patch="${BASH_REMATCH[3]}"

grep -qx "version: $current" shard.yml \
  || { printf 'shard.yml version mismatch\n' >&2; exit 1; }
grep -q "<release version=\"$current\"" \
  data/com.restartfu.BedrockLinuxGdk.metainfo.xml \
  || { printf 'AppStream version mismatch\n' >&2; exit 1; }

case "$bump" in
  patch) patch=$((patch + 1)) ;;
  minor) minor=$((minor + 1)); patch=0 ;;
  major) major=$((major + 1)); minor=0; patch=0 ;;
esac

next="$major.$minor.$patch"

if [[ "$dry_run" == --dry-run ]]; then
  printf '%s\n' "$next"
  exit 0
fi

sed -i \
  "s/VERSION = \"$current\"/VERSION = \"$next\"/" \
  src/bedrock_linux_gdk/version.cr
sed -i \
  "0,/^version: $current\$/s//version: $next/" \
  shard.yml
sed -i \
  "/<releases>/a\\    <release version=\"$next\" date=\"$(date -u +%F)\"/>" \
  data/com.restartfu.BedrockLinuxGdk.metainfo.xml

printf '%s\n' "$next"
