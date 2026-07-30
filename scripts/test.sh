#!/usr/bin/env bash
# Run Crystal specs in the pinned Docker toolchain.

set -euo pipefail

cd "$(dirname "$0")/.."
docker build --target test --progress plain "$@" .
