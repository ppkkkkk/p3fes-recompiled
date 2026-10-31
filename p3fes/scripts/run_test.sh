#!/bin/bash
# Headless test run on Linux: starts the port under Xvfb for a fixed time, optionally taking screenshots.
#
#   run_test.sh <name> <seconds> [screenshot times in seconds...]
#
# P3FES_GAME_DIR   folder with SLUS_216.21, SYSTEM.CNF, LIB31/ and the .CVM files (default: current folder)
# P3FES_RUNNER     the built ps2EntryRunner (default: build-linux/ps2xRuntime/ps2EntryRunner next to this repository)
# P3FES_SHOTS_DIR  where screenshots go (default: <game dir>/shots)
# Other PS2X_* variables pass through (PS2X_PAD_SCRIPT, PS2X_PCSX2_SHOTS, ...). The log is <game dir>/<name>.log.
set -u
name=$1; secs=$2; shift 2; shots="$*"
repo=$(cd "$(dirname "$0")/../.." && pwd)
game=${P3FES_GAME_DIR:-$PWD}
runner=${P3FES_RUNNER:-$repo/build-linux/ps2xRuntime/ps2EntryRunner}
shotdir=${P3FES_SHOTS_DIR:-$game/shots}
cd "$game" || exit 1

pkill -f "Xvfb :99" 2>/dev/null; sleep 0.5
Xvfb :99 -screen 0 1280x800x24 >/dev/null 2>&1 &
XPID=$!
sleep 1
export DISPLAY=:99 PS2X_CALLBACK_STACK_TOP=${PS2X_CALLBACK_STACK_TOP:-0x100000} PS2X_HIDE_DEBUG_UI=${PS2X_HIDE_DEBUG_UI:-1}
"$runner" "$game/SLUS_216.21" > "$game/$name.log" 2>&1 &
RPID=$!
start=$(date +%s)
[ -n "$shots" ] && mkdir -p "$shotdir"
for t in $shots; do
  while [ $(( $(date +%s) - start )) -lt "$t" ]; do sleep 1; done
  import -window root "$shotdir/${name}_$t.png" 2>/dev/null
done
while [ $(( $(date +%s) - start )) -lt "$secs" ]; do sleep 1; kill -0 $RPID 2>/dev/null || break; done
kill $RPID 2>/dev/null; sleep 1; kill -9 $RPID 2>/dev/null
kill $XPID 2>/dev/null
echo done
