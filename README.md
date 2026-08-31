# ADT — ARM64 Android Development Toolchain

I built ADT to provide a practical Android/Flutter development toolchain for Linux ARM64 environments, including Termux + PRoot Debian on ARM64 Android devices.

My goal is simple: I want an ARM64 machine to be able to prepare, build, sign, install, inspect, debug, and validate Android applications without depending on an x86_64-only Android Studio installation.

The CLI toolchain is the canonical path. GUI/X11 support is optional.

## What ADT Provides

ADT brings together the pieces I need for Android development on Linux ARM64:

- Git and source-management tooling
- GCC/Clang, CMake, Ninja and Make for native builds
- Java/JDK and JVM-based Android tools
- Flutter and Dart
- Android SDK platforms
- Android SDK Build-Tools
- Android Platform-Tools
- ARM64-native `aapt`, `aapt2`, `aidl`, `zipalign`, and related tools
- ARM64-native `adb`, `fastboot`, and related platform tools
- `apksigner`, `d8`, and R8 through their JVM execution paths
- NDK compatibility/shim support where a higher-level tool only needs selected LLVM utilities
- Reusable ARM64 binary artifacts for expensive builds
- Validation and diagnostic documentation

## My Operating Principle

I do not mark a tool as supported simply because it exists upstream.

For every important tool I distinguish between:

1. native Linux ARM64 binary;
2. Android/Termux binary;
3. JVM-based tool that is architecture-independent at the Java level;
4. source-built ARM64 binary;
5. compatibility shim/workaround;
6. installed but not yet validated.

A tool becomes part of my supported environment only after its actual execution path is understood and, where practical, tested in the target environment.

## Current Validated Environment

The current real-device validation was completed on:

- Device model: `25053RT47C`
- Product: `onyx`
- Android: `16`
- Android API level: `36`
- Device ABI: `arm64-v8a`
- SoC: Snapdragon 8s Gen 4 / SM8735
- GPU: Adreno 825
- Linux host architecture: `aarch64`
- Android SDK root: `/home/sbj/android-sdk`
- Build-Tools: `35.0.2`
- Android Platform: `android-35`
- NDK installed: `27.2.12479018`

The ARM64 native APK pipeline has been validated end-to-end:

`native source → ARM64 shared library → APK packaging → signing → ADB installation → Android ARM64 ABI selection → JNI loading → native execution → log output → process remains alive`

The successful validation is documented in `docs/validation/`.

## Tool Roles

### Git

I use Git to obtain AOSP source repositories, track ADT changes, and maintain the reproducible source configuration.

### GCC / Clang

I use the native compiler for Linux ARM64 builds. For Android-targeted native code inside the Termux environment, the working compiler path is Termux Clang with an Android target triple such as:

```bash
/data/data/com.termux/files/usr/bin/clang --target=aarch64-linux-android24 ...
```

### CMake

I use CMake to generate native build files for the ADT source tree and its support libraries.

### Ninja

I use Ninja as the primary fast build executor for CMake-generated builds.

### Make

I keep Make available for projects and dependencies that still use traditional Make-based build systems.

### Python 3

I use Python for ADT's source acquisition and build orchestration scripts, including `get_source.py` and `build.py`.

### Java / Javac

I use the JDK for Android's JVM-based development tools and for Gradle/Flutter Android builds.

### Flutter / Dart

I use Flutter and Dart for Flutter application development. ADT provides the native Android tooling required by the Flutter Android build pipeline.

### Android SDK Platform

I use the installed Android platform package for Android API headers, resources, and platform definitions required when compiling Android applications.

### Build-Tools

The build-tools layer contains the native tools required during APK construction and inspection.

| Tool | What I use it for |
|---|---|
| `aapt` | Legacy Android resource packaging and inspection |
| `aapt2` | Modern Android resource compilation and linking |
| `aidl` | Compiling Android Interface Definition Language files |
| `zipalign` | Aligning APK ZIP entries for Android packaging requirements |
| `dexdump` | Inspecting and disassembling DEX files |
| `split-select` | Selecting APK split variants |

### Platform-Tools

| Tool | What I use it for |
|---|---|
| `adb` | Connecting to devices, installing APKs, launching apps, collecting logs, shell access, and debugging workflows |
| `fastboot` | Communicating with Android bootloaders |
| `sqlite3` | SQLite database inspection and command-line operations |
| `etc1tool` | ETC1 texture conversion/inspection |
| `hprof-conv` | Converting HPROF heap-profile files |
| `mke2fs` | Creating ext4 filesystems |
| `e2fsdroid` | Preparing Android ext4 filesystem images |
| `make_f2fs` | Creating F2FS filesystem images |
| `make_f2fs_casefold` | Creating F2FS filesystems with casefold support |
| `sload_f2fs` | Loading data into F2FS filesystem images |

