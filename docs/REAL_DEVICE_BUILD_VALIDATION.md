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

## Current evidence boundary

### VERIFIED

- Native Linux ARM64 `aapt2` executes successfully.
- AAPT2 resource compilation succeeds.
- AAPT2 resource linking succeeds.
- JVM-based D8 executes successfully and emits DEX.
- Debian-provided `apksigner` 35.0.2-1 executes successfully.
- A generated APK can be signed and verified with v1/v2/v3.

### NOT YET VERIFIED in this sequence

- `zipalign` before signing.
- Installation of this fixture APK with the native ADT/ADB path on the physical device.
- Launch and runtime behavior of the fixture APK on the physical device.
- Complete automated APK build orchestration through ADT's installer.
- A self-contained ADT-distributed apksigner solution independent of the host Debian package.

## Next validation gate

1. Verify native `zipalign` on the generated unsigned APK **before signing**.
2. Sign the aligned APK with the verified apksigner path.
3. Verify the final signed APK again.
4. Verify the native ARM64 `adb` from ADT and establish the physical-device connection.
5. Install the signed/aligned fixture APK and confirm launch.
6. Convert the proven sequence into ADT's automated installer/build workflow.
7. Update `versions.json`, installer logic, and documentation only after each component has direct evidence.

## Reproducibility rule

Do not record a tool as "supported" merely because a package, jar, or upstream release exists. Record its exact source, execution model (native ARM64 ELF vs JVM), version, command, and observed result. Failed paths such as the 404 archive lookup must remain documented as failed attempts rather than silently replaced by assumptions.
