# ADT Real-Device APK Build Validation

**Status:** VERIFIED OBSERVED on the current ARM64 Linux / PRoot Debian environment
**Validation workspace:** `/tmp/real-device-test`
**SDK root:** `/home/sbj/android-sdk`
**Build-tools target:** `35.0.2`
**Validation date:** 2026-08-31 / 2026-09-01 local session

## Purpose

This document records the actual end-to-end pieces tested while building an Android APK on the ARM64 Linux host. It is evidence, not a claim that the complete ADT installer is finished.

## Environment and tool sources

- Linux host is ARM64/aarch64 inside the user's PRoot Debian environment.
- Android platform API 35 is available at `$ANDROID_SDK/platforms/android-35/android.jar`.
- `r8.jar` is present in `cmdline-tools/latest/lib/r8.jar`.
- D8 is invoked directly with `com.android.tools.r8.D8`.
- APK signing is provided by Debian's `apksigner` package, not by a binary found in ADT's build-tools directory.

## Verified D8 path

The first D8 attempt failed only because the test command referenced the wrong class path:

`out/com/test/MainActivity.class`

The actual class was:

`out/com/test/arm64device/MainActivity.class`

After correcting the path, D8 succeeded and produced:

`out/dex/classes.dex` — approximately 1.1 KiB.

Observed D8 version:

`D8 8.2.33 (build b9c6a503fec02920ce801cc886c748552851b6f3 ...)`

This proves that the JVM-based D8 tool can run natively in the ARM64 Linux environment; it is not an ARM64 ELF binary and does not need a native rebuild.

## Verified AAPT2 path

ADT's locally built build-tools binary was tested directly:

`$ANDROID_SDK/build-tools/35.0.2/aapt2`

`file` reports it as:

`ELF 64-bit LSB pie executable, ARM aarch64, dynamically linked, interpreter /lib/ld-linux-aarch64.so.1`

AAPT2 version command succeeded.

A minimal `res/values/strings.xml` was compiled successfully to:

`out/compiled/resources.zip` — approximately 374 bytes.

AAPT2 then linked the manifest, Android 35 platform jar, and compiled resources successfully into an unsigned APK.

## Verified APK assembly

AAPT2 produced an unsigned APK containing:

- `AndroidManifest.xml`
- `resources.arsc`

The generated `classes.dex` was then inserted into the APK for this controlled validation fixture. The resulting APK contained all three expected entries and was recognized as an Android package.

**Important:** this manual ZIP injection is a validation fixture, not the final production packaging algorithm. Final ADT automation must use a deterministic Android-compatible packaging/signing sequence.

## APK signer discovery result

No `apksigner`, `apksigner.jar`, or signer jar was found under the current SDK/cmdline-tools tree during the search.

The attempted official Google download URL for a presumed Linux Build-Tools 35.0.2 archive returned HTTP 404, so that route was not treated as verified.

Debian Trixie provides:

- `apksigner` version/package `35.0.2-1`
- dependency `libapksig-java 35.0.2-1`
- installed command: `/usr/bin/apksigner`

The installed `/usr/bin/apksigner` is a symlink into Debian's Android SDK build-tools packaging.

## Verified signing and verification

A temporary test RSA-2048 keystore was generated for the fixture only:

`out/test.keystore`

The test APK was signed successfully as:

`out/final-signed.apk`

Observed verification:

- v1 JAR signing: **true**
- v2 APK Signature Scheme v2: **true**
- v3 APK Signature Scheme v3: **true**
- v3.1: false
- v4: false
- SourceStamp: false
- Number of signers: 1
- Key algorithm: RSA
- Key size: 2048 bits

The test certificate identity was `CN=ARM64 Test, O=ADT, C=BD`.

The keystore is a disposable test artifact and must never be committed to the repository.

## ARM64 native library validation — new evidence

### NDK discovery

The expected SDK-side NDK directory did not exist initially:

`/home/sbj/android-sdk/ndk` → **missing**

APT did not provide an `android-ndk` package in the current environment.

SDK Manager did list NDK side-by-side packages. NDK `27.2.12479018` was installed successfully with:

`$HOME/android-sdk/cmdline-tools/latest/bin/sdkmanager "ndk;27.2.12479018"`

The installed directory became:

`/home/sbj/android-sdk/ndk/27.2.12479018`

The NDK ARM64 target wrapper existed, but its host `clang-18` could not execute because the ARM64 PRoot environment does not provide the x86-64 ELF interpreter `/lib64/ld-linux-x86-64.so.2` required by the downloaded Linux-x86_64 NDK binaries.

This is an **environment incompatibility**, not evidence that Android NDK ARM64 target compilation is unsupported.

### Working native compiler path

The host environment already provides Termux Clang at:

`/data/data/com.termux/files/usr/bin/clang`

