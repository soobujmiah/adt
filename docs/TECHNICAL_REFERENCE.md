# ADT — Technical Reference

Deep technical detail for the ADT toolchain: tool roles, the native ARM64 build
strategy, the NDK/PRoot reality, manual installation steps, the `setup.sh`
command surface, profiles and repository structure.

For the quick picture — what ADT is, evidence, Ternux relationship, limits —
see the [README](../README.md). Everyday tool commands live in
[COMMANDS.md](../COMMANDS.md).

## Tool roles

### Git

Git obtains AOSP source repositories, tracks ADT changes, and maintains the reproducible source configuration.

### GCC / Clang

The native compiler for Linux ARM64 builds. For Android-targeted native code inside the Termux environment, the working compiler path is Termux Clang with an Android target triple such as:

```bash
/data/data/com.termux/files/usr/bin/clang --target=aarch64-linux-android24 ...
```

### CMake

Generates native build files for the ADT source tree and its support libraries.

### Ninja

The primary fast build executor for CMake-generated builds.

### Make

Kept available for projects and dependencies that still use traditional Make-based build systems.

### Python 3

Used for ADT's source acquisition and build orchestration scripts, including `get_source.py` and `build.py`.

### Java / Javac

The JDK powers Android's JVM-based development tools and Gradle/Flutter Android builds.

### Flutter / Dart

Flutter and Dart for Flutter application development. ADT provides the native Android tooling required by the Flutter Android build pipeline.

### Android SDK Platform

The installed Android platform package supplies Android API headers, resources, and platform definitions required when compiling Android applications.

### Build-Tools

| Tool | Role |
|---|---|
| `aapt` | Legacy Android resource packaging and inspection |
| `aapt2` | Modern Android resource compilation and linking |
| `aidl` | Compiling Android Interface Definition Language files |
| `zipalign` | Aligning APK ZIP entries for Android packaging requirements |
| `dexdump` | Inspecting and disassembling DEX files |
| `split-select` | Selecting APK split variants |

### Platform-Tools

| Tool | Role |
|---|---|
| `adb` | Connecting to devices, installing APKs, launching apps, collecting logs, shell access, debugging workflows |
| `fastboot` | Communicating with Android bootloaders |
| `sqlite3` | SQLite database inspection and command-line operations |
| `etc1tool` | ETC1 texture conversion/inspection |
| `hprof-conv` | Converting HPROF heap-profile files |
| `mke2fs` | Creating ext4 filesystems |
| `e2fsdroid` | Preparing Android ext4 filesystem images |
| `make_f2fs` | Creating F2FS filesystem images |
| `make_f2fs_casefold` | Creating F2FS filesystems with casefold support |
| `sload_f2fs` | Loading data into F2FS filesystem images |

### Java-based Android tools

| Tool | Role |
|---|---|
| `apksigner` | Signing APKs and verifying APK signatures |
| `d8` | Converting Java bytecode to DEX |
| `R8` | Shrinking, optimizing, and obfuscating Android bytecode |
| `sdkmanager` | Managing Android SDK packages |

### Other

`veridex` is used for DEX verification and related compatibility analysis where required.

## Support discipline

A tool is not marked supported simply because it exists upstream. Every important tool is classified by how it actually runs:

1. native Linux ARM64 binary;
2. Android/Termux binary;
3. JVM-based tool, architecture-independent at the Java level;
4. source-built ARM64 binary;
5. compatibility shim/workaround;
6. installed but not yet validated.

A tool becomes part of the supported environment only after its actual execution path is understood and, where practical, tested in the target environment.

## Native ARM64 build strategy

Google's Linux Android SDK distribution is centered on x86_64 host binaries. ADT therefore builds the native host tools from AOSP source for Linux ARM64.

The important distinction: these binaries are **Linux ARM64/glibc** tools. They are not Android/Bionic binaries.

The source adaptation therefore:

- uses the Linux host compiler;
- does not use the Android NDK toolchain file for the host tools;
- links against the Linux host runtime and libraries;
- removes or replaces Android-only code paths where required;
- adds Linux pthread linkage where required;
- supplies compatibility patches for AOSP components (`patches/base`, plus version-specific patches kept separate from reusable ones).

## NDK / PRoot reality

The Android NDK package may install successfully while its bundled x86_64 host compiler remains unusable inside an ARM64 PRoot runtime. In the validated environment, the bundled NDK compiler expected:

```text
/lib64/ld-linux-x86-64.so.2
```

That host ELF loader is not provided by the current PRoot runtime. Repeated attempts to execute the bundled x86_64 NDK compiler are therefore not the solution.

For Android-targeted native compilation in Termux, the working path is Termux Clang with an explicit Android target triple. For Gradle/Flutter paths, ADT installs NDK versions with `llvm-strip` shims delegating to a working ARM64 binary — see the `ndk` entries in `versions.json` (validated: `27.2.12479018`; validated option: `28.2.13676358`).

## Artifacts

ADT keeps expensive, already-validated ARM64 builds as versioned artifacts when doing so avoids unnecessary rebuilds:

- `artifacts/build-tools-35.0.2-linux-arm64.tar.gz`
- `artifacts/platform-tools-35.0.2-linux-arm64.tar.gz`
- `artifacts/build-tools-36.0.0-linux-arm64.tar.gz` (built from the same AOSP source as 35.0.2 — see `versions.json`; there is no separate platform-tools-36.0.0 AOSP tag)

Checksums are maintained in `artifacts/SHA256SUMS`. Source, build instructions, patches, and validation records remain the authoritative explanation of how an artifact was produced.

Installation order for a verified version: checked-in `artifacts/` tarball first (SHA256-verified), then a GitHub Release registered in `versions.json`, otherwise a source build. When a verified artifact exists, installation prefers the artifact over rebuilding from source.

