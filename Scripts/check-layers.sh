#!/usr/bin/env bash
# Layer lint for the Foundation-only core.
#
# 1. Linea/Core must not import Apple UI/persistence frameworks — the Docker
#    build would fail anyway, but this gives a readable error in seconds.
# 2. Engines must not read ambient time/locale: everything comes through
#    `TimeContext`, otherwise tests are not reproducible (the Docker container
#    runs in UTC, the user's phone does not).
set -euo pipefail
cd "$(dirname "$0")/.."

status=0

echo "• Apple framework imports inside Linea/Core"
if grep -rnE '^\s*import (SwiftUI|SwiftData|HealthKit|UIKit|EventKit|UserNotifications|BackgroundTasks|FoundationModels|Observation|CoreData|Speech|AVFoundation|AVFAudio|CoreMedia|OSLog)\b' Linea/Core; then
  echo "  ✗ Core must stay Foundation-only"; status=1
else
  echo "  ✓ none"
fi

echo "• Ambient time/locale inside engines (Intelligence, UseCases, Connectors)"
# Domain/Models may use `Date()` as an initializer default (called by UI);
# engines and use cases must take time from TimeContext.
ENGINE_DIRS=(Linea/Core/Intelligence Linea/Core/Domain/UseCases Linea/Core/Connectors)
if grep -rnE 'Date\(\)|Calendar\.current|TimeZone\.current|Locale\.current|Locale\.autoupdatingCurrent|Calendar\.autoupdatingCurrent' "${ENGINE_DIRS[@]}" 2>/dev/null; then
  echo "  ✗ use TimeContext instead"; status=1
else
  echo "  ✓ none"
fi

echo "• Tests must live outside Linea/ (synchronized Xcode group)"
if find Linea -name '*Tests.swift' -o -path 'Linea/*Tests*' | grep -q .; then
  echo "  ✗ move tests to Tests/"; status=1
else
  echo "  ✓ ok"
fi

exit $status