### Java-based Android Tools

| Tool | What I use it for |
|---|---|
| `apksigner` | Signing APKs and verifying APK signatures |
| `d8` | Converting Java bytecode to DEX |
| `R8` | Shrinking, optimizing, and obfuscating Android bytecode |
| `sdkmanager` | Managing Android SDK packages |

### Other Tool

`veridex` is used for DEX verification and related compatibility analysis where required.

## Native ARM64 Build Strategy

Google's Linux Android SDK distribution is traditionally centered on x86_64 host binaries. ADT therefore builds the native host tools from AOSP source for Linux ARM64.

The important distinction is that these binaries are **Linux ARM64/glibc** tools. They are not Android/Bionic binaries.

The ADT source adaptation therefore:

- uses the Linux host compiler;
- does not use the Android NDK toolchain file for the host tools;
- links against the Linux host runtime and libraries;
- removes or replaces Android-only code paths where required;
- adds Linux pthread linkage where required;
- supplies compatibility patches for AOSP components;
- keeps version-specific patches separate from reusable base patches.

## NDK / PRoot Reality

The Android NDK package may be installed successfully while its bundled x86_64 host compiler remains unusable inside an ARM64 PRoot runtime.

In the validated environment, the bundled NDK compiler expected:

```text
/lib64/ld-linux-x86-64.so.2
```

That host ELF loader is not provided by the current PRoot runtime. I therefore do not treat repeated attempts to execute the bundled x86_64 NDK compiler as the solution.

For Android-targeted native compilation in Termux, the working path is Termux Clang with an explicit Android target triple.

## Artifacts

ADT keeps expensive, already-validated ARM64 builds as versioned artifacts when doing so avoids unnecessary rebuilds.

Current artifact examples include:

- `artifacts/build-tools-35.0.2-linux-arm64.tar.gz`
- `artifacts/platform-tools-35.0.2-linux-arm64.tar.gz`

Checksums are maintained in `artifacts/SHA256SUMS`.

Source, build instructions, patches, and validation records remain the authoritative explanation of how an artifact was produced.

## Repository Structure

```text
ADT/
├── AGENTS.md
├── PLAN.md
├── README.md
├── CONTRIBUTING.md
├── repos.json
├── versions.json
├── get_source.py
├── build.py
├── setup.sh
├── CMakeLists.txt
├── build-tools/
├── platform-tools/
├── lib/
├── others/
├── patches/
├── docs/
│   ├── REAL_DEVICE_BUILD_VALIDATION.md
│   └── validation/
└── artifacts/
```

The AOSP source tree and local build output are deliberately excluded from normal Git tracking. I keep the repository focused on the reproducible build definition, patches, documentation, validation evidence, and selected reusable artifacts.

## Installation and Management

`setup.sh` provides an SDK-manager-like interface:

```bash
./setup.sh list-versions
./setup.sh status
./setup.sh doctor
./setup.sh install-build-tools 35.0.2
./setup.sh install-platform-tools 35.0.2
./setup.sh install-platforms android-35
./setup.sh install-cmd-tools
./setup.sh setup-gradle
```

When a verified artifact exists, installation should prefer the artifact rather than rebuilding from source.

Source builds remain available when I need to reproduce or extend a toolchain version:

```bash
./setup.sh build-build-tools 35.0.2
./setup.sh build-platform-tools 35.0.2
```

## Validation Philosophy

I validate the complete path, not just the presence of binaries.

For Android development, the strongest practical test is:

1. compile the native/application code;
2. package an APK;
3. align and sign it;
4. install it through ADB;
5. confirm Android selects the ARM64 native library;
6. launch the application;
7. inspect log output;
8. verify that the process remains alive without native or Java crashes.

This is the validation standard I use before calling the corresponding pipeline working.

## Project Boundary

ADT is the canonical project for this ARM64 Android development-tooling work.

This documentation does not belong in LAI, Self AI, SKB, or unrelated application repositories. Higher-level projects may consume ADT's resulting capabilities, but ADT remains responsible for the underlying ARM64 development tooling.

## Next Evolution

When I add another tool or version, I will follow the same sequence:

`identify → obtain official source → adapt for Linux ARM64 → build → validate → document → record version status → publish reusable artifact when worthwhile`

I will not mark a tool as verified without evidence.
