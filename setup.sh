#!/usr/bin/env bash
#
# setup.sh - Android SDK Manager for Linux ARM64
#
# Manages Android SDK tools on aarch64 Linux where Google provides no
# native binaries. Downloads pre-built releases or builds from AOSP source.
#
# Usage:
#   ./setup.sh bootstrap                     # Full automatic setup (fresh device)
#   ./setup.sh list-versions                 # Show all available versions
#   ./setup.sh install-build-tools 35.0.2    # Install build-tools
#   ./setup.sh install-platform-tools 35.0.2 # Install platform-tools
#   ./setup.sh install-ndk 28.2.13676358     # Create NDK shim
#   ./setup.sh install-cmake 3.22.1          # Create CMake shim
#   ./setup.sh install-cmd-tools             # Install sdkmanager
#   ./setup.sh install-platforms android-35   # Install Android platform
#   ./setup.sh install-profile validated     # Install the validated NDK27+BT35.0.2+API36 bundle
#   ./setup.sh build-all                     # Build + install everything
#   ./setup.sh build-build-tools 35.0.2      # Build from AOSP source
#   ./setup.sh build-platform-tools 35.0.2   # Build from AOSP source
#   ./setup.sh doctor                        # Diagnose setup
#   ./setup.sh setup-gradle                  # Configure Gradle aapt2 override
#
set -euo pipefail

# ── Constants ──────────────────────────────────────────────────────────────────

REPO_OWNER="soobujmiah"
REPO_NAME="adt"
REPO="${REPO_OWNER}/${REPO_NAME}"
REPO_URL="https://github.com/${REPO}"
RAW_URL="https://raw.githubusercontent.com/${REPO}/main"
CMDLINE_TOOLS_URL="https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"

# Build-tools binaries (native, need ARM64 builds)
BUILD_TOOLS_BINS=(aapt aapt2 aidl zipalign dexdump split-select)

# Platform-tools binaries (native, need ARM64 builds)
PLATFORM_TOOLS_BINS=(adb fastboot sqlite3 etc1tool hprof-conv mke2fs e2fsdroid make_f2fs make_f2fs_casefold sload_f2fs)

# NDK "host tools" that the Android Gradle Plugin invokes by a fixed path
# under toolchains/llvm/prebuilt/<host-tag>/bin/ regardless of $PATH — this
# is the entry point that tripped the NDK 28 x86_64 llvm-strip
# trap (see versions.json and docs/REAL_DEVICE_BUILD_VALIDATION.md). Add a name here if a
# future AGP/Gradle version is found to invoke another NDK host tool the
# same way; detect_binary_arch() itself is generic and needs no changes.
NDK_HOST_TOOL_BINS=(llvm-strip)

# Build dependencies by distro family
DEPS_FEDORA="gcc gcc-c++ cmake ninja-build git python3 golang bison flex zlib-devel openssl-devel libusb1-devel pcre2-devel expat-devel libpng-devel"
DEPS_DEBIAN="gcc g++ cmake ninja-build git python3 golang bison flex zlib1g-dev libssl-dev libusb-1.0-0-dev libpcre2-dev libexpat1-dev libpng-dev"

# ── Colors ─────────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

info()    { echo -e "  ${BLUE}[INFO]${NC} $*"; }
ok()      { echo -e "  ${GREEN}[DONE]${NC} $*"; }
warn()    { echo -e "  ${YELLOW}[WARN]${NC} $*"; }
err()     { echo -e "  ${RED}[FAIL]${NC} $*"; }
die()     { err "$@"; exit 1; }
ADT_UI_TICK=0
adt_draw_phase_progress() {
    local title="$1" rows cols width inner current total filled bar i color
    [[ "$title" =~ ^([0-9]+)/7[[:space:]]+(.*)$ ]] || return 1
    current="${BASH_REMATCH[1]}"; title="${BASH_REMATCH[2]}"; total=7
    rows="$(tput lines 2>/dev/null || printf 24)"; cols="$(tput cols 2>/dev/null || printf 80)"
    (( cols > 0 )) || cols=80
    width=$((cols - 2)); (( width > 78 )) && width=78; (( width < 12 )) && width=12
    inner=$((width - 4)); filled=$((inner * current / total)); (( filled > inner )) && filled=$inner
    ((ADT_UI_TICK+=1)); color="$CYAN"; ((ADT_UI_TICK % 4 == 1)) && color="$GREEN"; ((ADT_UI_TICK % 4 == 2)) && color="$BLUE"; ((ADT_UI_TICK % 4 == 3)) && color="$YELLOW"
    printf '\n  %s+%s+%s\n' "$CYAN" "$(printf '%*s' "$inner" '' | tr ' ' '-')" "$NC"
    printf '  %s|%s %sSTEPS %s/%s%s |%s\n' "$CYAN" "$NC" "$color" "$current" "$total" "$NC" "$CYAN" "$NC"
    printf '  %s|%s%s' "$CYAN" "$NC" "$color"
    for ((i=0; i<inner; i++)); do if (( i < filled )); then printf '#'; else printf '-'; fi; done
    printf '%s%s|%s\n' "$NC" "$CYAN" "$NC"
    title="${title:0:$inner}"
    printf '  %s|%s %b%-*s%s |%s\n' "$CYAN" "$NC" "$BOLD" "$((inner - 2))" "$title" "$NC" "$CYAN"
    printf '  %s+%s+%s\n' "$CYAN" "$(printf '%*s' "$inner" '' | tr ' ' '-')" "$NC"
    return 0
}
header()  {
    if [[ "${ADT_GUIDED_UI:-0}" == "1" ]] && adt_draw_phase_progress "$*"; then
        return 0
    fi
    echo ""
    echo -e "  ${BOLD}== $* ==${NC}"
    printf '  %s------------------------------------------------------------%s\n' "$DIM" "$NC"
}

adt_banner() {
    [[ -t 1 ]] || return 0
    printf '\n  %s+----------------------------------------------------------+%s\n' "$CYAN" "$NC"
    printf '  %s|%s  %sADT%s  %s|  Android Development Toolchain  | Linux ARM64  %s|%s\n' "$CYAN" "$NC" "$BOLD" "$NC" "$DIM" "$CYAN" "$NC"
    printf '  %s+----------------------------------------------------------+%s\n' "$CYAN" "$NC"
    printf '  %sby @soobujmiah  |  AOSP tools · native ARM64 · real-device workflow%s\n\n' "$DIM" "$NC"
}

adt_signature() {
    local status="${1:-0}" label="session complete"
    [[ "$status" -eq 0 ]] || label="session ended with status $status"
    printf '\n  %s%s%s  ·  %s© github.com/soobujmiah - 2026%s\n' "$DIM" "$label" "$NC" "$CYAN" "$NC" >&2
}

if [[ ! -t 1 || -n "${NO_COLOR:-}" || "${TERM:-}" == "dumb" ]]; then
    RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' DIM='' NC=''
fi

# ── Globals ────────────────────────────────────────────────────────────────────

SDK_ROOT=""
SCRIPT_DIR=""
INTERACTIVE=1   # 0 = unattended (bootstrap --auto)

# ── Helper functions ───────────────────────────────────────────────────────────

check_command() { command -v "$1" &>/dev/null; }
require_command() {
    if ! check_command "$1"; then
        die "Required command '$1' not found. Please install it."
    fi
}

# Interactive confirmation; always yes in --auto mode
confirm() {
    [[ "$INTERACTIVE" == "0" ]] && return 0
    local answer
    read -rp "  $1 [Y/n] " answer
    [[ "$answer" =~ ^[Nn]$ ]] && return 1
    return 0
}

check_arch() {
    local arch
    arch="$(uname -m)"
    if [[ "$arch" != "aarch64" && "$arch" != "arm64" ]]; then
        die "This tool only supports Linux ARM64 (aarch64), but you are on: $arch"
    fi
}

# ── Host-tool architecture trap detection ───────────────────────────────────
#
# Google's Android SDK/NDK distributions bundle host tools (aapt2, adb,
# llvm-strip, ...) built for whatever the packager targeted — usually
# linux-x86_64. Under this project's ARM64 host, an x86_64 binary is
# present, executable-bit set, and passes any plain `-x` check, yet fails
# at actual exec time with "No such file or directory" because the x86_64
# ELF interpreter (/lib64/ld-linux-x86-64.so.2) does not exist here. That
# silent gap between "looks installed" and "actually runs" is what caused
# the confusing build-tools 36.0.0/aapt2 and NDK 28/llvm-strip failures.
#
# detect_binary_arch is the single, generic primitive that closes that gap:
# it resolves symlinks (a shim is judged by what it points at, not its
# name) and classifies what would actually execute. It knows nothing about
# aapt2, adb, or llvm-strip by name, so it applies unchanged to any current
# or future SDK/NDK host tool — callers decide which paths to check.
#
# Prints exactly one of:
#   arm64        - native ELF for this host, safe to execute
#   x86_64       - x86_64 ELF, cannot execute under ARM64 PRoot (the trap)
#   script       - text shim (#!/...), delegates elsewhere, assumed safe
#   other:<desc> - some other file(1) description (unreadable, other ELF
#                  machine type, etc.) — informational, not a known-safe
#                  or known-broken case
#   missing      - path (or, for a symlink, its target) does not exist
detect_binary_arch() {
    local path="$1" resolved ftype

    [[ -e "$path" ]] || { echo "missing"; return; }

    resolved="$path"
    if [[ -L "$path" ]]; then
        resolved="$(readlink -f "$path" 2>/dev/null || true)"
        [[ -n "$resolved" && -e "$resolved" ]] || { echo "missing"; return; }
    fi

    [[ -r "$resolved" ]] || { echo "other:unreadable"; return; }

    # A text shim (`#!/bin/sh`, `#!/usr/bin/env python3`, ...) delegates to
    # whatever it execs and is not itself an architecture trap.
    if head -c 2 "$resolved" 2>/dev/null | grep -q '^#!'; then
        echo "script"
        return
    fi

    ftype="$(file -b "$resolved" 2>/dev/null || true)"
    if [[ -z "$ftype" ]] && command -v python3 &>/dev/null; then
        local py_arch
        py_arch="$(python3 -c '
import struct, sys
try:
    with open(sys.argv[1], "rb") as f:
        magic = f.read(4)
        if magic != b"\x7fELF":
            sys.exit(0)
        ei_data = f.read(2)[1]
        endian = "<" if ei_data == 1 else ">"
        f.seek(18)
        e_machine = struct.unpack(endian + "H", f.read(2))[0]
        if e_machine == 183:
            print("arm64")
        elif e_machine == 62:
            print("x86_64")
except Exception:
    pass
' "$resolved" 2>/dev/null || true)"
        if [[ -n "$py_arch" ]]; then
            echo "$py_arch"
            return
        fi
    fi

    case "$ftype" in
        *aarch64*|*"ARM aarch64"*) echo "arm64" ;;
        *"x86-64"*|*x86_64*)       echo "x86_64" ;;
        *)                          echo "other:${ftype}" ;;
    esac
}

