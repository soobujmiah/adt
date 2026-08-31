# ARM64 Linux Android Build Pipeline Validation

> **Status: HISTORICAL SESSION RECORD — superseded.** This record documents the pipeline
> *before* signing and device installation were completed ("has not yet completed
> signing/install/smoke-test validation"). Those gates were subsequently completed:
> canonical, current evidence is [`../REAL_DEVICE_BUILD_VALIDATION.md`](../REAL_DEVICE_BUILD_VALIDATION.md),
> and the reproducible procedure is [`../ANDROID_ARM64_NATIVE_BUILD_GUIDE.md`](../ANDROID_ARM64_NATIVE_BUILD_GUIDE.md).
> This file is preserved unchanged as the dated evidence trail.

**Date:** 2026-08-31 → 2026-09-01 (Dhaka local time)
**Environment:** Termux + PRoot Debian ARM64
**Project:** ADT (`soobujmiah/adt`)

## Purpose

Record the real target-environment validation performed while building an Android APK without relying on x86_64 Linux SDK binaries.

## What was verified

### 1. Java runtime

- OpenJDK 21.0.11 is available and runs natively in the ARM64 Debian environment.

### 2. D8 / R8

The Google command-line tools installation contains:

`$HOME/android-sdk/cmdline-tools/latest/lib/r8.jar`

The JAR contains `com/android/tools/r8/D8.class`.

Observed version:

`D8 8.2.33`

D8 successfully converted the test Java class into `out/dex/classes.dex` using Android API 35's `android.jar` as the library.

### 3. AAPT2

The ADT-installed build-tools directory contains:

`$HOME/android-sdk/build-tools/35.0.2/aapt2`

The binary was verified as:

- ELF 64-bit
- ARM aarch64
- GNU/Linux
- dynamically linked

AAPT2 successfully:

1. compiled `res/values/strings.xml` into `resources.zip`;
2. linked the Android manifest, API 35 `android.jar`, and resources into an unsigned APK.

Reported AAPT2 version string:

`Android Asset Packaging Tool (aapt) 2.19-SOONG BUILD NUMBER PLACEHOLDER`

The placeholder version string is recorded as observed output; it is **not** evidence that the binary is Google's official 35.0.2 binary.

### 4. APK assembly

The test APK was assembled successfully:

`/tmp/real-device-test/out/final-unsigned.apk`

Final archive contents:

- `AndroidManifest.xml`
- `resources.arsc`
- `classes.dex`

The resulting file was recognized by `file` as an Android package (APK).

## Important discovery: Google Build-Tools 35.0.2 retrieval mismatch

`$HOME/android-sdk/cmdline-tools/latest/bin/sdkmanager --list` advertises `build-tools;35.0.2`, but an isolated SDK root download attempt:

`SDKMANAGER --sdk_root=/tmp/google-sdk-bt "build-tools;35.0.2"`

returned:

`Warning: Failed to find package 'build-tools;35.0.2'`

A direct guessed URL for `build-tools_r35.0.2-linux.zip` returned HTTP 404. A search of the downloaded `repository2-3.xml` also did not expose a matching package entry in the checked output.

Therefore, do **not** document Google 35.0.2 as successfully downloaded from Google's Linux package repository. The installed `35.0.2` directory is the ADT/source-built toolchain currently under test.

## Java APK signing status

`apksigner` is currently absent from the SDK build-tools directory and is not available on `PATH`.

The command-line tools installation does contain `r8.jar`, but searching the SDK JARs did not locate an `apksigner` implementation.

This means the current pipeline is at:

**Java compile → D8 → AAPT2 compile → AAPT2 link → APK assembly**

and has **not yet completed signing/install/smoke-test validation**.

## Current known-good chain

```text
Java source
   ↓
javac (ARM64 JVM)
   ↓
MainActivity.class
   ↓
D8 8.2.33 (r8.jar / JVM)
   ↓
classes.dex
   ↓
AAPT2 (native ARM64 Linux)
   ↓
resources.zip + AndroidManifest.xml
   ↓
unsigned APK
   ↓
classes.dex injected
   ↓
final unsigned APK
```

## Next validation gate

Do **not** claim the full Android build pipeline is complete yet.

Next gate:

1. establish a reproducible Java `apksigner` path from an appropriate Android/AOSP source or verified artifact;
2. generate a test keystore/signature;
3. sign `final-unsigned.apk`;
4. run `zipalign` before signing where required by the final pipeline;
5. verify the signed APK;
6. use the already-established ADB/device path to install it on the real ARM64 Android device;
7. launch the test activity and verify the expected text:
   `ARM64 REAL DEVICE TEST OK`.

Only after those checks pass should the ADT documentation mark the complete build → sign → install → launch path as validated.

## Repository/source boundary

The upstream/reference repositories used for research are **not** the destination for ADT's project history. Findings, adaptations, validation results, and documentation belong in the user's own ADT repository (`soobujmiah/adt`). Upstream sources remain references unless explicitly incorporated under their applicable licenses.
