# ADT — ARM64 Android Development Toolchain

A reproducible Android/Flutter development environment for ARM64 Linux running inside Termux + PRoot Debian, with optional X11 GUI support.

## Goal

Provide a local, agent-friendly toolchain so a coding agent can analyze, test, build, sign, install, and smoke-test Android/Flutter projects without depending on Android Studio.

Android Studio/X11 GUI is optional; the CLI toolchain is the canonical path.

## Target environment

- Android phone with ARM64 CPU
- Termux
- PRoot-Distro
- Debian ARM64
- Termux:X11 / X11-capable GUI environment

## Planned toolchain

- Git
- JDK
- Gradle
- Flutter + Dart
- Android SDK platforms
- Android SDK build-tools
- Android platform-tools / ADB
- AAPT/AAPT2
- AIDL
- apksigner
- zipalign
- d8/R8 where practical
- optional GUI tooling through X11

## Installation philosophy

Installation will be developed incrementally. Each stage must be tested on the target environment before becoming part of the final installer.

The repository will eventually provide:

```bash
./install.sh
./doctor.sh
```

The final installer must not assume x86_64 Linux binaries when an ARM64-native alternative is required.

## Development status

Initial repository created. Toolchain compatibility audit and environment bootstrap are the next steps.

## Important rule

Do not claim a tool is supported merely because it exists upstream. Record whether it is an ARM64 Linux binary, Android/Termux binary, JVM-based tool, source build, or compatibility workaround, and validate it in the actual Proot Debian environment.