# Resolve the directory where this script lives (for finding versions.json, etc.)
resolve_script_dir() {
    if [[ -n "$SCRIPT_DIR" ]]; then return; fi
    local source="${BASH_SOURCE[0]}"
    while [[ -L "$source" ]]; do
        SCRIPT_DIR="$(cd -P "$(dirname "$source")" && pwd)"
        source="$(readlink "$source")"
        [[ "$source" != /* ]] && source="$SCRIPT_DIR/$source"
    done
    SCRIPT_DIR="$(cd -P "$(dirname "$source")" && pwd)"
}

# Detect or ask for SDK root
detect_sdk_root() {
    if [[ -n "$SDK_ROOT" ]]; then
        info "SDK root: ${BOLD}${SDK_ROOT}${NC} (--sdk-root)"
        return
    fi

    if [[ -n "${ANDROID_HOME:-}" ]]; then
        SDK_ROOT="$ANDROID_HOME"
        info "SDK root: ${BOLD}${SDK_ROOT}${NC} (from \$ANDROID_HOME)"
    elif [[ -n "${ANDROID_SDK_ROOT:-}" ]]; then
        SDK_ROOT="$ANDROID_SDK_ROOT"
        info "SDK root: ${BOLD}${SDK_ROOT}${NC} (from \$ANDROID_SDK_ROOT)"
    elif [[ -d "$HOME/Android/Sdk" ]]; then
        SDK_ROOT="$HOME/Android/Sdk"
        info "SDK root: ${BOLD}${SDK_ROOT}${NC} (found ~/Android/Sdk)"
    elif [[ -d "$HOME/android-sdk" ]]; then
        SDK_ROOT="$HOME/android-sdk"
        info "SDK root: ${BOLD}${SDK_ROOT}${NC} (found ~/android-sdk)"
    else
        SDK_ROOT="$HOME/android-sdk"
        if [[ "$INTERACTIVE" == "0" ]]; then
            info "SDK root: ${BOLD}${SDK_ROOT}${NC} (default, auto mode)"
        else
            echo ""
            echo -e "  No Android SDK found. Default: ${BOLD}$SDK_ROOT${NC}"
            read -rp "  Use this path? [Y/n] or enter a custom path: " answer
            case "$answer" in
                ""|[Yy]*) ;;
                [Nn]*)   read -rp "  Enter SDK path: " SDK_ROOT ;;
                *)       SDK_ROOT="$answer" ;;
            esac
            SDK_ROOT="${SDK_ROOT/#\~/$HOME}"
            info "SDK root: ${BOLD}${SDK_ROOT}${NC} (new)"
        fi
    fi

    mkdir -p "$SDK_ROOT"
    SDK_ROOT="$(cd "$SDK_ROOT" && pwd)"
}

# ── versions.json handling ─────────────────────────────────────────────────────

# Read versions.json — either from the local repo or fetch from GitHub
get_versions_json() {
    resolve_script_dir

    local local_path="${SCRIPT_DIR}/versions.json"
    if [[ -f "$local_path" ]]; then
        cat "$local_path"
        return
    fi

    # Fetch from GitHub
    local tmpfile
    tmpfile="$(mktemp)"
    if curl -fsSL "${RAW_URL}/versions.json" -o "$tmpfile" 2>/dev/null; then
        cat "$tmpfile"
        rm -f "$tmpfile"
        return
    fi
    rm -f "$tmpfile"
    die "Could not find versions.json locally or fetch from GitHub."
}

# Query a field from versions.json
# Usage: versions_query '.["build-tools"]["35.0.2"]["status"]'
versions_query() {
    local json
    json="$(get_versions_json)"
    echo "$json" | python3 -c "
import sys, json
data = json.load(sys.stdin)
path = sys.argv[1]
# Simple path parser: .key1.key2.key3 or .[\"key1\"][\"key2\"]
import re
keys = re.findall(r'\[\"([^\"]+)\"\]|\.(\w+)', path)
obj = data
for k in keys:
    key = k[0] or k[1]
    if isinstance(obj, dict) and key in obj:
        obj = obj[key]
    else:
        sys.exit(1)
print(json.dumps(obj) if isinstance(obj, (dict, list)) else obj)
" "$1" 2>/dev/null
}

# Get AOSP tag for a component version
get_aosp_tag() {
    local component="$1" version="$2"
    versions_query ".[\"${component}\"][\"${version}\"][\"aosp_tag\"]"
}

# Get status for a component version
get_status() {
    local component="$1" version="$2"
    versions_query ".[\"${component}\"][\"${version}\"][\"status\"]"
}

# Get release tag for a component version
get_release_tag() {
    local component="$1" version="$2"
    versions_query ".[\"${component}\"][\"${version}\"][\"release\"]"
}

# ── Host dependency auto-install + environment ───────────────────────────────

# Map a required command to its package name (Debian / Fedora families)
pkg_for_deb() { case "$1" in java) echo "openjdk-21-jdk-headless";; ninja) echo "ninja-build";; llvm-strip) echo "llvm";; strip) echo "binutils";; *) echo "$1";; esac; }
pkg_for_dnf() { case "$1" in java) echo "java-21-openjdk-headless";; ninja) echo "ninja-build";; llvm-strip) echo "llvm";; strip) echo "binutils";; *) echo "$1";; esac; }

# Run a privileged command as root when possible; return 1 when we cannot escalate.
as_root() {
    if [[ "$(id -u)" -eq 0 ]]; then
        "$@"
    elif check_command sudo; then
        sudo "$@"
    else
        return 1
    fi
}

# Ensure host commands exist; auto-install from the distro package manager when missing.
ensure_commands() {
    local missing=()
    local c
    for c in "$@"; do check_command "$c" || missing+=("$c"); done
    [[ ${#missing[@]} -eq 0 ]] && return 0

    info "Missing host tools: ${missing[*]} — trying automatic install..."
    local pkgs=() mgr=""
    if [[ -f /etc/debian_version ]] || [[ -f /etc/ubuntu_version ]]; then
        mgr="deb"
        for c in "${missing[@]}"; do pkgs+=("$(pkg_for_deb "$c")"); done
    elif [[ -f /etc/fedora-release ]]; then
        mgr="dnf"
        for c in "${missing[@]}"; do pkgs+=("$(pkg_for_dnf "$c")"); done
    fi

    local ok_install=1
    if [[ "$mgr" == "deb" ]]; then
        as_root apt-get update -qq && as_root apt-get install -y "${pkgs[@]}" && ok_install=0
    elif [[ "$mgr" == "dnf" ]]; then
        as_root dnf install -y "${pkgs[@]}" && ok_install=0
    fi

    if [[ "$ok_install" -ne 0 ]]; then
        err "Automatic install needs root or sudo."
        echo ""
        if [[ "$mgr" == "dnf" ]]; then
            echo "  Run this as root, then re-run your last command:"
            echo ""
            echo "      dnf install -y ${pkgs[*]}"
        else
            echo "  Run this as root (e.g. 'proot-distro login <distro>' without --user), then re-run your last command:"
            echo ""
            echo "      apt-get update && apt-get install -y ${pkgs[*]}"
        fi
        echo ""
        die "Missing host tools and no privilege to install them."
    fi

    local still=()
    for c in "${missing[@]}"; do check_command "$c" || still+=("$c"); done
    [[ ${#still[@]} -gt 0 ]] && die "Still missing after install attempt: ${still[*]}"
    ok "Installed host tools: ${missing[*]}"
}

# Ensure the full AOSP build dependency set (commands + dev libraries).
# Auto-installs via the distro package manager when permitted; otherwise prints
# the exact root command and stops.
ensure_build_deps() {
    info "Checking build dependencies..."
    local missing=()
    local cmd
    for cmd in gcc g++ cmake ninja git python3 go bison flex; do
        check_command "$cmd" || missing+=("$cmd")
    done
    if [[ ${#missing[@]} -eq 0 ]]; then
        ok "Dependencies OK."
        return 0
    fi

    warn "Missing build tools: ${missing[*]} — installing the full build dependency set..."
    local installed=1
    if [[ -f /etc/fedora-release ]] || [[ -f /etc/redhat-release ]]; then
        as_root dnf install -y $DEPS_FEDORA && installed=0
    elif [[ -f /etc/debian_version ]]; then
        as_root apt-get update -qq && as_root apt-get install -y $DEPS_DEBIAN && installed=0
    fi

    if [[ "$installed" -ne 0 ]]; then
        err "Automatic install needs root or sudo."
        echo ""
        if [[ -f /etc/fedora-release ]] || [[ -f /etc/redhat-release ]]; then
            echo "      dnf install -y $DEPS_FEDORA"
        else
            echo "      apt-get update && apt-get install -y $DEPS_DEBIAN"
        fi
        echo ""
        die "Run the command above as root, then retry."
    fi

    local still=()
    for cmd in "${missing[@]}"; do check_command "$cmd" || still+=("$cmd"); done
    [[ ${#still[@]} -gt 0 ]] && die "Build dependencies still missing after install: ${still[*]}"
    ok "Build dependencies installed."
}

# Phase 0 check: what is this device/environment?
detect_environment() {
    header "Device & Environment Check"

    local arch
    arch="$(uname -m)"
    if [[ "$arch" == "aarch64" || "$arch" == "arm64" ]]; then
        ok "Architecture: ${arch}"
    else
        die "ADT supports aarch64 Linux only — this machine is: ${arch}"
    fi

    local kver
    kver="$(uname -r 2>/dev/null || echo unknown)"
    info "Kernel: ${kver}"
    if [[ "$kver" == *PRoot* || ( -n "${PREFIX:-}" && "${PREFIX}" == *com.termux* ) ]]; then
        info "Environment: Termux/PRoot-class on-device Linux"
    fi

    local distro="unknown"
    if [[ -r /etc/os-release ]]; then
        distro="$( . /etc/os-release 2>/dev/null; echo "${ID:-unknown} ${VERSION_ID:-} ${VERSION_CODENAME:-}" )"
    fi
    info "Distro: ${distro}"

    if [[ "$(id -u)" -eq 0 ]]; then
        ok "Privileges: root — host packages can auto-install"
    elif check_command sudo; then
        ok "Privileges: user + sudo — host packages auto-install via sudo"
    else
        warn "Privileges: non-root, no sudo — missing host tools will be reported as an exact root command"
    fi

    for c in git curl tar unzip python3 java cmake ninja llvm-strip; do
        if check_command "$c"; then
            echo -e "    ${GREEN}+${NC} $c"
        else
            echo -e "    ${YELLOW}-${NC} $c ${DIM}(missing — auto-installed in the next step when possible)${NC}"
        fi
    done

    local avail_mb
    avail_mb="$(df -Pm "${SDK_ROOT:-$HOME}" 2>/dev/null | awk 'NR==2 {print $4}')"
    if [[ -n "$avail_mb" ]]; then
        if [[ "$avail_mb" -lt 2048 ]]; then
            warn "Free space: ${avail_mb} MB — SDK + platform needs ~1 GB; AOSP source builds need much more"
        else
            ok "Free space: ${avail_mb} MB"
        fi
    fi
}

# Prefer a verified version that ships a checked-in artifact; else first verified.
get_bootstrap_version() {
    local component="$1"
    resolve_script_dir
    local json
    json="$(get_versions_json)"
    echo "$json" | python3 -c "
import json, os, sys
data = json.load(sys.stdin)
component, adir = sys.argv[1], sys.argv[2]
entries = data.get(component, {})
verified = [v for v, i in entries.items() if i.get('status') == 'verified']
for v in verified:
    if os.path.isfile(os.path.join(adir, component + '-' + v + '-linux-arm64.tar.gz')):
        print(v); sys.exit(0)
if verified:
    print(verified[0]); sys.exit(0)
sys.exit(1)
" "$component" "${SCRIPT_DIR}/artifacts"
}

# Prefer the NDK shim entry with device-tested metadata; else first shim.
get_bootstrap_ndk() {
    local json
    json="$(get_versions_json)"
    echo "$json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
entries = data.get('ndk', {})
for v, i in entries.items():
    if i.get('status') == 'shim' and i.get('tested_on'):
        print(v); sys.exit(0)
for v, i in entries.items():
    if i.get('status') == 'shim':
        print(v); sys.exit(0)
sys.exit(1)
"
}

# Persist ANDROID_HOME/PATH to ~/.bashrc (idempotent, marked block)
write_env_block() {
    require_command python3
    local profile="$HOME/.bashrc"
    local display_root="$SDK_ROOT"
    [[ "$SDK_ROOT" == "$HOME/"* ]] && display_root="\$HOME/${SDK_ROOT#"$HOME"/}"

    # Discover installed build-tools version so CLI utilities (aapt, aapt2, zipalign, aidl, etc.)
    # are directly available on $PATH out of the box for dev shells
    local bt_subpath=""
    if [[ -d "$SDK_ROOT/build-tools" ]]; then
        for d in $(ls -d "$SDK_ROOT/build-tools"/*/ 2>/dev/null | sort -V -r); do
            local ver
            ver="$(basename "$d")"
            if [[ -n "$ver" ]]; then
                bt_subpath=":\$ANDROID_HOME/build-tools/${ver}"
                break
            fi
        done
    fi

    touch "$profile"
    if grep -q ">>> ADT Android environment >>>" "$profile"; then
        python3 - "$profile" "$display_root" "$bt_subpath" <<'PY'
import re, sys
path, root, bt_subpath = sys.argv[1], sys.argv[2], sys.argv[3]
block = ('# >>> ADT Android environment >>>\n'
         'export ANDROID_HOME="%s"\n'
         'export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin%s:$PATH"\n'
         '# <<< ADT Android environment <<<' % (root, bt_subpath))
src = open(path).read()
new = re.sub(r'# >>> ADT Android environment >>>.*?# <<< ADT Android environment <<<',
             block, src, count=1, flags=re.S)
open(path, "w").write(new)
PY
        info "Updated Android environment block in ${profile}"
    else
        {
            echo ""
            echo "# >>> ADT Android environment >>>"
            echo "export ANDROID_HOME=\"${display_root}\""
            echo "export PATH=\"\$ANDROID_HOME/platform-tools:\$ANDROID_HOME/cmdline-tools/latest/bin${bt_subpath}:\$PATH\""
            echo "# <<< ADT Android environment <<<"
        } >> "$profile"
        info "Wrote Android environment block to ${profile}"
    fi
    echo -e "  ${DIM}Apply now with: source ~/.bashrc — new shells load it automatically${NC}"
}

print_post_install_guide() {
    header "Setup Complete — Quick Guide"
    cat <<EOF

  SDK root: ${SDK_ROOT}

  Now working:
    build-tools    aapt2 aapt aidl zipalign dexdump split-select
    platform-tools adb fastboot sqlite3 etc1tool hprof-conv (and F2FS/ext4 tools)
    NDK / CMake    shims delegating to system tools
    cmdline-tools  sdkmanager   (Java-based)

EOF
    if adt_step_selected env; then
        cat <<'EOF'
  Load the saved Android environment into THIS shell:
    source ~/.bashrc
EOF
    else
        cat <<'EOF'
  Shell environment was skipped. Configure it whenever you want:
    ./setup.sh setup-env
    source ~/.bashrc
EOF
    fi
    cat <<'EOF'

  Everyday use:
    adb devices -l                    # talk to a device
    ./setup.sh status                 # what is installed
    ./setup.sh doctor                 # re-verify any time

  Full per-tool command reference (adb connect, aapt2, sdkmanager, ...):
    COMMANDS.md  (in this repo)

  APK signing (JVM tool, runs on ARM64):
    apt install apksigner

  Extend / rebuild from AOSP source (heavy, needs more deps + space):
    ./setup.sh build-build-tools 35.0.2
    ./setup.sh list-versions          # what else exists

EOF
}

# ── list-versions ──────────────────────────────────────────────────────────────

cmd_list_versions() {
    local json
    json="$(get_versions_json)"

    header "Available Versions"

    echo "$json" | python3 -c "
import sys, json

data = json.load(sys.stdin)

GREEN  = '\033[0;32m'
YELLOW = '\033[1;33m'
CYAN   = '\033[0;36m'
DIM    = '\033[2m'
BOLD   = '\033[1m'
NC     = '\033[0m'

for component in ['build-tools', 'platform-tools', 'ndk', 'cmake', 'cmdline-tools']:
    if component not in data:
        continue
    print(f'\n  {BOLD}{component}{NC}')
    versions = data[component]
    for ver in sorted(versions.keys(), key=lambda v: [int(x) for x in v.split('.') if x.isdigit()], reverse=True):
        info = versions[ver]
        status = info.get('status', 'unknown')
        notes  = info.get('notes', '')
        release = info.get('release', '')

        if status == 'verified':
            badge = f'{GREEN}verified{NC}'
            extra = f' {DIM}(pre-built binary available){NC}' if release else ''
        elif status == 'shim':
            badge = f'{CYAN}shim{NC}'
            extra = f' {DIM}(delegates to system tools){NC}'
        else:
            badge = f'{YELLOW}unverified{NC}'
            extra = f' {DIM}(build from source){NC}'

        print(f'    {ver:>20s}  [{badge}]{extra}')
        if notes:
            print(f'                         {DIM}{notes}{NC}')
print()
"
}

# ── install-build-tools ────────────────────────────────────────────────────────

cmd_install_build_tools() {
    local version="${1:-}"
    if [[ -z "$version" ]]; then
        die "Usage: $0 install-build-tools <version>\n  Run '$0 list-versions' to see available versions."
    fi
    shift

    # Parse flags
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --sdk-root) SDK_ROOT="$2"; shift 2 ;;
            *) die "Unknown option: $1" ;;
        esac
    done

    check_arch
    detect_sdk_root

    local status
    status="$(get_status "build-tools" "$version" 2>/dev/null || echo "")"

    if [[ -z "$status" ]]; then
        die "Version $version not found in versions.json.\n  Run '$0 list-versions' to see available versions."
    fi

    local bt_dir="$SDK_ROOT/build-tools/${version}"

    header "Install build-tools ${version}"
    echo "  SDK root:    $SDK_ROOT"
    echo "  Destination: $bt_dir"
    echo "  Status:      $status"
    echo ""

    if [[ "$status" == "verified" ]]; then
        # Prefer the checked-in, validated artifact; fall back to release download, then source
        if ! install_local_artifact "build-tools" "$version" "$bt_dir"; then
            local release_tag
            release_tag="$(get_release_tag "build-tools" "$version" 2>/dev/null || echo "")"

            if [[ -n "$release_tag" ]]; then
                # Download pre-built binary
                download_and_install_release "$release_tag" "$bt_dir" "build-tools"
            else
                warn "No verified artifact or GitHub Release is available for ${version}."
                info "Building from source instead..."
                build_tools_from_source "build-tools" "$version"
            fi
        fi
    else
        warn "Version ${version} is unverified — no pre-built binary available."
        echo ""
        echo "  Options:"
        echo "    1. Build from source:  $0 build-build-tools ${version}"
        echo "    2. Use a verified version: $0 list-versions"
        echo ""
        die "Use 'build-build-tools' to build unverified versions from source."
    fi

    # source.properties
    create_source_properties "$bt_dir" "Android SDK Build-Tools ${version}" "$version"

    # Configure gradle aapt2 override
    configure_gradle "${bt_dir}/aapt2"

    ok "build-tools ${version} installed to ${bt_dir}"
}

