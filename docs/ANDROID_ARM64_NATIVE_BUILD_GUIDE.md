# Android ARM64 Native Build Guide

I use this guide when I need to prove that an Android ARM64 native library can be built, packaged, installed, and executed on a real device from my ARM64 Linux/PRoot environment.

This is a controlled validation guide. It is not a replacement for the normal Flutter/Gradle build pipeline.

## Scope

This guide covers:

- building an Android ARM64 JNI shared library;
- packaging it under `lib/arm64-v8a/`;
- aligning and signing a controlled APK fixture;
- installing it with ADB;
- launching it and checking native execution through logcat.

The canonical project for this work is ADT. Temporary source, APKs, keystores, and build output remain outside the repository unless explicitly designated as fixtures.

## Validated Environment

I performed the current validation on:

- Linux host architecture: `aarch64`
- Android device model: `25053RT47C`
- Android product: `onyx`
- Android release: `16`
- Device ABI: `arm64-v8a`
- SDK root: `/home/sbj/android-sdk`
- Build-tools: `35.0.2`
- NDK installed: `27.2.12479018`
- Termux Clang: `21.1.8`

## Important NDK Limitation

The installed Google NDK is useful for SDK-side files and metadata, but its downloaded Linux x86_64 host compiler cannot execute directly inside the current ARM64 PRoot runtime because the expected x86_64 ELF interpreter is unavailable:

```text
/lib64/ld-linux-x86-64.so.2
```

I therefore use the working Termux Clang for Android-targeted native compilation in this environment.

This is an execution-environment limitation. It is not treated as evidence that Android ARM64 target compilation itself is unsupported.

## 1. Build the Native Library

The working compiler is:

```bash
/data/data/com.termux/files/usr/bin/clang
```

For the validated test, I use an Android AArch64 target and API level 24:

```bash
/data/data/com.termux/files/usr/bin/clang \
  --target=aarch64-linux-android24 \
  -shared -fPIC \
  -I"$PREFIX/include" \
  -o out/apk-root/lib/arm64-v8a/libarm64test.so \
  native/test.c \
  -llog
```

The resulting library must be an AArch64 Android shared object.

Example inspection:

```bash
file out/apk-root/lib/arm64-v8a/libarm64test.so
```

I expect an ELF 64-bit AArch64 shared object and the Android logging symbol import used by the test library.

## 2. Prepare the APK Root

The controlled fixture uses this structure:

```text
out/apk-root/
├── AndroidManifest.xml
├── classes.dex
├── resources.arsc
└── lib/
    └── arm64-v8a/
        └── libarm64test.so
```

The important ABI rule is that the native library is placed under:

```text
lib/arm64-v8a/
```

Android can then select the ARM64 native library for an `arm64-v8a` device.

## 3. Package the APK

For the controlled native-library fixture, I package the prepared APK root with ZIP tooling:

```bash
cd out/apk-root
zip -r ../fresh-native-unsigned.apk .
cd ../..
```

This is a validation fixture, not a claim that ZIP injection is the production Android packaging algorithm.

## 4. Align the APK

Use the validated SDK Build-Tools 35.0.2 `zipalign`:

```bash
/home/sbj/android-sdk/build-tools/35.0.2/zipalign \
  -f 4 \
  out/fresh-native-unsigned.apk \
  out/fresh-native-aligned.apk
```

Verify alignment before signing:

```bash
/home/sbj/android-sdk/build-tools/35.0.2/zipalign -c -v 4 \
  out/fresh-native-aligned.apk
```

## 5. Sign the APK

The current validated signer is the host Debian `apksigner` package:

```bash
/usr/bin/apksigner sign \
  --ks out/test.keystore \
  --ks-key-alias test \
  --ks-pass pass:changeit \
  --key-pass pass:changeit \
  --out out/fresh-native-signed.apk \
  out/fresh-native-aligned.apk
```

The keystore used for this controlled test is disposable. I never commit test private keys or production signing keys to ADT.

Verify the signature:

```bash
/usr/bin/apksigner verify --verbose out/fresh-native-signed.apk
```

The validated fixture produced successful v1/v2/v3 verification.

## 6. Confirm the Device

```bash
adb devices -l
adb shell getprop ro.product.model
adb shell getprop ro.product.cpu.abi
adb shell getprop ro.build.version.release
```

The validated device reports:

```text
25053RT47C
arm64-v8a
16
```

## 7. Install

```bash
adb install -r out/fresh-native-signed.apk
```

Confirm that Android selected the ARM64 primary ABI for the installed package when applicable:

```bash
adb shell dumpsys package com.test.arm64device | grep -E 'primaryCpuAbi|nativeLibraryDir'
```

## 8. Launch and Validate Native Execution

Launch the controlled application using the activity defined by its test manifest. Then inspect logcat:

```bash
adb logcat -c
adb shell am start -n com.test.arm64device/.MainActivity
adb logcat -d | grep ARM64NativeTest
```

The validated native execution message is:

```text
ARM64NativeTest: ARM64 native code executed successfully
```

I also check that the process remains alive and that the log does not contain the failure signatures relevant to this test:

```text
FATAL EXCEPTION
SIGSEGV
SIGABRT
UnsatisfiedLinkError
```

## 9. Validation Result

A successful run proves this chain:

```text
Termux Clang
  → Android AArch64 shared library
  → lib/arm64-v8a/
  → APK packaging
  → zipalign
  → APK signing
  → ADB installation
  → Android ARM64 ABI selection
  → JNI loading
  → native execution
  → logcat evidence
  → process remains alive
```

This is the current physical-device validation gate for the controlled ARM64 native-library path.

## What This Guide Does Not Claim

This guide does not claim:

- that the Google Linux x86_64 NDK compiler can execute inside this ARM64 PRoot environment;
- that ADT provides a completely self-contained native Android C/C++ compiler;
- that the disposable fixture packaging sequence is the production APK packaging implementation;
- that production signing-key management is solved;
- that every ARM64 Linux host exposes the same Termux tool paths.

Those boundaries are intentional. I record observed behavior rather than promoting assumptions to support claims.

## Related ADT Evidence

The complete evidence record is maintained in:

`docs/REAL_DEVICE_BUILD_VALIDATION.md`

The toolchain and project architecture are documented in:

- `README.md`
- `AGENTS.md`
- `PLAN.md`
- `versions.json`
