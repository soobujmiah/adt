#!/usr/bin/env bash
#
# Unit tests for setup.sh's install-profile support (profile_versions).
# A "profile" is a named bundle of already-verified component versions
# recorded in versions.json — this only tests that the lookup resolves
# correctly, not that installing one works (that needs a real device;
# see docs/REAL_DEVICE_BUILD_VALIDATION.md for the end-to-end evidence).
#
# Each case runs in its own `bash -c` subprocess with ADT_SOURCE_ONLY=1,
# same pattern as tests/test_arch_detection.sh, so setup.sh's
# `set -euo pipefail` and function definitions load without calling
# main().
#
# Run: ./tests/test_profile.sh
#
set -uo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_SH="$SCRIPT_DIR/../setup.sh"

pass=0
fail=0

resolve() {
    ADT_SOURCE_ONLY=1 bash -c 'cd "$(dirname "$1")" && source "$1"; profile_versions "$2"' _ "$SETUP_SH" "$1"
}

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo "ok - $desc"
        pass=$((pass + 1))
    else
        echo "NOT OK - $desc (expected '$expected', got '$actual')"
        fail=$((fail + 1))
    fi
}

# ── Cases ────────────────────────────────────────────────────────────────

assert_eq "'validated' profile resolves to the real-device-validated bundle" \
    "35.0.2|27.2.12479018|android-36" "$(resolve validated)"

assert_eq "unknown profile name resolves to nothing" \
    "" "$(resolve this-profile-does-not-exist)"

# The point of a profile is that it only ever names already-verified
# component versions — never something the profile installer would need
# to build or that isn't backed by real evidence elsewhere in the
# registry. Check that here so a future edit to versions.json can't
# silently point "validated" at an unverified or nonexistent version.
check_component_verified() {
    local component="$1" version="$2"
    ADT_SOURCE_ONLY=1 bash -c '
        cd "$(dirname "$1")" && source "$1"
        status="$(get_status "$2" "$3" 2>/dev/null || true)"
        # NDK entries use "status": "shim", not "verified" — a shim is the
        # correct/expected state for an NDK component, not a red flag.
        [[ "$status" == "verified" || "$status" == "shim" ]]
    ' _ "$SETUP_SH" "$component" "$version"
}

if check_component_verified "build-tools" "35.0.2"; then
    echo "ok - profile's build-tools component (35.0.2) is verified in versions.json"
    pass=$((pass + 1))
else
    echo "NOT OK - profile's build-tools component (35.0.2) is not verified in versions.json"
    fail=$((fail + 1))
fi

if check_component_verified "ndk" "27.2.12479018"; then
    echo "ok - profile's NDK component (27.2.12479018) is a recorded shim in versions.json"
    pass=$((pass + 1))
else
    echo "NOT OK - profile's NDK component (27.2.12479018) is not recorded in versions.json"
    fail=$((fail + 1))
fi

echo ""
echo "== ${pass} passed, ${fail} failed =="
[[ $fail -eq 0 ]]
