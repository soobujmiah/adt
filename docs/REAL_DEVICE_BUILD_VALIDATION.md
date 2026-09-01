# ADT — Real-Device Android ARM64 Build Validation

**Status:** VERIFIED / CLOSED for the validated project state
**Validation date:** 2026-09-01
**Project:** `/home/sbj/android_arm64_build_test/android`
**SDK:** `/home/sbj/android-sdk`

## Executive result

I built and validated the Flutter/Gradle Android ARM64 APK pipeline end to end on my real physical ARM64 Android device, from Termux + PRoot Debian.

Final build:

```text
./gradlew clean assembleDebug --no-daemon
BUILD SUCCESSFUL in 1m 21s
60 actionable tasks: 54 executed, 6 up-to-date
BUILD_EXIT=0
```

APK:

```text
/home/sbj/android_arm64_build_test/build/app/outputs/flutter-apk/app-debug.apk
```

Observed size: **144M**.

Installation:

```text
adb install -r "$APK"
Success
INSTALL_EXIT=0
```

Package:

```text
com.example.android_arm64_build_test
```

Final evidence:

```text
Device ABI: arm64-v8a
APK primaryCpuAbi: arm64-v8a
Runtime PID: 24373
Crash/ANR scan: no matching output
```

I manually exercised the app with 50 presses of the `+` button and observed normal operation. The app remained alive after I returned to Termux.

**This validation gate is CLOSED. Do not repeat the same test loop unless a material configuration/environment change occurs.**

## Actual device topology

The ADB target is my **real physical Android device**, not a desktop emulator:

```text
Physical Android phone
└── Termux
    └── PRoot Debian / Linux ARM64 userland
        ├── ADT / Android SDK tools
        ├── Flutter / Gradle
        └── ADB
            └── physical Android host/device
```

ADB reported the serial `emulator-5554`, but that serial is an artifact of the on-device ADB connection path. Device properties identify my physical device as model `25053RT47C`, product `onyx`, Android 16, ABI `arm64-v8a`.

## Environment

- Linux architecture: `aarch64`
- Android: 16 / API 36
- ABI: `arm64-v8a`
- Hardware: Snapdragon 8s Gen 4 / SM8735
- GPU: Adreno 825
- SDK root: `/home/sbj/android-sdk`
- Build-Tools: `35.0.2`
- Installed NDKs: `27.2.12479018`, `28.2.13676358`
- Gradle observed: `9.3.1`

## Failure I discovered

My project initially used:

```kotlin
ndkVersion = flutter.ndkVersion
```

Flutter/Gradle selected NDK `28.2.13676358`. The build failed at:

```text
:app:stripDebugDebugSymbols FAILED
```

with:

```text
Cannot run program "/home/sbj/android-sdk/ndk/28.2.13676358/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip"
Exec failed, error: 2 (No such file or directory)
```

This is a **host-tool execution limitation**: my ARM64 PRoot environment can't directly start the downloaded Linux-x86_64 NDK host executable. It isn't evidence that Android ARM64 target compilation or NDK 28 is universally broken. (I later fixed this specific trap for NDK 28 too — see `docs/ANDROID_ARM64_BUILD_HANDOFF.md`.)

## Resolution

I pinned the project to the already-validated NDK:

```kotlin
ndkVersion = "27.2.12479018"
```

I created a backup before the edit:

```text
app/build.gradle.kts.before-ndk-pin
```

NDK 27's `llvm-strip` was present and resolved as:

```text
llvm-strip: symbolic link to llvm-objcopy
```

I used the validated native-tool PATH:

```bash
export PATH="$HOME/android-sdk/platform-tools:$HOME/.native-android-bin:/usr/lib/llvm-19/bin:/usr/bin:/bin"
```

and ran:

```bash
./gradlew clean assembleDebug --no-daemon
```

which produced the successful APK.

## Canonical fast build method for this environment

```bash
cd ~/android_arm64_build_test/android
export PATH="$HOME/android-sdk/platform-tools:$HOME/.native-android-bin:/usr/lib/llvm-19/bin:/usr/bin:/bin"
./gradlew clean assembleDebug --no-daemon
APK="$HOME/android_arm64_build_test/build/app/outputs/flutter-apk/app-debug.apk"
adb install -r "$APK"
```

Prerequisite project configuration:

```kotlin
ndkVersion = "27.2.12479018"
```

This is the **currently validated Flutter/Gradle ARM64 APK path** for my Termux + PRoot environment.

## APK ABI evidence

`apkanalyzer` showed:

```text
/lib/arm64-v8a/libflutter.so
/lib/arm64-v8a/libVkLayer_khronos_validation.so
/lib/armeabi-v7a/libflutter.so
/lib/x86_64/libflutter.so
```

My physical device reported `arm64-v8a`, and the installed package reported:

```text
primaryCpuAbi=arm64-v8a
secondaryCpuAbi=null
```

So Android selected the ARM64 native ABI on my physical device.

## Runtime evidence

Launch:

```bash
adb shell am force-stop com.example.android_arm64_build_test
adb shell monkey -p com.example.android_arm64_build_test 1
```

Process remained alive:

```text
24373
```

Activity:

```text
com.example.android_arm64_build_test/.MainActivity
```

After I repeatedly interacted with the app and returned to Termux, the process remained alive. The activity being paused/backgrounded is normal Android lifecycle behavior.

I ran a final log scan checking for:

```text
FATAL EXCEPTION
AndroidRuntime
SIGSEGV
SIGABRT
ANR in
am_anr
```

No matching output appeared.

## Earlier lower-level native evidence

I had also previously validated the controlled JNI path on the same physical device:

```text
Termux Clang
 → Android AArch64 shared library
 → lib/arm64-v8a/
 → APK packaging
 → zipalign
 → signing
 → ADB installation
 → JNI loading
 → native execution
 → logcat
```

Observed native message:

```text
ARM64NativeTest: ARM64 native code executed successfully
```

That gave me lower-level native execution evidence; this record adds the higher-level Flutter/Gradle APK validation I completed here.

## Non-blocking warnings

The successful Gradle build emitted deprecation/experimental warnings concerning built-in Kotlin settings, the old Android DSL, `aapt2FromMavenOverride`, deprecated Kotlin plugin usage under AGP 9.0, and an inconsistent `platform-tools-2` SDK location. None of them prevented the validated build/install/runtime flow.

These are future cleanup items and **must not reopen this completed validation gate**.

## Validation matrix

| Gate | Result |
|---|---|
| Physical device identified | PASS |
| Device ABI `arm64-v8a` | PASS |
| Build-Tools 35.0.2 | PASS |
| NDK 27.2.12479018 | PASS |
| Flutter/Gradle clean build | PASS |
| APK generated | PASS |
| APK installed | PASS |
| Installed primary ABI `arm64-v8a` | PASS |
| App launch | PASS |
| 50× manual `+` interaction | PASS |
| Process survival | PASS |
| Crash check | PASS |
| ANR check | PASS |

## Closure rule

**ANDROID ARM64 DEVICE BUILD VALIDATION: CLOSED.**

I'll reopen this validation only after a material change to the project, Gradle/AGP configuration, NDK version, SDK tools, Flutter toolchain, Android OS, or execution environment.

See `docs/ANDROID_ARM64_BUILD_HANDOFF.md` for my engineering handoff notes and the follow-up work (NDK 28 fix, build-tools 36.0.0) completed after this gate closed.