## Installing on a new ARM64 device

A complete from-scratch install on any aarch64 Linux with glibc (Termux + PRoot Debian on an ARM64 phone is the validated target; Asahi/RPi/ARM64 servers follow the same path).

**One-liner (fully automatic):**

```bash
curl -fsSL https://raw.githubusercontent.com/soobujmiah/adt/main/install.sh | bash
source ~/.bashrc
```

It fetches the repo into `~/adt` (git clone when git exists, otherwise the GitHub tarball — only `curl` + `tar` + `gzip` are required) and runs the whole setup unattended. Re-running it updates an existing clone and skips what is already installed. Override the install location with `ADT_DIR=/some/path` before `bash`.

**Two full-setup modes** (from a clone):

- **Guided (default):** `./setup.sh` or `./setup.sh bootstrap` — checks the device first, then asks permission before each step (host packages, tools, network downloads, shell config).
- **Automatic:** `./setup.sh bootstrap --auto` — start-to-finish unattended: device check, host dependency install, artifact-preferred tools, shims, sdkmanager + platform, environment, verification, final guide. Zero prompts.

Both detect root/sudo automatically for system packages; with neither, the exact root command is printed and the run stops loudly instead of half-failing.

```bash
git clone --depth 1 https://github.com/soobujmiah/adt.git
cd adt
./setup.sh bootstrap --auto    # or guided: ./setup.sh
source ~/.bashrc
```

**Step by step** (the same operations bootstrap performs):

```bash
# Host prerequisites (Debian/Ubuntu names)
apt update && apt install -y git curl tar python3 \
    openjdk-21-jdk-headless cmake ninja-build llvm binutils

git clone --depth 1 https://github.com/soobujmiah/adt.git
cd adt

# build-tools + platform-tools 35.0.2 — fully offline from the checked-in,
# SHA256-verified artifacts (byte-identical to the binaries validated on device)
./setup.sh install-build-tools 35.0.2
./setup.sh install-platform-tools 35.0.2

# NDK + CMake shims (delegate to system llvm-strip/cmake)
./setup.sh install-ndk 27.2.12479018
./setup.sh install-cmake

# sdkmanager + Android platform (these two download from Google — network needed)
./setup.sh install-cmd-tools
./setup.sh install-platforms android-35

# Environment + final verification
export ANDROID_HOME=$HOME/android-sdk
export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"
./setup.sh doctor
```

For APK signing, install the JVM-based signer: `apt install apksigner` (works natively on ARM64; does not need a native rebuild).

What needs network vs what works offline:

- **Offline:** build-tools and platform-tools `35.0.2`, build-tools `36.0.0` (from `artifacts/`, SHA256-verified), NDK/CMake shims.
- **Network needed:** cmdline-tools (Google zip), `platforms;android-35`/`android-36`, and any other version — e.g. `35.0.1` builds from AOSP source via `build-build-tools <version>` (~2–4 GB source, ~15–30 min compile).

## setup.sh command surface

```bash
./setup.sh list-versions
./setup.sh status
./setup.sh doctor
./setup.sh install-build-tools 35.0.2
./setup.sh install-platform-tools 35.0.2
./setup.sh install-ndk 27.2.12479018       # NDK shim (validated version; see versions.json for others)
./setup.sh install-cmake                   # CMake shim (default 3.22.1)
./setup.sh install-platforms android-35
./setup.sh install-cmd-tools
./setup.sh install-profile validated       # one command for the exact validated bundle
./setup.sh setup-gradle
./setup.sh build-all                       # build + install everything from AOSP source
./setup.sh build-build-tools 35.0.2        # reproduce/extend from source
./setup.sh build-platform-tools 35.0.2
```

### Profiles

A profile is a named bundle of already-verified component versions, recorded in `versions.json`'s `profiles` key. Installing one doesn't build or verify anything new — it calls the same install commands with the bundle's versions.

The only profile right now is `validated`: build-tools `35.0.2` + NDK `27.2.12479018` + `platforms;android-36` — the exact configuration validated end-to-end on the real device (see [`REAL_DEVICE_BUILD_VALIDATION.md`](REAL_DEVICE_BUILD_VALIDATION.md)).

```bash
./setup.sh install-profile validated
```

## Validation philosophy

ADT validates the complete path, not just the presence of binaries. For Android development, the strongest practical test is:

1. compile the native/application code;
2. package an APK;
3. align and sign it;
4. install it through ADB;
5. confirm Android selects the ARM64 native library;
6. launch the application;
7. inspect log output;
8. verify that the process remains alive without native or Java crashes.

This is the standard used before calling the corresponding pipeline working.

## Repository structure

```text
ADT/
├── AI_ASSISTANT.md
├── PLAN.md
├── README.md
├── COMMANDS.md
├── CONTRIBUTING.md
├── repos.json
├── versions.json
├── get_source.py
├── build.py
├── setup.sh
├── CMakeLists.txt
├── .github/workflows/    # ci.yml (push/PR sanity build) · build.yml (tag → release) · pages.yml (site)
├── build-tools/
├── platform-tools/
├── lib/
├── others/
├── patches/
├── docs/
│   ├── REAL_DEVICE_BUILD_VALIDATION.md      # canonical evidence record
│   ├── ANDROID_ARM64_NATIVE_BUILD_GUIDE.md  # reproducible native build/install procedure
│   ├── TECHNICAL_REFERENCE.md               # this document
│   └── validation/                          # dated session records (historical)
└── artifacts/            # validated, SHA256-recorded ARM64 tarballs for offline install
```

The AOSP source tree and local build output are deliberately excluded from normal Git tracking. The repository stays focused on the reproducible build definition, patches, documentation, validation evidence, and selected reusable artifacts.
