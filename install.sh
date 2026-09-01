#!/usr/bin/env bash
# =============================================================================
#  Android SDK ARM64 (ADT) — one-line installer
# =============================================================================
#
#  One-liner (fully automatic, no prompts):
#
#      curl -fsSL https://raw.githubusercontent.com/soobujmiah/adt/main/install.sh | bash
#
#  What it does:
#    1. Fetches the repo into $ADT_DIR      (git clone when git exists,
#       otherwise the GitHub tarball — only curl + tar are required)
#    2. Runs:  setup.sh bootstrap --auto    (device check → deps → tools →
#       shims → sdkmanager + platform → env → verification → guide)
#
#  Notes:
#    - The piped one-liner is ALWAYS unattended: prompts cannot work when the
#      script itself is reading stdin. For the guided experience, clone and
#      run ./setup.sh instead.
#    - Idempotent: re-running updates an existing git clone (fast-forward
#      only) or reuses the directory; bootstrap skips what is already installed.
#
#  Environment variables:
#    ADT_DIR          Install location          (default: $HOME/adt)
#    ADT_REF          Git branch/tag            (default: main)
#    ADT_REPO_URL     Git remote (for tests)    (default: github repo)
#    ADT_TARBALL_URL  Archive URL (for tests)   (default: github codeload)
#
# =============================================================================

set -euo pipefail

ADT_DIR="${ADT_DIR:-$HOME/adt}"
ADT_REF="${ADT_REF:-main}"
ADT_REPO_URL="${ADT_REPO_URL:-https://github.com/soobujmiah/adt.git}"
ADT_TARBALL_URL="${ADT_TARBALL_URL:-https://codeload.github.com/soobujmiah/adt/tar.gz/refs/heads/${ADT_REF}}"

info() { echo ":: $*"; }
die()  { echo ":: ERROR: $*" >&2; exit 1; }

echo ""
echo "  ADT one-line installer (automatic mode)"
echo "  install dir : $ADT_DIR"
echo "  ref         : $ADT_REF"
echo ""

# ---------------------------------------------------------------------------
# 1. Get the repo into $ADT_DIR
# ---------------------------------------------------------------------------
if [[ -d "$ADT_DIR/.git" ]] && command -v git >/dev/null 2>&1; then
    info "Existing clone found — updating (fast-forward only)"
    git -C "$ADT_DIR" pull --ff-only || echo ":: WARNING: git pull failed; installing from existing checkout"
elif [[ -d "$ADT_DIR" ]]; then
    info "$ADT_DIR already exists (not a git clone) — reusing it"
elif command -v git >/dev/null 2>&1; then
    info "Cloning (shallow)..."
    git clone --depth 1 --branch "$ADT_REF" "$ADT_REPO_URL" "$ADT_DIR"
else
    command -v curl >/dev/null 2>&1 || die "Neither git nor curl found. Install one of them first (e.g. 'pkg install curl' on Termux / 'apt install curl' on Debian)."
    command -v tar  >/dev/null 2>&1 || die "tar not found — install it, or install git and re-run."
    command -v gzip >/dev/null 2>&1 || die "gzip not found (tar needs it) — install it, or install git and re-run."
    info "git not found — downloading tarball..."
    local_tmp="$(mktemp -d)"
    trap 'rm -rf "$local_tmp"' EXIT
    curl -fsSL "$ADT_TARBALL_URL" -o "$local_tmp/adt.tar.gz" \
        || die "Download failed: $ADT_TARBALL_URL"
    mkdir -p "$ADT_DIR"
    tar xzf "$local_tmp/adt.tar.gz" -C "$ADT_DIR" --strip-components=1 \
        || die "Extraction failed — remove $ADT_DIR and retry"
    info "Extracted to $ADT_DIR"
fi

[[ -f "$ADT_DIR/setup.sh" ]] || die "$ADT_DIR/setup.sh missing — checkout looks wrong"

# ---------------------------------------------------------------------------
# 2. Automatic full setup (device check first, verification before the guide)
# ---------------------------------------------------------------------------
info "Running automatic bootstrap..."
echo ""
bash "$ADT_DIR/setup.sh" bootstrap --auto

# ---------------------------------------------------------------------------
# 3. This shell still needs the new environment
# ---------------------------------------------------------------------------
echo ""
echo "  ============================================================"
echo "   Almost done — load the environment into THIS shell:"
echo ""
echo "       source ~/.bashrc"
echo ""
echo "   (piped installers cannot modify your current shell)"
echo "  ============================================================"