# ── install-platform-tools ─────────────────────────────────────────────────────

cmd_install_platform_tools() {
    local version="${1:-}"
    if [[ -z "$version" ]]; then
        die "Usage: $0 install-platform-tools <version>\n  Run '$0 list-versions' to see available versions."
    fi
    shift

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --sdk-root) SDK_ROOT="$2"; shift 2 ;;
            *) die "Unknown option: $1" ;;
        esac
    done

    check_arch
    detect_sdk_root

    local status
    status="$(get_status "platform-tools" "$version" 2>/dev/null || echo "")"

    if [[ -z "$status" ]]; then
        die "Version $version not found in versions.json.\n  Run '$0 list-versions' to see available versions."
    fi

    local pt_dir="$SDK_ROOT/platform-tools"

    header "Install platform-tools ${version}"
    echo "  SDK root:    $SDK_ROOT"
    echo "  Destination: $pt_dir"
    echo "  Status:      $status"
    echo ""

    if [[ "$status" == "verified" ]]; then
        if ! install_local_artifact "platform-tools" "$version" "$pt_dir"; then
            local release_tag
            release_tag="$(get_release_tag "platform-tools" "$version" 2>/dev/null || echo "")"

            if [[ -n "$release_tag" ]]; then
                download_and_install_release "$release_tag" "$pt_dir" "platform-tools"
            else
                warn "No verified artifact or GitHub Release is available."
                info "Building from source instead..."
                build_tools_from_source "platform-tools" "$version"
            fi
        fi
    else
        warn "Version ${version} is unverified."
        echo ""
        echo "  Build from source:  $0 build-platform-tools ${version}"
        echo ""
        die "Use 'build-platform-tools' to build unverified versions."
    fi

    ok "platform-tools ${version} installed to ${pt_dir}"
}

# ── install-ndk ────────────────────────────────────────────────────────────────

cmd_install_ndk() {
    local version="${1:-}"

    if [[ -z "$version" ]]; then
        # Try auto-detect from current directory
        local detected
        if detected="$(detect_ndk_version .)"; then
            info "Detected ndkVersion from project: ${detected}"
            read -rp "  Create NDK shim for ${detected}? [Y/n] " confirm
            [[ "$confirm" =~ ^[Nn] ]] && exit 0
            version="$detected"
        else
            die "Usage: $0 install-ndk <version>\n  Example: $0 install-ndk 28.2.13676358\n  Run from a Flutter project dir to auto-detect."
        fi
    else
        shift
    fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --sdk-root) SDK_ROOT="$2"; shift 2 ;;
            *) die "Unknown option: $1" ;;
        esac
    done

    detect_sdk_root
    create_ndk_shim "$version"
    if ! create_cmake_shim "3.22.1"; then
        warn "CMake shim not created — install cmake, then: $0 install-cmake"
    fi
    ok "NDK ${version} shim ready."
}

# ── install-cmake ──────────────────────────────────────────────────────────────

cmd_install_cmake() {
    local version="${1:-3.22.1}"
    [[ $# -gt 0 ]] && shift

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --sdk-root) SDK_ROOT="$2"; shift 2 ;;
            *) die "Unknown option: $1" ;;
        esac
    done

    detect_sdk_root
    create_cmake_shim "$version" || die "CMake shim could not be created (needs system cmake)."
    ok "CMake ${version} shim ready."
}

# ── install-cmd-tools ──────────────────────────────────────────────────────────

cmd_install_cmd_tools() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --sdk-root) SDK_ROOT="$2"; shift 2 ;;
            *) die "Unknown option: $1" ;;
        esac
    done

    detect_sdk_root
    ensure_cmdline_tools
    accept_licenses
    ok "Command-line tools installed."
}

# ── install-platforms ──────────────────────────────────────────────────────────

cmd_install_platforms() {
    detect_sdk_root
    ensure_cmdline_tools

    if [[ $# -gt 0 ]]; then
        accept_licenses
        info "Installing: $*"
        # Prefix with "platforms;" if user passed bare version like "android-35"
        local packages=()
        for arg in "$@"; do
            case "$arg" in
                --sdk-root) SDK_ROOT="$2"; shift; continue ;;
                platforms\;*|build-tools\;*|sources\;*|system-images\;*|add-ons\;*)
                    packages+=("$arg") ;;
                android-*)
                    packages+=("platforms;${arg}") ;;
                *)
                    packages+=("$arg") ;;
            esac
        done
        run_sdkmanager "${packages[@]}"
    else
        header "Install Android Platforms"
        local -a common_platforms=(android-36 android-35 android-34 android-33)
        echo "  Select platform numbers separated by spaces (example: 1 2):"
        echo "    1) Android 16 — API 36"
        echo "    2) Android 15 — API 35"
        echo "    3) Android 14 — API 34"
        echo "    4) Android 13 — API 33"
        echo "    0) Cancel"
        read -rp "  Platforms to install: " input

        if [[ -n "$input" && "$input" != "0" ]]; then
            accept_licenses
            local packages=()
            local choice
            for choice in $input; do
                [[ "$choice" =~ ^[1-4]$ ]] || die "Choose platform numbers 1-4, or 0 to cancel."
                packages+=("platforms;${common_platforms[$((choice - 1))]}")
            done
            run_sdkmanager "${packages[@]}"
        fi
    fi
}

# ── install-profile ────────────────────────────────────────────────────────────
#
# A "profile" is just a named bundle of already-verified component versions
# recorded in versions.json (see the "profiles" key) — nothing here builds or
# verifies anything new. It exists so a fresh device can reproduce my
# validated configuration (docs/REAL_DEVICE_BUILD_VALIDATION.md) with one
# command instead of three, entirely by delegating to the existing
# install-build-tools / install-ndk / install-platforms commands.

# Look up profile "$1"'s component versions. Echoes
# "<build-tools>|<ndk>|<platforms>" and returns 0, or returns 1 (no output)
# if the profile isn't in versions.json.
profile_versions() {
    local name="$1" bt ndk platform
    bt="$(versions_query ".[\"profiles\"][\"${name}\"][\"components\"][\"build-tools\"]")"
    [[ -z "$bt" ]] && return 1
    ndk="$(versions_query ".[\"profiles\"][\"${name}\"][\"components\"][\"ndk\"]")"
    platform="$(versions_query ".[\"profiles\"][\"${name}\"][\"components\"][\"platforms\"]")"
    echo "${bt}|${ndk}|${platform}"
}

cmd_install_profile() {
    local name="${1:-validated}"
    detect_sdk_root

    local resolved
    resolved="$(profile_versions "$name")" \
        || die "Unknown profile: ${name}\n  Profiles are listed in versions.json under \"profiles\". Currently available: validated"

    local bt_version="${resolved%%|*}"
    local rest="${resolved#*|}"
    local ndk_version="${rest%%|*}"
    local platform="${rest#*|}"

    header "ADT profile: ${name}"
    echo "  build-tools: ${bt_version}"
    echo "  NDK:         ${ndk_version}"
    echo "  Platform:    platforms;${platform}"
    echo ""
    info "Installing the exact configuration I validated end-to-end on a real ARM64 Android device (docs/REAL_DEVICE_BUILD_VALIDATION.md)."
    echo ""

    cmd_install_build_tools "$bt_version"
    cmd_install_ndk "$ndk_version"
    cmd_install_platforms "$platform"

    echo ""
    ok "Profile '${name}' installed: build-tools ${bt_version}, NDK ${ndk_version}, platforms;${platform}"
    echo -e "  ${DIM}Verify with: $0 doctor${NC}"
}

# ── build-build-tools ──────────────────────────────────────────────────────────

cmd_build_build_tools() {
    local version="${1:-}"
    if [[ -z "$version" ]]; then
        die "Usage: $0 build-build-tools <version>"
    fi
    shift

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --sdk-root) SDK_ROOT="$2"; shift 2 ;;
            *) die "Unknown option: $1" ;;
        esac
    done

    check_arch
    detect_sdk_root
    build_tools_from_source "build-tools" "$version"

    local bt_dir="$SDK_ROOT/build-tools/${version}"
    create_source_properties "$bt_dir" "Android SDK Build-Tools ${version}" "$version"
    configure_gradle "${bt_dir}/aapt2"
    ok "build-tools ${version} built and installed."
}

# ── build-platform-tools ──────────────────────────────────────────────────────

cmd_build_platform_tools() {
    local version="${1:-}"
    if [[ -z "$version" ]]; then
        die "Usage: $0 build-platform-tools <version>"
    fi
    shift

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --sdk-root) SDK_ROOT="$2"; shift 2 ;;
            *) die "Unknown option: $1" ;;
        esac
    done

    check_arch
    detect_sdk_root
    build_tools_from_source "platform-tools" "$version"
    ok "platform-tools ${version} built and installed."
}

# ── build-all ──────────────────────────────────────────────────────────────────

# Get the first verified (or shim) version for a component from versions.json
get_default_version() {
    local component="$1"
    local json
    json="$(get_versions_json)"
    echo "$json" | python3 -c "
import sys, json
data = json.load(sys.stdin)
component = sys.argv[1]
entries = data.get(component, {})
for ver, info in entries.items():
    if info.get('status') in ('verified', 'shim'):
        print(ver)
        sys.exit(0)
sys.exit(1)
" "$component" 2>/dev/null
}

cmd_build_all() {
    local bt_version="" pt_version="" ndk_version="" cmake_version="3.22.1"
    local skip_ndk=false skip_cmake=false skip_cmd_tools=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --sdk-root)       SDK_ROOT="$2"; shift 2 ;;
            --build-tools)    bt_version="$2"; shift 2 ;;
            --platform-tools) pt_version="$2"; shift 2 ;;
            --ndk)            ndk_version="$2"; shift 2 ;;
            --cmake)          cmake_version="$2"; shift 2 ;;
            --skip-ndk)       skip_ndk=true; shift ;;
            --skip-cmake)     skip_cmake=true; shift ;;
            --skip-cmd-tools) skip_cmd_tools=true; shift ;;
            *) die "Unknown option: $1" ;;
        esac
    done

    check_arch
    detect_sdk_root

    # Resolve default versions from versions.json
    if [[ -z "$bt_version" ]]; then
        bt_version="$(get_default_version "build-tools" 2>/dev/null || echo "")"
        [[ -z "$bt_version" ]] && die "No verified build-tools version found in versions.json"
    fi
    if [[ -z "$pt_version" ]]; then
        pt_version="$(get_default_version "platform-tools" 2>/dev/null || echo "")"
        [[ -z "$pt_version" ]] && die "No verified platform-tools version found in versions.json"
    fi
    if [[ -z "$ndk_version" ]] && [[ "$skip_ndk" == false ]]; then
        ndk_version="$(get_default_version "ndk" 2>/dev/null || echo "")"
        [[ -z "$ndk_version" ]] && skip_ndk=true
    fi

    header "Build All"
    echo ""
    echo "  SDK root:        ${SDK_ROOT}"
    echo "  build-tools:     ${bt_version}"
    echo "  platform-tools:  ${pt_version}"
    if [[ "$skip_ndk" == false ]]; then
        echo "  NDK shim:        ${ndk_version}"
    fi
    if [[ "$skip_cmake" == false ]]; then
        echo "  CMake shim:      ${cmake_version}"
    fi
    if [[ "$skip_cmd_tools" == false ]]; then
        echo "  cmd-tools:       latest"
    fi
    echo ""

    # 1. Build build-tools
    header "1/5  build-tools ${bt_version}"
    build_tools_from_source "build-tools" "$bt_version"
    local bt_dir="$SDK_ROOT/build-tools/${bt_version}"
    create_source_properties "$bt_dir" "Android SDK Build-Tools ${bt_version}" "$bt_version"
    ok "build-tools ${bt_version} installed."

    # 2. Build platform-tools
    header "2/5  platform-tools ${pt_version}"
    build_tools_from_source "platform-tools" "$pt_version"
    ok "platform-tools ${pt_version} installed."

    # 3. NDK shim
    if [[ "$skip_ndk" == false ]]; then
        header "3/5  NDK shim ${ndk_version}"
        create_ndk_shim "$ndk_version"
        ok "NDK ${ndk_version} shim ready."
    else
        info "3/5  NDK shim: skipped"
    fi

    # 4. CMake shim
    if [[ "$skip_cmake" == false ]]; then
        header "4/5  CMake shim ${cmake_version}"
        if create_cmake_shim "$cmake_version"; then
            ok "CMake ${cmake_version} shim ready."
        else
            warn "CMake shim skipped (no system cmake)."
        fi
    else
        info "4/5  CMake shim: skipped"
    fi

    # 5. Command-line tools
    if [[ "$skip_cmd_tools" == false ]]; then
        header "5/5  Command-line tools"
        if check_command java; then
            ensure_cmdline_tools
            accept_licenses
            ok "Command-line tools installed."
        else
            warn "Java not found — skipping cmd-tools (install JDK 17+ to enable)."
        fi
    else
        info "5/5  Command-line tools: skipped"
    fi

    # Configure gradle
    if [[ -f "$SDK_ROOT/build-tools/${bt_version}/aapt2" ]]; then
        configure_gradle "$SDK_ROOT/build-tools/${bt_version}/aapt2"
    fi

    echo ""
    header "Done"
    ok "All components installed to: ${SDK_ROOT}"
    echo ""
    echo "  Next steps:"
    echo "    export ANDROID_HOME=\"${SDK_ROOT}\""
    echo "    export PATH=\"\$ANDROID_HOME/platform-tools:\$ANDROID_HOME/cmdline-tools/latest/bin:\$ANDROID_HOME/build-tools/${bt_version}:\$PATH\""
    echo ""
    echo "    ./setup.sh doctor        # verify everything"
    echo "    ./setup.sh status        # see what's installed"
    echo ""
}

