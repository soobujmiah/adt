# ADT — Android ARM64 Build Handoff

**Handoff status:** READY FOR AGENT DOCUMENTATION/REGISTRY COMPLETION
**Validation status:** BUILD/INSTALL/RUNTIME GATE CLOSED
**Date:** 2026-09-01

## Mission

Continue the ADT project from the already validated Android ARM64 state. Do **not** restart the same build/debug/test loop. The engineering objective now is to preserve the knowledge, make the successful method reproducible, and keep the failed alternative documented as negative knowledge.

## Source of truth

Repository: `soobujmiah/adt`

ADT is the canonical owner of Android ARM64 development-tooling implementation, commands, version status, compatibility shims, artifacts, and validation evidence.

Do not move this work into LAI. Higher-level projects may consume ADT, but ADT owns this tooling knowledge.

## Current validated state

### Device / host

- Physical Android device: model `25053RT47C`
- Product: `onyx`
- Android: 16
- API: 36
- Device ABI: `arm64-v8a`
- SoC: Snapdragon 8s Gen 4 / SM8735
- GPU: Adreno 825
- Linux host architecture: `aarch64`
- Linux environment: Termux + PRoot Debian on the physical phone
- SDK root: `/home/sbj/android-sdk`

### Android tooling

- Build-Tools: `35.0.2`
- Installed NDKs: `27.2.12479018`, `28.2.13676358`
- Validated NDK configuration: `27.2.12479018`
- Native host Clang observed: Debian LLVM 19.1.7
- Android target wrapper observed: `aarch64-linux-android24-clang`
- LLD observed: Debian LLD 19.1.7
- Gradle observed: `9.3.1`

### Flutter APK

Project:

```text
/home/sbj/android_arm64_build_test/android
```

Package:

```text
com.example.android_arm64_build_test
```

Version:

```text
1.0.0 / versionCode 1
minSdk 24
 targetSdk 36
```

APK:

```text
/home/sbj/android_arm64_build_test/build/app/outputs/flutter-apk/app-debug.apk
```

Observed size: `144M`.

## Proven solution

The project originally used:

```kotlin
ndkVersion = flutter.ndkVersion
```

That selected NDK 28.2.13676358 and failed during `stripDebugDebugSymbols` because Gradle attempted to start:

```text
/home/sbj/android-sdk/ndk/28.2.13676358/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip
```

with process-start error 2 (`No such file or directory`). The underlying issue is the inability of the ARM64 PRoot environment to execute the downloaded Linux-x86_64 NDK host executable.

The validated fix was to pin the project to:

```kotlin
ndkVersion = "27.2.12479018"
```

A backup was created before editing:

```text
app/build.gradle.kts.before-ndk-pin
```

NDK 27 `llvm-strip` was present as a symlink to `llvm-objcopy` and the clean Flutter/Gradle build succeeded.

## Canonical fast build recipe

```bash
cd ~/android_arm64_build_test/android
export PATH="$HOME/android-sdk/platform-tools:$HOME/.native-android-bin:/usr/lib/llvm-19/bin:/usr/bin:/bin"
./gradlew clean assembleDebug --no-daemon
APK="$HOME/android_arm64_build_test/build/app/outputs/flutter-apk/app-debug.apk"
adb install -r "$APK"
```

Prerequisite in `app/build.gradle.kts`:

```kotlin
ndkVersion = "27.2.12479018"
```

## Validation evidence already completed

1. Native Linux linker sanity check succeeded with host GCC.
2. Android-target Clang path was identified.
3. Flutter/Gradle build with automatic NDK selection failed at NDK 28 `llvm-strip`.
4. NDK 27 was explicitly pinned.
5. `./gradlew clean assembleDebug --no-daemon` succeeded.
6. APK was produced at the Flutter output path.
7. `adb install -r` returned `Success` and exit code 0.
8. Device ABI was confirmed as `arm64-v8a`.
9. APK contained `lib/arm64-v8a/libflutter.so`.
10. Installed package reported `primaryCpuAbi=arm64-v8a`.
11. App launched and process PID `24373` was observed.
12. User manually pressed the `+` button 50 times with no reported malfunction.
13. After returning to Termux, the app process remained alive.
14. Final log scan returned no `FATAL EXCEPTION`, `AndroidRuntime`, `SIGSEGV`, `SIGABRT`, `ANR in`, or `am_anr` matches.

