#!/usr/bin/env bash
# Build and export a self-contained Linux bundle. Docker is the only host
# dependency.

set -euo pipefail

cd "$(dirname "$0")/.."

commit=$(git rev-parse --short HEAD 2>/dev/null || true)

rm -rf dist
docker buildx build \
  --target bundle \
  --build-arg COMMIT="$commit" \
  --output "type=local,dest=dist" \
  "$@" \
  .

printf '\nBundle ready:\n  ./dist/bedrock-linux-gdk.sh\n'