# ── setup-gradle ───────────────────────────────────────────────────────────────

cmd_setup_gradle() {
    local force=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force) force="--force"; shift ;;
            --sdk-root) SDK_ROOT="$2"; shift 2 ;;
            *) die "Unknown option: $1" ;;
        esac
    done
    detect_sdk_root

    # Find latest build-tools with ARM64 aapt2
    local bt_dir="$SDK_ROOT/build-tools"
    local latest=""
    if [[ -d "$bt_dir" ]]; then
        for d in $(ls -d "$bt_dir"/*/ 2>/dev/null | sort -V -r); do
            if [[ -x "${d}aapt2" && "$(detect_binary_arch "${d}aapt2")" == "arm64" ]]; then
                latest="${d}aapt2"
                break
            fi
        done
    fi

    if [[ -z "$latest" ]]; then
        die "No ARM64 build-tools with aapt2 found in ${bt_dir}.\n  Install build-tools first: $0 install-build-tools <version>"
    fi

    configure_gradle "$latest" "$force"
    if [[ "${ADT_GRADLE_OVERRIDE_KEPT:-0}" == "1" ]]; then
        info "Gradle override left as-is (see the warning above)."
        info "  Force it with: $0 setup-gradle --force"
    else
        ok "Gradle configured with aapt2 at: ${latest}"
    fi
}

# ── doctor ─────────────────────────────────────────────────────────────────────

# Read-only commands (doctor/status/cleanup) accept the same "--sdk-root <path>"
# flag as the install commands. Without this they silently fell back to
# detect_sdk_root's default, so `doctor --sdk-root /opt/android-sdk` reported on
# an empty ~/android-sdk instead — exactly the kind of answer that sends an agent
# down the wrong path. Extra arguments are ignored: these commands have no others.
take_sdk_root_arg() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --sdk-root)
                [[ -n "${2:-}" ]] || die "--sdk-root requires a path"
                SDK_ROOT="$2"
                shift 2
                ;;
            *) shift ;;
        esac
    done
}

cmd_doctor() {
    take_sdk_root_arg "$@"
    detect_sdk_root

    header "Android SDK ARM64 - Diagnostic Check"
    echo "  SDK root: $SDK_ROOT"
    echo ""

    local issues=0

    # Architecture
    local arch
    arch="$(uname -m)"
    if [[ "$arch" == "aarch64" || "$arch" == "arm64" ]]; then
        ok "Architecture: ${arch}"
    else
        err "Architecture: ${arch} — this project only supports aarch64"
        issues=$((issues+1))
    fi

    # ANDROID_HOME
    if [[ -n "${ANDROID_HOME:-}" ]]; then
        ok "ANDROID_HOME: ${ANDROID_HOME}"
    else
        warn "ANDROID_HOME not set"
        issues=$((issues+1))
    fi

    # Build-tools — check each version independently
    local bt_dir="$SDK_ROOT/build-tools"
    if [[ -d "$bt_dir" ]]; then
        local bt_count=0
        for d in $(ls -d "$bt_dir"/*/ 2>/dev/null | sort -V); do
            local ver
            ver="$(basename "$d")"
            bt_count=$((bt_count+1))

            # Determine arch from aapt2 (or first available binary)
            local arch_label="unknown"
            local probe_bin=""
            for bin in aapt2 aapt aidl zipalign dexdump; do
                if [[ -x "${d}${bin}" ]]; then
                    probe_bin="${d}${bin}"
                    break
                fi
            done
            if [[ -n "$probe_bin" ]]; then
                case "$(detect_binary_arch "$probe_bin")" in
                    arm64)  arch_label="arm64" ;;
                    x86_64) arch_label="x86_64" ;;
                esac
            fi

            if [[ "$arch_label" == "arm64" ]]; then
                ok "build-tools ${ver}: native ARM64"
                for bin in aapt2 aapt aidl zipalign dexdump; do
                    if [[ -x "${d}${bin}" ]]; then
                        ok "  ${bin}: OK"
                    else
                        warn "  ${bin}: missing"
                        issues=$((issues+1))
                    fi
                done
            elif [[ "$arch_label" == "x86_64" ]]; then
                err "build-tools ${ver}: x86_64 (won't run on ARM64!)"
                echo -e "    ${DIM}Replace with: $0 install-build-tools ${ver}${NC}"
                issues=$((issues+1))
            else
                warn "build-tools ${ver}: no binaries found"
                issues=$((issues+1))
            fi
        done
        if [[ $bt_count -eq 0 ]]; then
            warn "No build-tools installed"
            issues=$((issues+1))
        fi
    else
        warn "No build-tools installed"
        issues=$((issues+1))
    fi

    # Platform-tools
    local pt_dir="$SDK_ROOT/platform-tools"
    if [[ -d "$pt_dir" ]]; then
        for bin in adb fastboot; do
            local path="$pt_dir/$bin"
            if [[ -x "$path" ]]; then
                case "$(detect_binary_arch "$path")" in
                    arm64)
                        ok "  $bin: native ARM64"
                        ;;
                    x86_64)
                        err "  $bin: x86_64 (won't run!)"
                        echo -e "    ${DIM}Fix:  $0 install-platform-tools <version>${NC}"
                        issues=$((issues+1))
                        ;;
                    *)
                        ok "  $bin: present"
                        ;;
                esac
            else
                warn "  $bin: missing"
                issues=$((issues+1))
            fi
        done
    else
        warn "platform-tools not found"
        issues=$((issues+1))
    fi

    # Platforms
    local platforms_dir="$SDK_ROOT/platforms"
    if [[ -d "$platforms_dir" ]]; then
        local platforms
        platforms=$(ls -d "$platforms_dir"/*/ 2>/dev/null | xargs -I{} basename {} | sort -V | tr '\n' ' ')
        if [[ -n "$platforms" ]]; then
            ok "Platforms: ${platforms}"
        else
            warn "No platforms installed"
            issues=$((issues+1))
        fi
    else
        warn "No platforms installed"
        issues=$((issues+1))
    fi

    # NDK host-tool architecture check.
    #
    # Existence (`-x`) is not enough here: NDK 28's bundled llvm-strip is
    # executable and present, but it is a real x86_64 ELF that fails at
    # exec time under this ARM64 PRoot. Each name in NDK_HOST_TOOL_BINS is
    # checked with detect_binary_arch so this catches that class of
    # failure — a "present but wrong architecture" host tool — instead of
    # only noticing it is missing.
    local ndk_dir="$SDK_ROOT/ndk"
    if [[ -d "$ndk_dir" ]]; then
        local ndk_versions
        ndk_versions=$(ls -d "$ndk_dir"/*/ 2>/dev/null | xargs -I{} basename {} | tr '\n' ' ')
        if [[ -n "$ndk_versions" ]]; then
            ok "NDK shims: ${ndk_versions}"
            for ver in $ndk_versions; do
                local host_bin_dir
                host_bin_dir=$(ls -d "$ndk_dir/$ver"/toolchains/llvm/prebuilt/*/bin 2>/dev/null | head -1)
                if [[ -z "$host_bin_dir" ]]; then
                    warn "  NDK ${ver}: no LLVM prebuilt host-tool directory found"
                    issues=$((issues+1))
                    continue
                fi
                local tool
                for tool in "${NDK_HOST_TOOL_BINS[@]}"; do
                    local tool_path="$host_bin_dir/$tool" tool_arch
                    tool_arch="$(detect_binary_arch "$tool_path")"
                    case "$tool_arch" in
                        arm64|script)
                            ok "  NDK ${ver}: ${tool} OK (${tool_arch})"
                            ;;
                        x86_64)
                            err "  NDK ${ver}: ${tool} is x86_64 — cannot execute under ARM64 PRoot"
                            echo -e "    ${DIM}Gradle/AGP call this exact path directly, bypassing \$PATH.${NC}"
                            echo -e "    ${DIM}Path: ${tool_path}${NC}"
                            echo -e "    ${DIM}Fix:  $0 install-ndk ${ver}   (recreates the ARM64-compatible shim)${NC}"
                            issues=$((issues+1))
                            ;;
                        missing)
                            warn "  NDK ${ver}: ${tool} missing"
                            issues=$((issues+1))
                            ;;
                        *)
                            warn "  NDK ${ver}: ${tool} unexpected type (${tool_arch})"
                            issues=$((issues+1))
                            ;;
                    esac
                done
            done
        fi
    else
        warn "No NDK shims installed"
        issues=$((issues+1))
    fi

    # CMake shim
    local cmake_shim="$SDK_ROOT/cmake/3.22.1/bin/cmake"
    if [[ -x "$cmake_shim" ]]; then
        case "$(detect_binary_arch "$cmake_shim")" in
            script|arm64)
                ok "CMake shim: OK"
                ;;
            x86_64)
                err "CMake 3.22.1: x86_64 binary (needs shim!)"
                echo -e "    ${DIM}Fix:  $0 install-cmake${NC}"
                issues=$((issues+1))
                ;;
            *)
                ok "CMake: present"
                ;;
        esac
    else
        info "CMake shim: not installed (only needed if project uses NDK)"
    fi

    # Gradle config
    local gradle_props="$HOME/.gradle/gradle.properties"
    if [[ -f "$gradle_props" ]] && grep -q "^android.aapt2FromMavenOverride=" "$gradle_props"; then
        local aapt2_path
        aapt2_path=$(grep "^android.aapt2FromMavenOverride=" "$gradle_props" | cut -d= -f2)
        if [[ ! -e "$aapt2_path" ]]; then
            warn "Gradle aapt2 override points to missing file: $aapt2_path"
            issues=$((issues+1))
        elif [[ "$aapt2_path" == "$SDK_ROOT/"* ]]; then
            ok "Gradle aapt2 override: $aapt2_path (SDK build-tools)"
        elif [[ "$(detect_binary_arch "$aapt2_path")" == "x86_64" ]]; then
            err "Gradle aapt2 override is x86_64: $aapt2_path"
            echo -e "    ${DIM}Fix:  $0 setup-gradle --force   (point AGP at an ARM64 aapt2)${NC}"
            issues=$((issues+1))
        else
            ok "Gradle aapt2 override: $aapt2_path (custom shim, $(detect_binary_arch "$aapt2_path"))"
        fi
    else
        warn "Gradle aapt2 override not configured"
        issues=$((issues+1))
    fi

    # Java
    if check_command java; then
        local java_ver
        java_ver=$(java -version 2>&1 | head -1)
        ok "Java: $java_ver"
    else
        warn "Java not found"
        issues=$((issues+1))
    fi

    # Flutter
    if check_command flutter; then
        local flutter_ver
        flutter_ver=$(flutter --version 2>&1 | head -1)
        ok "Flutter: $flutter_ver"
    else
        info "Flutter: not found (optional)"
    fi

    # ARM64 overwrite hazard: sdkmanager only knows Google's linux-x86_64
    # payloads, so "updating" build-tools or platform-tools with it silently
    # replaces working ARM64 binaries with ones that cannot exec here.
    echo ""
    info "Reminder: do not update build-tools/platform-tools with sdkmanager on ARM64 —"
    info "          it installs x86_64 binaries. Re-run install-build-tools / install-platform-tools instead."

    # Summary
    echo ""
    if [[ $issues -eq 0 ]]; then
        echo -e "  ${GREEN}${BOLD}All checks passed.${NC}"
    else
        echo -e "  ${YELLOW}${BOLD}Found $issues issue(s).${NC} See above."
    fi
    echo ""
}

# ── status ─────────────────────────────────────────────────────────────────────

cmd_status() {
    take_sdk_root_arg "$@"
    detect_sdk_root

    header "Android SDK ARM64 - Status"
    echo "  SDK root: $SDK_ROOT"

    # Build-tools
    local bt_dir="$SDK_ROOT/build-tools"
    if [[ -d "$bt_dir" ]]; then
        for d in $(ls -d "$bt_dir"/*/ 2>/dev/null | sort -V); do
            local ver
            ver=$(basename "$d")
            # Check if our ARM64 binaries or x86_64
            local aapt2="$d/aapt2"
            local arch_label="?"
            if [[ -x "$aapt2" ]]; then
                case "$(detect_binary_arch "$aapt2")" in
                    arm64)  arch_label="arm64" ;;
                    x86_64) arch_label="x86_64" ;;
                esac
            fi
            echo -e "    ${GREEN}+${NC} build-tools;${ver}  ${DIM}(${arch_label})${NC}"
        done
    fi

    # Platform-tools
    local pt_dir="$SDK_ROOT/platform-tools"
    if [[ -d "$pt_dir" ]] && [[ -x "$pt_dir/adb" ]]; then
        local arch_label="?"
        case "$(detect_binary_arch "$pt_dir/adb")" in
            arm64)  arch_label="arm64" ;;
            x86_64) arch_label="x86_64" ;;
        esac
        echo -e "    ${GREEN}+${NC} platform-tools  ${DIM}(${arch_label})${NC}"
    fi

    # NDK shims
    local ndk_dir="$SDK_ROOT/ndk"
    if [[ -d "$ndk_dir" ]]; then
        for d in "$ndk_dir"/*/; do
            [[ -d "$d" ]] || continue
            echo -e "    ${GREEN}+${NC} ndk;$(basename "$d")  ${DIM}(shim)${NC}"
        done
    fi

    # CMake shim
    if [[ -d "$SDK_ROOT/cmake" ]]; then
        for d in "$SDK_ROOT/cmake"/*/; do
            [[ -d "$d" ]] || continue
            echo -e "    ${GREEN}+${NC} cmake;$(basename "$d")  ${DIM}(shim)${NC}"
        done
    fi

    # Cmdline-tools
    if [[ -x "$SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" ]]; then
        echo -e "    ${GREEN}+${NC} cmdline-tools;latest"
    fi

    # Platforms
    local platforms_dir="$SDK_ROOT/platforms"
    if [[ -d "$platforms_dir" ]]; then
        for d in "$platforms_dir"/*/; do
            [[ -d "$d" ]] || continue
            echo -e "    ${GREEN}+${NC} platforms;$(basename "$d")"
        done
    fi

    echo ""
}

# ── Shared internals ──────────────────────────────────────────────────────────

find_strip() {
    if check_command llvm-strip; then command -v llvm-strip
    elif check_command strip; then command -v strip
    else echo ""; fi
}

find_cmake_bin() {
    if check_command cmake; then command -v cmake
    else echo ""; fi
}

find_ninja_bin() {
    if check_command ninja; then command -v ninja
    elif check_command ninja-build; then command -v ninja-build
    else echo ""; fi
}

create_source_properties() {
    local dir="$1" desc="$2" revision="$3"
    cat > "${dir}/source.properties" << PROPS
Pkg.Desc = ${desc}
Pkg.Revision = ${revision}
PROPS
}

configure_gradle() {
    local aapt2_path="$1"
    local force="${2:-}"
    local gradle_props="$HOME/.gradle/gradle.properties"
    local backup="" existing=""

    # Callers report the outcome; see cmd_setup_gradle.
    ADT_GRADLE_OVERRIDE_KEPT=0

    info "Configuring Gradle aapt2 override..."
    echo "  aapt2:  ${aapt2_path}"
    echo "  config: ${gradle_props}"
    mkdir -p "$(dirname "$gradle_props")"

    if [[ -f "$gradle_props" ]]; then
        backup="${gradle_props}.bak-$(date +%Y%m%d-%H%M%S)"
        cp "$gradle_props" "$backup"

        # A pre-existing override that does not live inside this SDK is somebody's
        # deliberate shim (e.g. an aapt2 wrapper that rewrites arguments for this
        # AGP/aapt2 combination). Replacing it silently breaks their builds in
        # ways that look unrelated, so keep it unless the caller forces the change.
        existing="$(sed -n 's/^android\.aapt2FromMavenOverride=//p' "$gradle_props" | tail -n 1)"
        if [[ -n "$existing" && "$existing" != "$SDK_ROOT/"* && "$force" != "--force" ]]; then
            ADT_GRADLE_OVERRIDE_KEPT=1
            warn "Kept the existing aapt2 override: ${existing}"
            echo -e "    ${DIM}It is outside ${SDK_ROOT}, so it was not replaced by ${aapt2_path}.${NC}"
            echo -e "    ${DIM}Backup: ${backup}   Force a rewrite: $0 setup-gradle --force${NC}"
            return 0
        fi

        sed -i '/^android\.aapt2FromMavenOverride=/d' "$gradle_props"
    fi

    echo "android.aapt2FromMavenOverride=${aapt2_path}" >> "$gradle_props"
    ok "Gradle: ${gradle_props}"
    if [[ -n "$backup" ]]; then
        info "  previous file backed up to: ${backup}"
    fi
    return 0
}

create_ndk_shim() {
    local ndk_version="$1"
    local ndk_dir="$SDK_ROOT/ndk/${ndk_version}"

    info "Creating NDK ${ndk_version} shim..."
    echo "  NDK dir:   ${ndk_dir}"

    local strip_bin
    strip_bin="$(find_strip)"
    if [[ -z "$strip_bin" ]]; then
        ensure_commands llvm-strip
        strip_bin="$(find_strip)"
    fi
    [[ -z "$strip_bin" ]] && die "No strip or llvm-strip found. Install binutils or llvm."

    # llvm-strip shim
    local llvm_strip_dir="${ndk_dir}/toolchains/llvm/prebuilt/linux-x86_64/bin"
    mkdir -p "$llvm_strip_dir"
    cat > "${llvm_strip_dir}/llvm-strip" << SHIM
#!/bin/sh
exec ${strip_bin} "\$@"
SHIM
    chmod +x "${llvm_strip_dir}/llvm-strip"

    # source.properties
    cat > "${ndk_dir}/source.properties" << PROPS
Pkg.Desc = Android NDK
Pkg.Revision = ${ndk_version}
PROPS

    # CMake toolchain shim
    local toolchain_dir="${ndk_dir}/build/cmake"
    mkdir -p "$toolchain_dir"

    local gcc_path
    gcc_path="$(command -v gcc 2>/dev/null || echo /usr/bin/gcc)"
    local gpp_path
    gpp_path="$(command -v g++ 2>/dev/null || echo /usr/bin/g++)"

    cat > "${toolchain_dir}/android.toolchain.cmake" << CMAKE
# NDK toolchain shim — auto-generated by setup.sh
set(CMAKE_C_COMPILER ${gcc_path})
set(CMAKE_CXX_COMPILER ${gpp_path})
CMAKE

    ok "NDK ${ndk_version} shim: llvm-strip -> ${strip_bin}"
}

create_cmake_shim() {
    local cmake_version="$1"
    local cmake_dir="$SDK_ROOT/cmake/${cmake_version}/bin"

    local sys_cmake
    sys_cmake="$(find_cmake_bin)"
    local sys_ninja
    sys_ninja="$(find_ninja_bin)"

    if [[ -z "$sys_cmake" ]]; then
        ensure_commands cmake ninja
        sys_cmake="$(find_cmake_bin)"
        sys_ninja="$(find_ninja_bin)"
    fi
    [[ -z "$sys_cmake" ]] && { warn "System cmake not found, skipping cmake shim."; return 1; }

    info "Creating CMake ${cmake_version} shim..."
    echo "  CMake dir: ${cmake_dir}"
    mkdir -p "$cmake_dir"

    # If there's an existing x86_64 binary, back it up
    if [[ -f "${cmake_dir}/cmake" ]] && ! head -1 "${cmake_dir}/cmake" 2>/dev/null | grep -q "^#!/bin/sh"; then
        mv "${cmake_dir}/cmake" "${cmake_dir}/cmake.x86_64.bak" 2>/dev/null || true
    fi
    if [[ -f "${cmake_dir}/ninja" ]] && ! head -1 "${cmake_dir}/ninja" 2>/dev/null | grep -q "^#!/bin/sh"; then
        mv "${cmake_dir}/ninja" "${cmake_dir}/ninja.x86_64.bak" 2>/dev/null || true
    fi

    cat > "${cmake_dir}/cmake" << SHIM
#!/bin/sh
# CMake shim — filters Android flags, delegates to system cmake.
# Auto-generated by ${REPO_NAME}/setup.sh
FILTERED_ARGS=""
for arg in "\$@"; do
    case "\$arg" in
        -DCMAKE_SYSTEM_NAME=Android) ;;
        -DCMAKE_SYSTEM_VERSION=*) ;;
        -DANDROID_PLATFORM=*) ;;
        -DANDROID_ABI=*) ;;
        -DCMAKE_ANDROID_ARCH_ABI=*) ;;
        -DANDROID_NDK=*) ;;
        -DCMAKE_ANDROID_NDK=*) ;;
        -DCMAKE_TOOLCHAIN_FILE=*) ;;
        *) FILTERED_ARGS="\$FILTERED_ARGS \$arg" ;;
    esac
done
exec ${sys_cmake} \$FILTERED_ARGS
SHIM
    chmod +x "${cmake_dir}/cmake"

    if [[ -n "$sys_ninja" ]]; then
        cat > "${cmake_dir}/ninja" << SHIM
#!/bin/sh
exec ${sys_ninja} "\$@"
SHIM
        chmod +x "${cmake_dir}/ninja"
    fi

    ok "CMake ${cmake_version} shim -> ${sys_cmake}"
}

ensure_cmdline_tools() {
    local cmdline_dir="$SDK_ROOT/cmdline-tools/latest"
    if [[ -x "${cmdline_dir}/bin/sdkmanager" ]]; then return 0; fi

    info "Installing Android command-line tools..."
    ensure_commands curl unzip java

    local tmpdir
    tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/adt-install.XXXXXX")"

    curl -fSL -o "${tmpdir}/cmdline-tools.zip" "$CMDLINE_TOOLS_URL" 2>/dev/null \
        || die "Failed to download command-line tools."
    unzip -q "${tmpdir}/cmdline-tools.zip" -d "${tmpdir}" \
        || die "Failed to extract command-line tools."

    mkdir -p "$SDK_ROOT/cmdline-tools"
    rm -rf "$cmdline_dir"
    mv "${tmpdir}/cmdline-tools" "$cmdline_dir"
    rm -rf "$tmpdir"

    ok "Command-line tools installed."
}

run_sdkmanager() {
    local sdkmanager="$SDK_ROOT/cmdline-tools/latest/bin/sdkmanager"
    [[ -x "$sdkmanager" ]] || die "sdkmanager not found. Run: $0 install-cmd-tools"

    # ARM64 guard. sdkmanager serves Google's linux-x86_64 payloads only, and for
    # these two components that means replacing working ARM64 binaries with ones
    # that cannot execute on this host — the failure is invisible until something
    # tries to run them. Platforms/NDK/CMake payloads are arch-neutral or handled
    # by the shims, so only these two are refused at this single choke point
    # (every caller, including bootstrap and profiles, goes through here).
    local arg=""
    for arg in "$@"; do
        case "$arg" in
            build-tools\;*)
                die "'build-tools' must not be installed with sdkmanager on ARM64 (x86_64 payload).\n  Use: $0 install-build-tools <version>   (see '$0 list-versions')" ;;
            platform-tools|platform-tools\;*)
                die "'platform-tools' must not be installed with sdkmanager on ARM64 (x86_64 payload).\n  Use: $0 install-platform-tools <version>   (see '$0 list-versions')" ;;
        esac
    done

    "$sdkmanager" --sdk_root="$SDK_ROOT" "$@"
}

accept_licenses() {
    yes 2>/dev/null | run_sdkmanager --licenses >/dev/null 2>&1 || true
}

# ── Release-download integrity (ARM64 host) ───────────────────────────────────
#
# install_local_artifact has always verified artifacts/SHA256SUMS, but a
# *downloaded* GitHub Release asset was trusted blindly — and under this
# project's ARM64 PRoot, curl can also fail on a perfectly healthy URL when its
# error text is thrown away. Both gaps let a bad payload reach $SDK_ROOT and only
# surface later inside Gradle:
#   * an x86_64 tarball installs just as cleanly as an arm64 one (same names,
#     same exec bits) and only explodes at exec time — the detect_binary_arch
#     trap documented above, and
#   * a failed transfer used to print nothing but "Download failed".
# The helpers below close that: real transfer errors, SHA256 against the
# release's own digest, and payload architecture *before* anything is copied.

# Print "sha256:<hex>" for one release asset, from the GitHub API asset digest.
# Prints nothing when the API is unreachable or the asset carries no digest —
# callers then warn instead of dying, so offline installs keep working.
fetch_release_asset_digest() {
    local release_tag="$1" asset_name="$2"
    command -v curl >/dev/null 2>&1 || return 0
    command -v python3 >/dev/null 2>&1 || return 0

    local auth=()
    [[ -n "${GITHUB_TOKEN:-}" ]] && auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
    [[ -n "${GH_TOKEN:-}" ]] && auth=(-H "Authorization: Bearer ${GH_TOKEN}")

    local json=""
    json="$(curl -fsSL --connect-timeout 20 --max-time 60 \
        -H 'Accept: application/vnd.github+json' "${auth[@]}" \
        "https://api.github.com/repos/${REPO}/releases/tags/${release_tag}" 2>/dev/null)" || return 0
    [[ -n "$json" ]] || return 0

    ADT_RELEASE_JSON="$json" ADT_ASSET_NAME="$asset_name" python3 -c '
import json, os, sys
try:
    release = json.loads(os.environ["ADT_RELEASE_JSON"])
except Exception:
    sys.exit(0)
for asset in release.get("assets") or []:
    if asset.get("name") == os.environ["ADT_ASSET_NAME"]:
        digest = (asset.get("digest") or "").strip()
        if digest.startswith("sha256:"):
            print(digest)
        break
' 2>/dev/null || true
}

# Download one URL with retries and a *visible* failure. Returns non-zero on
# failure; falls back to wget because a PRoot curl can fail where wget succeeds.
download_asset() {
    local url="$1" out="$2"
    local log="${out}.log"
    local progress=() retry_all=()
    # A progress bar writes escape codes into every non-TTY consumer (agent logs,
    # CI) and tells us nothing the error log does not.
    [[ -t 1 ]] && progress=(--progress-bar)

    if command -v curl >/dev/null 2>&1; then
        curl --retry-all-errors --version >/dev/null 2>&1 && retry_all=(--retry-all-errors)
        if curl -fSL --retry 3 --retry-delay 2 "${retry_all[@]}" \
            --connect-timeout 20 --max-time 900 "${progress[@]}" \
            -o "$out" "$url" 2>"$log"; then
            rm -f "$log"
            return 0
        fi
    fi
    if command -v wget >/dev/null 2>&1; then
        warn "Using wget fallback for $(basename "$out")..."
        if wget -q --tries=3 --timeout=60 -O "$out" "$url" 2>>"$log"; then
            rm -f "$log"
            return 0
        fi
    fi
    err "Download failed: $url"
    if [[ -s "$log" ]]; then
        echo -e "    ${DIM}--- transfer log (last 5 lines) ---${NC}"
        tail -n 5 "$log" | sed 's/^/    /'
    fi
    return 1
}

# Verify a downloaded archive against the release's published SHA256.
verify_asset_digest() {
    local archive="$1" expected="$2"
    local actual=""

    command -v sha256sum >/dev/null 2>&1 || return 0
    actual="sha256:$(sha256sum "$archive" | awk '{print $1}')"

    if [[ -z "$expected" ]]; then
        warn "No release digest available for $(basename "$archive") — installing unverified."
        info "  sha256: ${actual#sha256:}"
        return 0
    fi
    if [[ "$actual" != "$expected" ]]; then
        die "SHA256 mismatch for $(basename "$archive"):\n  expected ${expected}\n  got      ${actual}\n  Refusing to install — re-download, or report a corrupted release asset."
    fi
    ok "SHA256 verified against the GitHub release digest."
    return 0
}

# Check an extracted payload's architecture before a single file reaches
# $SDK_ROOT. A wheel of binaries that cannot exec here is fatal; text shims are
# fine (they delegate); an unknown type is reported but not fatal.
verify_payload_arch() {
    local tmpdir="$1" component="$2"
    local bin="" src="" arch="" found=0
    local wrong=() foreign=()

    local bins_ref
    if [[ "$component" == "build-tools" ]]; then
        bins_ref=("${BUILD_TOOLS_BINS[@]}")
    else
        bins_ref=("${PLATFORM_TOOLS_BINS[@]}")
    fi

    for bin in "${bins_ref[@]}"; do
        # The release decides how it nests its payload: flat "build-tools/<bin>",
        # or a full tree such as "android-sdk-linux-arm64/build-tools/<bin>".
        # Search the whole extraction so a missed binary can never turn into a
        # silently skipped check.
        src="$(find "$tmpdir" -type f -name "$bin" -print -quit 2>/dev/null || true)"
        [[ -n "$src" ]] || continue
        found=$((found+1))
        arch="$(detect_binary_arch "$src")"
        case "$arch" in
            arm64|script) : ;;
            x86_64)       wrong+=("$bin") ;;
            *)            foreign+=("$bin (${arch})") ;;
        esac
    done

    if [[ ${#wrong[@]} -gt 0 ]]; then
        die "Refusing to install: $(basename "$tmpdir") payload contains x86_64 binaries (${wrong[*]}).\n  They cannot execute on this ARM64 host; $SDK_ROOT was left untouched.\n  Use a verified ARM64 version: $0 list-versions"
    fi
    if [[ ${#foreign[@]} -gt 0 ]]; then
        warn "Unrecognised architecture: ${foreign[*]}"
    fi
    if [[ $found -gt 0 ]]; then
        ok "Payload architecture OK: ${found} ARM64-compatible binary/binaries."
    fi
    return 0
}

# Install from a checked-in, validated artifact in artifacts/ (offline path).
# Returns 0 on success, 1 when no matching local artifact exists.
install_local_artifact() {
    local component="$1" version="$2" dest_dir="$3"   # component: "build-tools" | "platform-tools"

    resolve_script_dir
    local name="${component}-${version}-linux-arm64.tar.gz"
    local artifact="${SCRIPT_DIR}/artifacts/${name}"
    [[ -f "$artifact" ]] || return 1

    info "Local artifact found: artifacts/${name}"

    # Verify against artifacts/SHA256SUMS when a manifest entry exists
    local sums="${SCRIPT_DIR}/artifacts/SHA256SUMS"
    if [[ -f "$sums" ]] && check_command sha256sum; then
        if grep -qF "artifacts/${name}" "$sums"; then
            (cd "$SCRIPT_DIR" && grep -F "artifacts/${name}" artifacts/SHA256SUMS | sha256sum -c - >/dev/null) \
                || die "Checksum FAILED for artifacts/${name} — refusing to install a corrupted artifact."
            ok "SHA256 verified (artifacts/SHA256SUMS)."
        else
            warn "No checksum entry for ${name} in artifacts/SHA256SUMS — installing without checksum verification."
        fi
    fi

    require_command tar

    local tmpdir
    tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/adt-install.XXXXXX")"
    tar -xzf "$artifact" -C "$tmpdir" || { rm -rf "$tmpdir"; die "Could not extract ${artifact}"; }

    # SHA256 came from artifacts/SHA256SUMS above; this checks what the bytes
    # actually are, so an x86_64 payload never reaches $SDK_ROOT.
    verify_payload_arch "$tmpdir" "$component"

    local bins_ref
    if [[ "$component" == "build-tools" ]]; then
        bins_ref=("${BUILD_TOOLS_BINS[@]}")
    else
        bins_ref=("${PLATFORM_TOOLS_BINS[@]}")
    fi

    mkdir -p "$dest_dir"
    info "Installing binaries to: ${BOLD}${dest_dir}${NC}"

    local installed=0
    for bin in "${bins_ref[@]}"; do
        local src=""
        for candidate in \
            "$tmpdir/${component}/${version}/${bin}" \
            "$tmpdir/${component}/${bin}" \
            "$tmpdir/bin/${bin}" \
            "$tmpdir/${bin}"; do
            if [[ -f "$candidate" ]]; then
                src="$candidate"
                break
            fi
        done
        if [[ -n "$src" ]]; then
            cp "$src" "$dest_dir/$bin"
            chmod +x "$dest_dir/$bin"
            installed=$((installed+1))
            echo -e "    ${GREEN}+${NC} $bin"
        else
            echo -e "    ${YELLOW}-${NC} $bin ${DIM}(not found in artifact)${NC}"
        fi
    done

    # Carry SDK metadata files when present
    for meta in source.properties package.xml; do
        for candidate in \
            "$tmpdir/${component}/${version}/${meta}" \
            "$tmpdir/${component}/${meta}"; do
            if [[ -f "$candidate" ]]; then
                cp "$candidate" "$dest_dir/$meta"
                break
            fi
        done
    done

    rm -rf "$tmpdir"
    if [[ $installed -eq 0 ]]; then
        die "Artifact ${name} contained no expected ${component} binaries — archive layout mismatch."
    fi
    ok "Installed ${installed} binaries from local artifact."
    return 0
}

# Download a release tarball and install binaries
download_and_install_release() {
    local release_tag="$1"
    local dest_dir="$2"
    local component="$3"  # "build-tools" or "platform-tools"

    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
        die "Required command 'curl' or 'wget' not found. Please install one of them."
    fi
    require_command tar

    local version="${release_tag#v}"

    # Try the current artifact naming first, then legacy upstream names
    local tarballs=(
        "${component}-${version}-linux-arm64.tar.gz"
        "android-sdk-linux-arm64-${component}-${version}.tar.gz"
        "android-sdk-linux-arm64-${release_tag}.tar.gz"
    )

    local tmpdir
    tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/adt-install.XXXXXX")"
    local downloaded=""

    for tarball in "${tarballs[@]}"; do
        local url="https://github.com/${REPO}/releases/download/${release_tag}/${tarball}"
        info "Trying ${tarball}..."
        if download_asset "$url" "$tmpdir/$tarball"; then
            downloaded="$tarball"
            break
        fi
    done

    if [[ -z "$downloaded" ]]; then
        rm -rf "$tmpdir"
        die "Download failed. Check: ${REPO_URL}/releases/tag/${release_tag}"
    fi

    # Integrity first: the archive is verified against the release's own digest
    # and its payload architecture before $SDK_ROOT is touched at all.
    local expected_digest=""
    expected_digest="$(fetch_release_asset_digest "$release_tag" "$downloaded")"
    verify_asset_digest "$tmpdir/$downloaded" "$expected_digest"

    info "Extracting ${downloaded}..."
    tar -xzf "$tmpdir/$downloaded" -C "$tmpdir" || { rm -rf "$tmpdir"; die "Could not extract ${downloaded} — not a valid gzip tarball."; }

    verify_payload_arch "$tmpdir" "$component"

    mkdir -p "$dest_dir"
    info "Installing binaries to: ${BOLD}${dest_dir}${NC}"

    local bins_ref
    if [[ "$component" == "build-tools" ]]; then
        bins_ref=("${BUILD_TOOLS_BINS[@]}")
    else
        bins_ref=("${PLATFORM_TOOLS_BINS[@]}")
    fi

    local installed=0
    for bin in "${bins_ref[@]}"; do
        # Look for binary in extracted tree
        local src=""
        for candidate in \
            "$tmpdir/${component}/$bin" \
            "$tmpdir/bin/$bin" \
            "$tmpdir/$bin" \
            "$tmpdir"/*/"$bin"; do
            if [[ -f "$candidate" ]]; then
                src="$candidate"
                break
            fi
        done
        if [[ -n "$src" ]]; then
            cp "$src" "$dest_dir/$bin"
            chmod +x "$dest_dir/$bin"
            installed=$((installed+1))
            echo -e "    ${GREEN}+${NC} $bin"
        else
            echo -e "    ${YELLOW}-${NC} $bin ${DIM}(not found in tarball)${NC}"
        fi
    done

    rm -rf "$tmpdir"
    if [[ $installed -eq 0 ]]; then
        die "Release ${release_tag} contained no expected ${component} binaries — archive layout mismatch."
    fi
    ok "Installed ${installed} binaries."
}

