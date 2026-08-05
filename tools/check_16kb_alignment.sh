#!/usr/bin/env bash
#
# check_16kb_alignment.sh
# Verifies a built APK/AAB satisfies Google Play's 16 KB page-size requirement.
#
# WHY THIS IS A SCRIPT AND NOT A BUTTON IN THE APP
# ------------------------------------------------
# The System Health screen used to have a "Verify 16 KB Page Size Alignment"
# button. It waited 1.2 seconds and then reported success unconditionally — it
# checked nothing. That was not a bug in the check; the idea was unsound:
# alignment is a property of the *built artifact*, decided at link time. A
# process already running on a device cannot meaningfully test it. So the check
# belongs in the release pipeline, which is here.
#
# BACKGROUND
# ----------
# From 1 November 2025, new apps and updates targeting Android 15 (API 35)+ must
# support 16 KB memory pages on 64-bit devices. From 1 February 2027 updates
# without support cannot be released at all.
#
# StopSnoozer is expected to PASS trivially, because it ships no native code of
# its own and its native-bearing dependencies bundle none either:
#
#   * play-services-location — a pure Java/Kotlin GMS client; talks to Play
#     Services on the device and contains no .so in its AAR.
#   * sqflite — uses the SQLite already present in Android and explicitly does
#     not bundle a SQLite library.
#
# Google's rule: code with no native libraries is compatible with no changes.
# This script exists to prove that claim per-build rather than assume it, since a
# future dependency could quietly introduce a native library.
#
# If a .so ever does appear and is misaligned, fix it by building with
# NDK r28+ (16 KB by default), or NDK r27 plus:
#     -Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384
#
# USAGE
#   tools/check_16kb_alignment.sh [path/to/app.apk]
# Defaults to the release APK, then the debug one.
#
# Exit codes: 0 pass, 1 misaligned, 2 could not run the check.
#
# On Windows run this from Git Bash, not from a WSL/Linux bash launched out of
# PowerShell: the latter has no Windows environment variables, so it cannot find
# the Android SDK and the script will (correctly) refuse to report a pass.
# Setting ANDROID_HOME explicitly works in any shell.
#
# Note the deliberate asymmetry: every failure path exits non-zero. A check that
# cannot run must never look like a check that passed — that was the whole
# problem with the UI button this replaces.

set -uo pipefail

APK="${1:-}"
if [[ -z "$APK" ]]; then
  for candidate in \
    build/app/outputs/flutter-apk/app-release.apk \
    build/app/outputs/flutter-apk/app-debug.apk
  do
    [[ -f "$candidate" ]] && APK="$candidate" && break
  done
fi

if [[ -z "$APK" || ! -f "$APK" ]]; then
  echo "ERROR: no APK found. Build one first, e.g.:" >&2
  echo "  flutter build apk --release" >&2
  exit 2
fi

echo "Checking 16 KB page-size compatibility"
echo "  artifact: $APK"

# --- locate tools ------------------------------------------------------------
# Search several roots: HOME differs when bash is launched from PowerShell, so
# relying on it alone makes the check silently unavailable in some shells.
# Windows env vars arrive with backslashes, which bash cannot use as paths, so
# normalise them. Without this the SDK is never found when bash is launched from
# PowerShell and the check reports "zipalign not found" on a machine that has it.
winpath() { printf '%s' "${1//\\//}"; }

SDK_CANDIDATES=(
  "$(winpath "${ANDROID_HOME:-}")"
  "$(winpath "${ANDROID_SDK_ROOT:-}")"
  "$(winpath "${LOCALAPPDATA:-}")/Android/sdk"
  "$(winpath "${USERPROFILE:-}")/AppData/Local/Android/sdk"
  "$HOME/AppData/Local/Android/sdk"
  "$HOME/Android/Sdk"
  "$HOME/Library/Android/sdk"
)

ZIPALIGN=""
if command -v zipalign >/dev/null 2>&1; then
  ZIPALIGN="$(command -v zipalign)"
else
  for SDK in "${SDK_CANDIDATES[@]}"; do
    [[ -z "$SDK" || ! -d "$SDK/build-tools" ]] && continue
    # Highest build-tools version wins.
    for d in $(ls -1 "$SDK/build-tools" 2>/dev/null | sort -Vr); do
      for exe in "$SDK/build-tools/$d/zipalign" "$SDK/build-tools/$d/zipalign.exe"; do
        [[ -f "$exe" ]] && ZIPALIGN="$exe" && break 3
      done
    done
  done
fi

# --- 1. enumerate native libraries ------------------------------------------
# List every entry and filter here rather than passing a pattern to unzip: the
# pattern argument silently matches nothing on some unzip builds, which made an
# earlier version of this script report "no native libraries" for an APK that
# actually contained ten. A check that cannot fail is worse than no check.
# unzip is not present everywhere (notably PowerShell environments and some CI
# images), so fall back to Python's zipfile, which ships with any Python 3.
list_entries() {
  if command -v unzip >/dev/null 2>&1; then
    unzip -Z1 "$1" 2>/dev/null && return 0
  fi
  for py in python3 python py; do
    if command -v "$py" >/dev/null 2>&1; then
      "$py" -c "import sys,zipfile
with zipfile.ZipFile(sys.argv[1]) as z:
    print('\n'.join(z.namelist()))" "$1" 2>/dev/null && return 0
    fi
  done
  return 1
}

ALL_ENTRIES="$(list_entries "$APK")"
if [[ -z "$ALL_ENTRIES" ]]; then
  echo "ERROR: could not read APK contents." >&2
  echo "       Need either 'unzip' or a Python 3 on PATH." >&2
  echo "       Refusing to report a pass without inspecting the archive." >&2
  exit 2
fi

SO_LIST="$(printf '%s\n' "$ALL_ENTRIES" | grep -i '\.so$' || true)"
SO_COUNT="$(printf '%s' "$SO_LIST" | grep -c . || true)"

if [[ "${SO_COUNT:-0}" -eq 0 ]]; then
  echo "  native libraries: none"
  echo
  echo "PASS: no native code is bundled, so the app is 16 KB-compatible."
else
  echo "  native libraries: $SO_COUNT"
  printf '%s\n' "$SO_LIST" | sed 's/^/    /'
  echo
  echo "  NOTE: these come from Flutter's own runtime and from plugins"
  echo "        (libflutter.so, libdartjni.so, libdatastore_shared_counter.so)."
  echo "        The app defines no native code of its own, but these still have"
  echo "        to be aligned — so the zipalign result below is what matters."
fi

# --- 2. authoritative alignment check ---------------------------------------
if [[ -z "$ZIPALIGN" ]]; then
  echo "ERROR: zipalign not found — cannot verify alignment." >&2
  echo "       Install Android build-tools 35.0.0+ or set ANDROID_HOME." >&2
  echo "       Refusing to report a pass without running the real check." >&2
  exit 2
fi

echo
echo "Running zipalign -c -P 16 ..."
if "$ZIPALIGN" -c -P 16 -v 4 "$APK" >/dev/null 2>&1; then
  echo "PASS: all entries are 16 KB aligned."
  exit 0
fi

echo "FAIL: artifact is NOT 16 KB aligned." >&2
echo >&2
echo "Rebuild the offending native library with NDK r28+, or NDK r27 plus:" >&2
echo "    -Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384" >&2
echo >&2
echo "Full output:" >&2
"$ZIPALIGN" -c -P 16 -v 4 "$APK" 2>&1 | tail -40 >&2
exit 1