## What the agent should NOT do

- Do not revert the NDK pin.
- Do not retry NDK 28 merely to see the same failure again.
- Do not interpret `emulator-5554` as a separate virtual emulator; this is the physical device's on-device ADB connection path.
- Do not delete the negative NDK 28 evidence.
- Do not mark NDK 28 as universally broken.
- Do not claim the full ADT installer is validated solely from this Flutter test.
- Do not invent SHAs, release tags, test results, or artifact checksums.
- Do not commit disposable keystores or production signing keys.
- Do not reopen the validation gate for the existing configuration.

## Documentation work to complete

### A. Validation evidence

`docs/REAL_DEVICE_BUILD_VALIDATION.md` has been updated with the final Flutter/Gradle evidence and is the primary evidence record.

### B. Lower-level native guide

`docs/ANDROID_ARM64_NATIVE_BUILD_GUIDE.md` remains the controlled JNI/native validation guide. Keep its distinction between native ARM64 ELF tools, JVM tools, and x86_64 host dependencies.

### C. Version registry

Update `versions.json` only with facts supported by the validation record. In particular, the NDK section should preserve the distinction:

- `27.2.12479018`: validated shim/configuration for ARM64 PRoot Flutter build path;
- `28.2.13676358`: installed/known shim metadata may exist, but the direct bundled x86_64 host `llvm-strip` execution path failed in this environment.

Do not change unrelated version statuses.

### D. README / AGENTS

Ensure the project overview and agent instructions point to the final validation record and handoff. Preserve the existing ADT project boundary and validation philosophy.

### E. Optional historical session record

If ADT's existing convention uses dated files under `docs/validation/`, create a concise dated session record containing:

- initial linker investigation;
- clean GCC host test success;
- NDK 28 failure;
- NDK 27 pin;
- successful clean build;
- APK install;
- ARM64 ABI evidence;
- runtime and 50× interaction evidence;
- final crash/ANR scan;
- closure decision.

This is historical evidence, not a new validation gate.

## Evidence boundaries

### Strongly verified on the physical device

- Android ARM64 ABI is `arm64-v8a`.
- Flutter APK builds successfully with NDK 27 pin.
- APK installs successfully through ADB.
- Android selects the ARM64 primary ABI.
- Application launches.
- Process survives repeated manual interaction.
- Final crash/ANR scan is clean.
- Lower-level JNI ARM64 native execution was previously observed successfully.

### Still outside this closed gate

- A completely self-contained ADT C/C++ Android compiler independent of Termux.
- A fully automated ADT Flutter/Gradle orchestration layer.
- A self-contained ADT-distributed production APK signer.
- Production signing-key management.
- Validation on every other ARM64 Linux/Android host.

These are future engineering capabilities, not reasons to reopen the completed test.

## Recommended next engineering phase

1. Preserve the current known-good project configuration.
2. Update the central registry accurately.
3. Ensure setup/doctor scripts encode the NDK 27 compatibility rule for the validated PRoot case.
4. Add a short capability check that detects an unusable x86_64 NDK host tool before Gradle wastes time.
5. Add deterministic validation commands to ADT documentation/scripts.
6. Optionally package the validated configuration as an explicit ADT profile, without breaking existing users.
7. Commit documentation changes.

## Handoff completion condition

The agent's documentation task is complete when the repository contains:

- final real-device validation record;
- reproducible ARM64 Flutter build recipe;
- documented NDK 28 negative result and limitation;
- registry status consistent with observed evidence;
- agent instructions linking to the handoff;
- no invented evidence.

At that point, this workstream can remain **CLOSED** until a material toolchain/project/environment change requires a new validation cycle.