# Build tools from AOSP source
build_tools_from_source() {
    local component="$1"  # "build-tools" or "platform-tools"
    local version="$2"

    header "Building ${component} ${version} from source"

    # Check + auto-install build dependencies
    ensure_build_deps

    # Find AOSP tag
    local aosp_tag
    aosp_tag="$(get_aosp_tag "$component" "$version" 2>/dev/null || echo "")"
    if [[ -z "$aosp_tag" ]]; then
        # Fallback: try platform-tools-<version>
        aosp_tag="platform-tools-${version}"
        warn "No AOSP tag in versions.json, trying: ${aosp_tag}"
    fi

    # Determine source directory
    resolve_script_dir
    local build_dir="$SCRIPT_DIR"

    if [[ ! -f "${build_dir}/repos.json" ]] || [[ ! -f "${build_dir}/build.py" ]]; then
        # Clone the repo
        build_dir="$(mktemp -d "${TMPDIR:-/tmp}/adt-install.XXXXXX")/${REPO_NAME}"
        info "Cloning build system..."
        git clone --depth 1 "$REPO_URL" "$build_dir" \
            || die "Failed to clone repository."
    fi

    local versioned_build="${build_dir}/build/${component}-${version}"

    echo ""
    echo "  AOSP tag:    ${aosp_tag}"
    echo "  Source dir:  ${build_dir}/src/ (~2-4 GB)"
    echo "  Build dir:   ${versioned_build}/"
    echo "  Output:      ${versioned_build}/bin/ (flat)"
    echo ""

    # Clone AOSP sources
    info "Cloning AOSP sources (tag: ${aosp_tag})..."
    python3 "${build_dir}/get_source.py" --tags "$aosp_tag" \
        --component "$component" --version "$version"

    # Build protoc
    local protoc_path="${build_dir}/src/protobuf/build/protoc"
    if [[ ! -x "$protoc_path" ]]; then
        info "Building host protoc..."
        mkdir -p "${build_dir}/src/protobuf/build"

        # Copy config.h — try version-specific, then base
        local config_src=""
        for candidate in \
            "${build_dir}/patches/${component}/${version}/misc/protobuf_config.h" \
            "${build_dir}/patches/base/misc/protobuf_config.h"; do
            if [[ -f "$candidate" ]]; then
                config_src="$candidate"
                break
            fi
        done
        if [[ -n "$config_src" ]]; then
            cp "$config_src" "${build_dir}/src/protobuf/build/config.h"
        fi

        cmake -GNinja \
            -B "${build_dir}/src/protobuf/build" \
            -S "${build_dir}/src/protobuf" \
            -Dprotobuf_BUILD_TESTS=OFF \
            || die "protoc cmake failed."

        ninja -C "${build_dir}/src/protobuf/build" -j"$(nproc)" protoc \
            || die "protoc build failed."
        ok "protoc built."
    fi

    # Build all tools
    info "Building SDK tools..."
    python3 "${build_dir}/build.py" \
        --protoc="$protoc_path" \
        --build="$versioned_build" \
        || die "Build failed."

    # Install binaries
    local build_bin="${versioned_build}/bin"
    [[ -d "$build_bin" ]] || die "Build output not found at ${build_bin}"

    if [[ "$component" == "build-tools" ]]; then
        local dest="$SDK_ROOT/build-tools/${version}"
        mkdir -p "$dest"
        info "Copying build-tools binaries to: ${BOLD}${dest}${NC}"
        for bin in "${BUILD_TOOLS_BINS[@]}"; do
            if [[ -f "${build_bin}/${bin}" ]]; then
                cp "${build_bin}/${bin}" "$dest/" && chmod +x "$dest/$bin"
                echo -e "    ${GREEN}+${NC} $bin"
            else
                echo -e "    ${YELLOW}-${NC} $bin ${DIM}(not built)${NC}"
            fi
        done
        ok "build-tools installed to ${dest}"
    else
        local dest="$SDK_ROOT/platform-tools"
        mkdir -p "$dest"
        info "Copying platform-tools binaries to: ${BOLD}${dest}${NC}"
        for bin in "${PLATFORM_TOOLS_BINS[@]}"; do
            if [[ -f "${build_bin}/${bin}" ]]; then
                cp "${build_bin}/${bin}" "$dest/" && chmod +x "$dest/$bin"
                echo -e "    ${GREEN}+${NC} $bin"
            else
                echo -e "    ${YELLOW}-${NC} $bin ${DIM}(not built)${NC}"
            fi
        done
        ok "platform-tools installed to ${dest}"
    fi

    # Source builds download ~2-4 GB (AOSP source tree + build output).
    # The binaries are now installed in the SDK — offer to reclaim the space.
    # (On failure, 'die' aborts before this point and the trees stay put for
    # debugging; './setup.sh cleanup' removes them later either way.)
    local total_size
    total_size="$(du -shc "${build_dir}/src" "$versioned_build" 2>/dev/null | tail -1 | cut -f1)" || true
    if confirm "Build finished — delete AOSP source + build trees (${total_size:-unknown size})? Installed binaries stay in the SDK."; then
        sweep_item "${build_dir}/src" "AOSP source tree"
        sweep_item "$versioned_build" "build output tree"
        # If the build system itself was a temp clone, remove it whole
        if [[ "$build_dir" == "${TMPDIR:-/tmp}"/adt-install.??????/* ]]; then
            sweep_item "${build_dir%/*}" "temp build-system clone"
        fi
    else
        info "Kept for inspection — remove later with: $0 cleanup"
    fi
}

# ── setup-env ────────────────────────────────────────────────────────────────

cmd_setup_env() {
    detect_sdk_root
    write_env_block
    ok "Environment configured."
}

# ── cleanup ──────────────────────────────────────────────────────────────────
# Remove installer leftovers: our prefixed temp dirs (including failed-download
# remnants), sdkmanager's temp dir, and the apt cache when privilege allows.
# ADT temp dirs always use the ${TMPDIR:-/tmp}/adt-install.XXXXXX prefix so this sweep
# is safe — it can never match unrelated files.

sweep_item() {
    local path="$1" label="$2" size=""
    [[ -e "$path" ]] || return 0
    size="$(du -sh "$path" 2>/dev/null | cut -f1)" || true
    if rm -rf "$path" 2>/dev/null; then
        ok "Removed ${label}: ${path}${size:+ (freed ${size})}"
    else
        warn "Could not remove ${path} — remove it manually"
    fi
}

cmd_cleanup() {
    take_sdk_root_arg "$@"
    detect_sdk_root
    header "Temporary cleanup"
    sweep_item "$SDK_ROOT/.temp" "sdkmanager temp"
    # Source-build trees (~2-4 GB each) when the build system lives in this
    # checkout and a build kept them for inspection
    resolve_script_dir
    if [[ -f "$SCRIPT_DIR/repos.json" && -f "$SCRIPT_DIR/build.py" ]]; then
        sweep_item "$SCRIPT_DIR/src" "AOSP source tree"
        sweep_item "$SCRIPT_DIR/build" "build output tree"
    fi
    # Only our own mktemp dirs: prefix 'adt-install.' + exactly 6 random chars.
    local d
    for d in "${TMPDIR:-/tmp}"/adt-install.??????; do
        sweep_item "$d" "installer temp"
    done
    if command -v apt-get >/dev/null 2>&1 && as_root apt-get clean >/dev/null 2>&1; then
        ok "Package cache cleaned (apt-get clean)"
    fi
    ok "Cleanup done — nothing else to optimize: ADT has no daemons, caches, or background state"
}

# ── bootstrap ────────────────────────────────────────────────────────────────

ADT_SETUP_ITEMS=(host build-tools platform-tools ndk cmake cmdline platform env cleanup)
ADT_SETUP_GROUPS=(SYSTEM BUILD ADB NDK BUILD SDK API SHELL CLEANUP)
ADT_SETUP_LABELS=()
ADT_SETUP_SELECTED=()

adt_toggle_setup_item() {
    local item="$1" i
    for i in "${!ADT_SETUP_SELECTED[@]}"; do
        if [[ "${ADT_SETUP_SELECTED[$i]}" == "$item" ]]; then
            unset 'ADT_SETUP_SELECTED[i]'
            ADT_SETUP_SELECTED=("${ADT_SETUP_SELECTED[@]}")
            return
        fi
    done
    ADT_SETUP_SELECTED+=("$item")
}

adt_ui_center_line() {
    local text="$1" color="${2:-$CYAN}" width="$3" length left right
    (( width >= 1 )) || return 0
    text="${text:0:width}"
    length=${#text}; left=$(((width - length) / 2)); right=$((width - length - left))
    printf '  %s|%s%*s%b%s%b%*s%s|%s\n' "$CYAN" "$NC" "$left" '' "$color" "$text" "$NC" "$right" '' "$CYAN" "$NC"
}

adt_ui_logo_line() {
    local text="$1" tick="$2" width="$3" i ch left right phase content="" color
    local -a primary=("$GREEN" "$CYAN" "$BLUE" "$GREEN" "$CYAN" "$BLUE")
    local -a accent=("$YELLOW" "$RED" "$DIM" "$YELLOW" "$RED" "$DIM")
    (( width >= 1 )) || return 0
    text="${text:0:width}"
    left=$(((width - ${#text}) / 2)); right=$((width - ${#text} - left))
    content="$(printf '%*s' "$left" '')"
    for ((i=0; i<${#text}; i++)); do
        ch="${text:i:1}"
        if [[ "$ch" == '#' || "$ch" == '_' ]]; then
            phase=$(((i + tick) % ${#primary[@]}))
            color="${primary[$phase]}"
            [[ "$ch" == '_' ]] && color="${accent[$(((i + tick) % ${#accent[@]}))]}"
            content+="${BOLD}${color}${ch}${NC}"
        else
            content+="$ch"
        fi
    done
    printf '  %s|%s%s%*s%s|%s\n' "$CYAN" "$NC" "$content" "$right" '' "$CYAN" "$NC"
}

adt_draw_setup_menu() {
    local cursor="$1" size="${2:-}" tick="${3:-0}" rows cols visible start end i mark pointer group_color width label selected_count=0 inner fixed_rows
    local -a wave=("$CYAN" "$GREEN" "$BLUE" "$YELLOW")
    if [[ "$size" =~ ^[0-9]+[[:space:]][0-9]+$ ]]; then read -r rows cols <<<"$size"; else rows="$(tput lines 2>/dev/null || printf 24)"; cols="$(tput cols 2>/dev/null || printf 80)"; fi
    (( rows > 0 )) || rows=24; (( cols > 0 )) || cols=80
    width=$((cols - 2)); (( width > 78 )) && width=78; (( width < 8 )) && width=8
    inner=$((width - 4)); (( inner < 4 )) && inner=4
    fixed_rows=14; (( inner < 52 )) && fixed_rows=15
    visible=$((rows - fixed_rows)); (( visible < 1 )) && visible=1; (( visible > ${#ADT_SETUP_ITEMS[@]} )) && visible=${#ADT_SETUP_ITEMS[@]}
    start=0; (( cursor >= visible )) && start=$((cursor - visible + 1))
    end=$((start + visible)); (( end > ${#ADT_SETUP_ITEMS[@]} )) && end=${#ADT_SETUP_ITEMS[@]}
    for i in "${!ADT_SETUP_ITEMS[@]}"; do [[ " ${ADT_SETUP_SELECTED[*]} " == *" ${ADT_SETUP_ITEMS[$i]} "* ]] && ((selected_count+=1)); done
    printf '\033[H\033[2J'
    printf '  %s+%s+%s\n' "$CYAN" "$(printf '%*s' "$((width - 2))" '' | tr ' ' '-')" "$CYAN"
    if (( inner >= 19 )); then
        adt_ui_logo_line '  #    ####   #####' "$tick" "$inner"
        adt_ui_logo_line ' #_#   #___#  __#__' "$((tick + 1))" "$inner"
        adt_ui_logo_line '#####  #   #    #  ' "$((tick + 2))" "$inner"
        adt_ui_logo_line '#   #  #   #    #  ' "$((tick + 3))" "$inner"
        adt_ui_logo_line '#   #  ####    #  ' "$((tick + 4))" "$inner"
    else
        adt_ui_logo_line '### ##_ ###' "$tick" "$inner"
        adt_ui_logo_line '#_# #_# _#_' "$((tick + 1))" "$inner"
        adt_ui_logo_line '### # #  # ' "$((tick + 2))" "$inner"
        adt_ui_logo_line '# # #_#  # ' "$((tick + 3))" "$inner"
        adt_ui_logo_line '# # ##_  # ' "$((tick + 4))" "$inner"
    fi
    adt_ui_center_line 'Linux Workstation In Your Pocket' "${wave[$(((tick + 2) % 4))]}" "$inner"
    adt_ui_center_line 'by @soobujmiah' "${wave[$(((tick + 3) % 4))]}" "$inner"
    printf '  %s+%s+%s\n' "$CYAN" "$(printf '%*s' "$((width - 2))" '' | tr ' ' '-')" "$CYAN"
    printf '  %sADT OPTIONAL COMPONENTS%s  %s%d/%d selected%s\n' "$BOLD" "$NC" "$CYAN" "$selected_count" "${#ADT_SETUP_ITEMS[@]}" "$NC"
    if (( inner >= 52 )); then
        printf '  %s↑/↓ j/k%s move  %sSpace/1–9%s toggle  %sEnter%s continue  %sq%s none\n' "$YELLOW" "$NC" "$GREEN" "$NC" "$BOLD" "$NC" "$DIM" "$NC"
    else
        adt_ui_center_line '↑/↓ or j/k: move' "$YELLOW" "$inner"
        adt_ui_center_line 'Space: toggle · Enter: next · q: none' "$GREEN" "$inner"
    fi
    for ((i=start; i<end; i++)); do
        mark=' '; group_color="$BLUE"; pointer=' '
        [[ " ${ADT_SETUP_SELECTED[*]} " == *" ${ADT_SETUP_ITEMS[$i]} "* ]] && mark='+' && group_color="$GREEN"
        [[ "${ADT_SETUP_GROUPS[$i]}" == ADB ]] && group_color="$CYAN"
        [[ "${ADT_SETUP_GROUPS[$i]}" == NDK ]] && group_color="$YELLOW"
        [[ "${ADT_SETUP_GROUPS[$i]}" == CLEANUP ]] && group_color="$DIM"
        [[ $i -eq $cursor ]] && pointer="${YELLOW}>${NC}"
        label="${ADT_SETUP_LABELS[$i]}"
        if (( inner >= 24 )); then
            printf '  %s|%s %b%s%s %s%2d%s %s%-7s%s %-*.*s %s|%s\n' "$CYAN" "$NC" "$pointer" "$group_color" "$mark" "$DIM" "$((i + 1))" "$NC" "$group_color" "${ADT_SETUP_GROUPS[$i]}" "$NC" "$((inner - 17))" "$((inner - 17))" "$label" "$CYAN" "$NC"
        else
            printf '  %s|%s %b%s%s %s%2d%s %-*.*s %s|%s\n' "$CYAN" "$NC" "$pointer" "$group_color" "$mark" "$DIM" "$((i + 1))" "$NC" "$((inner - 9))" "$((inner - 9))" "$label" "$CYAN" "$NC"
        fi
    done
    printf '  %s+%s+%s\n' "$CYAN" "$(printf '%*s' "$((width - 2))" '' | tr ' ' '-')" "$CYAN"
    printf '  %sSpace: toggle  ·  Enter: review and install%s\n' "$DIM" "$NC"
    printf '  %s© github.com/soobujmiah - 2026%s\n' "$CYAN" "$NC"
}

adt_choose_setup_components() {
    local bt="$1" pt="$2" ndk="$3" cursor=0 key seq i result="" size new_size read_status
    ADT_SETUP_LABELS=(
        "Missing host dependencies"
        "Build Tools ${bt} (verified; choose version next)"
        "Platform Tools ${pt} (ADB + fastboot; choose version next)"
        "NDK ${ndk} system shim"
        "CMake system shim"
        "Google SDK command-line tools"
        "Android API 36 platform"
        "Shell environment (ANDROID_HOME + PATH)"
        "Temporary files and package cache cleanup"
    )
    ADT_SETUP_SELECTED=("${ADT_SETUP_ITEMS[@]}")
    [[ "$INTERACTIVE" == "1" ]] || { printf '%s\n' "${ADT_SETUP_ITEMS[*]}"; return; }
    if { exec 3<>/dev/tty; } 2>/dev/null; then
        local old_stty
        old_stty="$(stty -g <&3 2>/dev/null || true)"
        stty -echo -icanon min 1 time 0 <&3 2>/dev/null || true
        printf '\033[?25l' >&3
        size="$(stty size <&3 2>/dev/null || true)"
        local tick=0
        adt_draw_setup_menu "$cursor" "$size" "$tick" >&3
        while :; do
            key=""; IFS= read -r -s -n 1 -t 0.5 -u 3 key; read_status=$?
            if (( read_status > 128 )); then
                new_size="$(stty size <&3 2>/dev/null || true)"
                ((tick+=1))
                if [[ "$new_size" != "$size" ]]; then size="$new_size"; fi
                adt_draw_setup_menu "$cursor" "$size" "$tick" >&3
                continue
            fi
            (( read_status == 0 )) || break
            case "$key" in
                $'\033') IFS= read -r -s -n 2 -t 1 -u 3 seq || seq=""; case "$seq" in '[A') (( cursor > 0 )) && cursor=$((cursor - 1)) ;; '[B') (( cursor + 1 < ${#ADT_SETUP_ITEMS[@]} )) && cursor=$((cursor + 1)) ;; esac ;;
                k) (( cursor > 0 )) && cursor=$((cursor - 1)) ;;
                j) (( cursor + 1 < ${#ADT_SETUP_ITEMS[@]} )) && cursor=$((cursor + 1)) ;;
                ' ') adt_toggle_setup_item "${ADT_SETUP_ITEMS[$cursor]}" ;;
                [1-9]) i=$((10#$key - 1)); (( i < ${#ADT_SETUP_ITEMS[@]} )) && adt_toggle_setup_item "${ADT_SETUP_ITEMS[$i]}" ;;
                ''|$'\r'|$'\n') break ;;
                q|Q) ADT_SETUP_SELECTED=(); break ;;
            esac
            size="$(stty size <&3 2>/dev/null || true)"
            ((tick+=1)); adt_draw_setup_menu "$cursor" "$size" "$tick" >&3
        done
        [[ -n "$old_stty" ]] && stty "$old_stty" <&3 2>/dev/null || true
        printf '\033[?25h\033[H\033[2J' >&3
        exec 3>&-
    else
        echo "" >&2
        for i in "${!ADT_SETUP_ITEMS[@]}"; do printf '  %2d) %s\n' "$((i + 1))" "${ADT_SETUP_LABELS[$i]}" >&2; done
        read -rp "  Select numbers (default: all, 0: none): " result || result=""
        if [[ -n "$result" ]]; then
            ADT_SETUP_SELECTED=()
            [[ "$result" == "0" ]] && { printf '\n'; return 0; }
            for i in $result; do
                [[ "$i" =~ ^[0-9]+$ ]] && (( i >= 1 && i <= ${#ADT_SETUP_ITEMS[@]} )) || die "Choose a listed number."
                ADT_SETUP_SELECTED+=("${ADT_SETUP_ITEMS[$((i - 1))]}")
            done
        fi
    fi
    printf '%s\n' "${ADT_SETUP_SELECTED[*]}"
}

adt_step_selected() { [[ " $ADT_SELECTED_STEPS " == *" $1 "* ]]; }

adt_pick_release_version() {
    local component="$1" preferred="$2" json choice index
    local -a versions=()
    [[ "$INTERACTIVE" == "1" ]] || { printf '%s\n' "$preferred"; return; }
    json="$(get_versions_json)"
    while IFS= read -r choice; do [[ -n "$choice" ]] && versions+=("$choice"); done < <(python3 -c '
import json,sys
d=json.load(sys.stdin)
for v,item in d.get(sys.argv[1],{}).items():
    if item.get("status")=="verified" and item.get("release"):
        print(v)
' "$component" <<<"$json")
    (( ${#versions[@]} > 0 )) || { printf '%s\n' "$preferred"; return; }
    printf '\n  %sAvailable %s releases%s\n' "$CYAN" "$component" "$NC" >&2
    for index in "${!versions[@]}"; do
        local marker=""
        [[ "${versions[$index]}" == "$preferred" ]] && marker=" (recommended)"
        printf '    %d) %s%s\n' "$((index + 1))" "${versions[$index]}" "$marker" >&2
    done
    read -rp "  Version number [default: $preferred]: " choice || choice=""
    [[ -z "$choice" ]] && { printf '%s\n' "$preferred"; return; }
    [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#versions[@]} )) || die "Choose a listed version number."
    printf '%s\n' "${versions[$((choice - 1))]}"
}

# Full automatic setup for a fresh ARM64 device:
# device check -> host deps -> SDK tools -> shims -> Google packages -> env -> verify -> guide
cmd_bootstrap() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --sdk-root)   SDK_ROOT="$2"; shift 2 ;;
            --auto|-y)    INTERACTIVE=0; shift ;;
            *) die "Unknown option: $1" ;;
        esac
    done

    if [[ "$INTERACTIVE" == "1" ]]; then
        echo "  Guided setup. Review the components, then toggle only what you need."
        echo "  Unattended mode: ./setup.sh bootstrap --auto"
    fi

    # Phase 0 — automatic device/environment check (always read-only)
    detect_environment

    local bt_version pt_version ndk_default
    bt_version="$(get_bootstrap_version build-tools)" || die "No verified build-tools version in versions.json"
    pt_version="$(get_bootstrap_version platform-tools)" || die "No verified platform-tools version in versions.json"
    ndk_default="$(get_bootstrap_ndk)" || ndk_default=""
    local ADT_SELECTED_STEPS
    ADT_SELECTED_STEPS="$(adt_choose_setup_components "$bt_version" "$pt_version" "${ndk_default:-not registered}")"
    if [[ "$INTERACTIVE" == "1" && -t 1 ]]; then export ADT_GUIDED_UI=1; else unset ADT_GUIDED_UI; fi
    if adt_step_selected build-tools; then bt_version="$(adt_pick_release_version build-tools "$bt_version")"; fi
    if adt_step_selected platform-tools; then pt_version="$(adt_pick_release_version platform-tools "$pt_version")"; fi

    # Phase 1 — host dependencies
    header "1/7  Host dependencies"
    if adt_step_selected host; then
        ensure_commands git curl tar unzip python3 java cmake ninja llvm-strip
    else
        info "Skipped by selection"
    fi

    # Phase 2 — SDK location
    # Phase 3 — native tools (prefers checked-in, SHA256-verified artifacts; offline)
    header "2/7  build-tools + platform-tools"
    if adt_step_selected build-tools; then
        cmd_install_build_tools "$bt_version"
    else
        info "Skipped by selection"
    fi
    if adt_step_selected platform-tools; then
        cmd_install_platform_tools "$pt_version"
    else
        info "Skipped by selection"
    fi

    # Phase 4 — shims (device-tested NDK version preferred)
    header "3/7  NDK + CMake shims"
    local ndk_version=""
    if [[ -n "$ndk_default" ]] && adt_step_selected ndk; then
        cmd_install_ndk "$ndk_default"
    else
        info "NDK shim skipped or no verified registry version is available"
    fi
    if adt_step_selected cmake; then
        local cmake_version
        cmake_version="$(python3 -c 'import json,sys; d=json.load(sys.stdin); print(next((v for v,x in d.get("cmake",{}).items() if x.get("status")=="shim"), "3.22.1"))' <<<"$(get_versions_json)")"
        cmd_install_cmake "$cmake_version"
    else
        info "CMake shim skipped by selection"
    fi

    # Phase 5 — Google packages (network)
    header "4/7  sdkmanager + Android platform"
    if adt_step_selected cmdline || adt_step_selected platform; then
        cmd_install_cmd_tools
    fi
    if adt_step_selected platform; then
        cmd_install_platforms android-36
    else
        info "Android platform skipped; install later with: $0 install-cmd-tools && $0 install-platforms android-36"
    fi

    # Phase 6 — persistent shell environment
    header "5/7  Shell environment"
    if adt_step_selected env; then
        write_env_block
    else
        info "Skipped by selection — run '$0 setup-env' any time"
    fi

    # Verification + final guide
    header "6/7  Verification"
    cmd_doctor

    # Final — temporary cleanup (temp dirs, sdkmanager temp, apt cache)
    header "7/7  Cleanup"
    if adt_step_selected cleanup; then
        cmd_cleanup
    else
        info "Skipped by selection — run '$0 cleanup' any time"
    fi
    print_post_install_guide
}

# ── NDK version detection ─────────────────────────────────────────────────────

detect_ndk_version() {
    local project_dir="${1:-.}"
    local build_gradle=""

    for f in \
        "${project_dir}/android/app/build.gradle" \
        "${project_dir}/android/app/build.gradle.kts"; do
        [[ -f "$f" ]] && build_gradle="$f" && break
    done
    [[ -z "$build_gradle" ]] && return 1

    local version
    version=$(grep -oP 'ndkVersion\s*[=: ]\s*"?\K[0-9]+\.[0-9]+\.[0-9]+' "$build_gradle" 2>/dev/null \
        || grep -oP "flutter\.ndkVersion" "$build_gradle" 2>/dev/null \
        || echo "")

    if [[ "$version" == "flutter.ndkVersion" ]]; then
        local flutter_sdk=""
        if [[ -n "${FLUTTER_ROOT:-}" ]]; then
            flutter_sdk="$FLUTTER_ROOT"
        elif check_command flutter; then
            flutter_sdk="$(dirname "$(dirname "$(readlink -f "$(command -v flutter)")")")"
        fi
        if [[ -n "$flutter_sdk" ]]; then
            for f in \
                "${flutter_sdk}/packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt" \
                "${flutter_sdk}/packages/flutter_tools/gradle/flutter.groovy"; do
                if [[ -f "$f" ]]; then
                    local found
                    found=$(grep -oP 'ndkVersion[^=]*=\s*"?\K[0-9]+\.[0-9]+\.[0-9]+' "$f" 2>/dev/null || echo "")
                    [[ -n "$found" ]] && version="$found" && break
                fi
            done
        fi
    fi

    [[ -n "$version" && "$version" != "flutter.ndkVersion" ]] && echo "$version" && return 0
    return 1
}

# ── help ───────────────────────────────────────────────────────────────────────

cmd_help() {
    cat << 'BANNER'

  Android SDK Tools for Linux ARM64
  ==================================

BANNER

    echo -e "  ${BOLD}FRESH DEVICE${NC}"
    echo ""
    echo "    bootstrap [--auto]              Full setup, start to finish. Default: guided"
    echo "                                    (device check first, asks permission per step)."
    echo "                                    --auto: unattended, sane defaults, no prompts."
    echo "    (no command)                    Same as guided bootstrap"
    echo "    cleanup                         Remove temp dirs, sdkmanager temp, apt cache"
    echo ""
    echo -e "  ${BOLD}INSTALL COMMANDS${NC}"
    echo ""
    echo "    install-build-tools <version>     Install build-tools (aapt2, aapt, aidl, ...)"
    echo "    install-platform-tools <version>  Install platform-tools (adb, fastboot, ...)"
    echo "    install-ndk <version>             Create NDK shim (llvm-strip)"
    echo "    install-cmake [version]           Create CMake shim (default: 3.22.1)"
    echo "    install-cmd-tools                 Install sdkmanager"
    echo "    install-platforms [packages]      Install Android platforms"
    echo "    install-profile [name]            Install a named bundle of verified versions (default: validated)"
    echo ""
    echo -e "  ${BOLD}BUILD COMMANDS${NC} ${DIM}(from AOSP source)${NC}"
    echo ""
    echo "    build-all                         Build + install everything (default versions)"
    echo "    build-build-tools <version>       Build build-tools from AOSP source"
    echo "    build-platform-tools <version>    Build platform-tools from AOSP source"
    echo ""
    echo -e "  ${BOLD}INFO COMMANDS${NC}"
    echo ""
    echo "    list-versions                     Show all available versions"
    echo "    status                            Show what's installed"
    echo "    doctor                            Diagnose setup issues"
    echo "    setup-gradle                      Configure Gradle aapt2 override"
    echo "    setup-env                         Write ANDROID_HOME/PATH to ~/.bashrc"
    echo ""
    echo -e "  ${BOLD}OPTIONS${NC}"
    echo ""
    echo "    --sdk-root <path>    Override Android SDK directory"
    echo ""
    echo -e "  ${BOLD}SDK ROOT DETECTION${NC} ${DIM}(in priority order)${NC}"
    echo ""
    echo "    1. --sdk-root <path>        (if passed)"
    echo "    2. \$ANDROID_HOME            (if set)"
    echo "    3. \$ANDROID_SDK_ROOT        (if set)"
    echo "    4. ~/Android/Sdk            (if exists)"
    echo "    5. ~/android-sdk            (default, created if needed)"
    echo ""
    echo -e "  ${BOLD}QUICK START${NC}"
    echo ""
    echo "    ./setup.sh install-build-tools 35.0.2"
    echo "    ./setup.sh install-platform-tools 35.0.2"
    echo "    ./setup.sh install-ndk 28.2.13676358"
    echo "    ./setup.sh install-cmake"
    echo "    ./setup.sh install-cmd-tools"
    echo "    ./setup.sh install-platforms android-35"
    echo "    ./setup.sh doctor"
    echo ""
    echo -e "  ${BOLD}REPO${NC}  ${REPO_URL}"
    echo ""
}

# ── Main ───────────────────────────────────────────────────────────────────────

main() {
    if [[ $# -eq 0 ]]; then
        # Bare invocation = guided full setup (per-device check first, permission
        # before every change). For pure documentation: ./setup.sh help
        cmd_bootstrap
        exit 0
    fi

    local command="$1"
    shift

    case "$command" in
        bootstrap)              cmd_bootstrap "$@" ;;
        setup-env)              cmd_setup_env "$@" ;;
        cleanup)                cmd_cleanup "$@" ;;
        list-versions)          cmd_list_versions "$@" ;;
        install-build-tools)    cmd_install_build_tools "$@" ;;
        install-platform-tools) cmd_install_platform_tools "$@" ;;
        install-ndk)            cmd_install_ndk "$@" ;;
        install-cmake)          cmd_install_cmake "$@" ;;
        install-cmd-tools)      cmd_install_cmd_tools "$@" ;;
        install-platforms)      cmd_install_platforms "$@" ;;
        install-profile)        cmd_install_profile "$@" ;;
        build-build-tools)      cmd_build_build_tools "$@" ;;
        build-platform-tools)   cmd_build_platform_tools "$@" ;;
        build-all)              cmd_build_all "$@" ;;
        setup-gradle)           cmd_setup_gradle "$@" ;;
        doctor)                 cmd_doctor "$@" ;;
        status)                 cmd_status "$@" ;;
        help|--help|-h)         cmd_help ;;
        *)
            err "Unknown command: $command"
            echo "  Run '$0 help' for usage."
            exit 1
            ;;
    esac
}

# ADT_SOURCE_ONLY=1 lets tests `source` this file to reuse its functions
# (e.g. detect_binary_arch) without triggering a real command. Unset/empty
# is the normal case for every existing invocation of this script.
if [[ "${ADT_SOURCE_ONLY:-0}" != "1" ]]; then
    adt_banner
    trap 'adt_status=$?; adt_signature "$adt_status"' EXIT
    main "$@"
fi