Observed version:

`clang version 21.1.8`

It accepts the Android target directly:

`--target=aarch64-linux-android21`

and was used successfully for the native test library. The resulting library was rebuilt with Android API 24 target settings and verified as:

- ELF 64-bit LSB shared object
- ARM aarch64
- Android target API 24
- `__android_log_print@LIBLOG` undefined import present as expected

The reproducible command is documented separately in `docs/ANDROID_ARM64_NATIVE_BUILD_GUIDE.md`.

### Fresh APK native packaging

The freshly rebuilt library was placed at:

`out/apk-root/lib/arm64-v8a/libarm64test.so`

The APK was assembled with `zip`, aligned using SDK Build Tools `35.0.2/zipalign`, then signed using `/usr/bin/apksigner`.

Final APK:

`out/fresh-native-signed.apk`

Observed APK contents included:

`lib/arm64-v8a/libarm64test.so`

APK verification succeeded with v1/v2/v3 signatures.

### Physical-device runtime validation

ADB reported the connected device as:

- model: `25053RT47C`
- Android release: `16`
- ABI: `arm64-v8a`

**ADB serial note.** `adb devices` reported the target with the serial `emulator-5554`. The serial label is an artifact of the on-device ADB connection path in use (a loopback-style connection to the phone's own adbd through a TCP port in adb's emulator serial range), not an emulator. The device properties read through that same connection — model `25053RT47C`, product `onyx`, Android `16`, ABI `arm64-v8a`, SM8735 (Snapdragon 8s Gen 4) hardware — identify the physical Redmi Turbo 4 Pro. This note is recorded so the serial label is not misread in either direction: neither as emulator evidence, nor silently glossed over when the physical-device claim is evaluated.

Installation succeeded:

`adb install -r out/fresh-native-signed.apk`

The app launched successfully. `adb logcat` recorded:

`ARM64NativeTest: ARM64 native code executed successfully`

A final validation run also confirmed:

- application process started successfully
- native log emitted successfully
- no `FATAL EXCEPTION`
- no `SIGSEGV`
- no `SIGABRT`
- no `UnsatisfiedLinkError`

Therefore the controlled ARM64 JNI path is **VERIFIED OBSERVED on the connected physical device**.

## Current evidence boundary

### VERIFIED

- Native Linux ARM64 `aapt2` executes successfully.
- AAPT2 resource compilation succeeds.
- AAPT2 resource linking succeeds.
- JVM-based D8 executes successfully and emits DEX.
- Debian-provided `apksigner` 35.0.2-1 executes successfully.
- A generated APK can be signed and verified with v1/v2/v3.
- Android SDK Manager can install NDK `27.2.12479018`.
- Downloaded Linux-x86_64 NDK clang cannot execute in the current ARM64 PRoot host because its x86-64 ELF interpreter is unavailable.
- Termux Clang 21.1.8 can target `aarch64-linux-android` and successfully build the JNI test library.
- The ARM64 native library can be packaged under `lib/arm64-v8a/`.
- `zipalign` 35.0.2 succeeds.
- The signed APK installs on the connected physical ARM64 device.
- The JNI native method executes successfully on the connected physical device.
- Native log output is observed and no native/JVM crash signature was detected in the final test.

### NOT YET VERIFIED in this sequence

- A fully self-contained ADT-distributed native compiler/toolchain independent of Termux.
- Whether every supported ARM64 Android host will expose the same Termux Clang path.
- Complete automated APK build orchestration through ADT's installer.
- A self-contained ADT-distributed apksigner solution independent of the host Debian package.
- Production-grade signing-key management.

## Next validation gate

1. Convert the proven native-library build and APK packaging sequence into ADT scripts.
2. Make tool-source detection explicit: native ARM64 tool, JVM tool, or external host dependency.
3. Add a fast capability probe so ADT does not spend long periods searching the entire filesystem.
4. Add a deterministic physical-device validation command using ADB.
5. Record exact versions and evidence in ADT's version/tool manifest only after direct verification.
6. Keep temporary test artifacts such as keystores and generated APKs outside the repository unless explicitly designated as fixtures.

## Reproducibility rule

Do not record a tool as "supported" merely because a package, jar, or upstream release exists. Record its exact source, execution model (native ARM64 ELF vs JVM vs external host binary), version, command, and observed result. Failed paths such as the x86_64 NDK clang execution failure must remain documented as failed attempts rather than silently replaced by assumptions.

## Project boundary

This work belongs to **ADT (`soobujmiah/adt`)**. It is Android Device Tooling engineering evidence and build/install guidance.

It must **not** be placed in LAI. LAI is a separate product/project. Reusable personal technical knowledge may be summarized in the private SKB knowledge base, while ADT remains the source of truth for ADT-specific tooling, commands, implementation, and validation evidence.
