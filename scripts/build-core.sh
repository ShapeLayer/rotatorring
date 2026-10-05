#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cmake -S "$root/core" -B "$root/build/core/host" -DCMAKE_BUILD_TYPE=Release
cmake --build "$root/build/core/host" --config Release
ctest --test-dir "$root/build/core/host" -C Release --output-on-failure
