#!/usr/bin/env bash
#
# Unit tests for setup.sh's generic host-tool architecture detection
# (detect_binary_arch). This is what lets `./setup.sh doctor` catch an
# x86_64 binary in an ARM64 SDK/NDK install before it causes a confusing
# "No such file or directory" build failure — see the build-tools
# 36.0.0/aapt2 and NDK 28/llvm-strip cases in
# docs/ANDROID_ARM64_BUILD_HANDOFF.md.
#
# Each case runs in its own `bash -c` subprocess with ADT_SOURCE_ONLY=1,
# so setup.sh's `set -euo pipefail` and function definitions load without
# ever calling main() (which would run the interactive bootstrap), and a
# failure in one case can't taint the next.
#
# Run: ./tests/test_arch_detection.sh
#
set -uo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_SH="$SCRIPT_DIR/../setup.sh"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

pass=0
fail=0

detect() {
    ADT_SOURCE_ONLY=1 bash -c 'source "$1"; detect_binary_arch "$2"' _ "$SETUP_SH" "$1"
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

# ── Fixtures ─────────────────────────────────────────────────────────────

# A real native binary for whatever host runs this test. This repo only
# ever runs on aarch64 (ARM64 PRoot devices, and CI's ubuntu-24.04-arm
# runner), so bash itself is the "known-good native tool" fixture.
NATIVE_ELF="$(command -v bash)"

# Minimal ELF64 header — magic, class/data/version/osabi, e_type=ET_EXEC,
# e_machine, e_version. file(1) only needs e_ident + e_machine to name an
# architecture, so this is enough to exercise the x86_64/aarch64 branches
# without shipping a real foreign-arch binary in the repo.
make_fake_elf() {
    local out="$1" machine_le="$2"
    printf '\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00%b\x01\x00\x00\x00' \
        "$machine_le" > "$out"
    chmod +x "$out"
}

FAKE_X86_64="$WORKDIR/fake-x86_64-tool"
make_fake_elf "$FAKE_X86_64" '\x3e\x00'   # EM_X86_64 = 62

FAKE_ARM64="$WORKDIR/fake-arm64-tool"
make_fake_elf "$FAKE_ARM64" '\xb7\x00'    # EM_AARCH64 = 183

SCRIPT_SHIM="$WORKDIR/script-shim"
printf '#!/bin/sh\nexec /usr/bin/llvm-objcopy "$@"\n' > "$SCRIPT_SHIM"
chmod +x "$SCRIPT_SHIM"

SYMLINK_TO_SCRIPT="$WORKDIR/link-to-script"
ln -s "$SCRIPT_SHIM" "$SYMLINK_TO_SCRIPT"

SYMLINK_TO_X86="$WORKDIR/link-to-x86"
ln -s "$FAKE_X86_64" "$SYMLINK_TO_X86"

MISSING="$WORKDIR/does-not-exist"

BROKEN_SYMLINK="$WORKDIR/broken-link"
ln -s "$WORKDIR/target-that-does-not-exist" "$BROKEN_SYMLINK"

# ── Cases ────────────────────────────────────────────────────────────────
# The names below deliberately don't say "aapt2" or "llvm-strip" anywhere:
# detect_binary_arch is generic over the binary's identity, so these
# synthetic fixtures are exactly as valid evidence as the real tools.

assert_eq "native host ELF -> arm64" \
    "arm64" "$(detect "$NATIVE_ELF")"

assert_eq "synthetic x86_64 ELF -> x86_64 (the trap case)" \
    "x86_64" "$(detect "$FAKE_X86_64")"

assert_eq "synthetic aarch64 ELF -> arm64" \
    "arm64" "$(detect "$FAKE_ARM64")"

assert_eq "shell shim script -> script (delegates, assumed safe)" \
    "script" "$(detect "$SCRIPT_SHIM")"

assert_eq "symlink to a script resolves through to script" \
    "script" "$(detect "$SYMLINK_TO_SCRIPT")"

assert_eq "symlink to an x86_64 ELF resolves through to x86_64" \
    "x86_64" "$(detect "$SYMLINK_TO_X86")"

assert_eq "nonexistent path -> missing" \
    "missing" "$(detect "$MISSING")"

assert_eq "symlink with a missing target -> missing" \
    "missing" "$(detect "$BROKEN_SYMLINK")"

echo ""
echo "== ${pass} passed, ${fail} failed =="
[[ $fail -eq 0 ]]
