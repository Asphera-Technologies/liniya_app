#!/usr/bin/env bash
# Builds and tests the Foundation-only core (Linea/Core + Tests/) in Docker.
# Works on any machine with Docker — no Xcode or local Swift required.
#
# Usage: Scripts/test-core.sh [extra swift test args, e.g. --filter StateEngine]
set -euo pipefail
cd "$(dirname "$0")/.."

IMAGE="${SWIFT_IMAGE:-swift:6.3}"   # Xcode 26.6 ships Swift 6.3; keep in sync with the project

# -u: otherwise .build/ is created by root and the next run fails with a
#     read-only database error. HOME=/tmp: SwiftPM needs a writable home.
docker run --rm \
  -u "$(id -u):$(id -g)" \
  -e HOME=/tmp \
  -e TZ=UTC \
  -v "$PWD":/src -w /src \
  "$IMAGE" \
  swift test "$@"
