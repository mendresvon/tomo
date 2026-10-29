#!/bin/zsh
# Runs the TimerEngine tests with swiftc and the Swift Testing framework.
# Works with only the Command Line Tools installed (no Xcode needed).
set -euo pipefail

ROOT="${0:A:h:h}"
OUT="$ROOT/.build/tests"
DEV="$(xcode-select -p)"
if [[ -d "$DEV/Platforms/MacOSX.platform" ]]; then
  # Full Xcode layout.
  DEV_LIB="$DEV/Platforms/MacOSX.platform/Developer"
else
  # Command Line Tools layout.
  DEV_LIB="$DEV/Library/Developer"
fi
FRAMEWORKS="$DEV_LIB/Library/Frameworks"
[[ -d "$FRAMEWORKS/Testing.framework" ]] || FRAMEWORKS="$DEV_LIB/Frameworks"
PLUGINS="$DEV/usr/lib/swift/host/plugins/testing"
[[ -d "$PLUGINS" ]] || PLUGINS="$DEV/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/host/plugins/testing"

mkdir -p "$OUT"

swiftc -swift-version 5 -parse-as-library -enable-testing \
  -emit-module -emit-library -static -module-name TomoCore \
  -emit-module-path "$OUT/TomoCore.swiftmodule" -o "$OUT/libTomoCore.a" \
  "$ROOT"/Sources/TomoCore/*.swift

cat > "$OUT/Runner.swift" <<'SWIFT'
import Foundation
import Testing
@main struct Runner { static func main() async { exit(await Testing.__swiftPMEntryPoint()) } }
SWIFT

swiftc -swift-version 5 -parse-as-library -plugin-path "$PLUGINS" \
  -I "$OUT" -L "$OUT" -lTomoCore -F "$FRAMEWORKS" -framework Testing \
  -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
  -Xlinker -rpath -Xlinker "$DEV_LIB/usr/lib" \
  -module-name TomoCoreTests -o "$OUT/run-tests" \
  "$ROOT"/Tests/TomoCoreTests/*.swift "$OUT/Runner.swift"

"$OUT/run-tests"
