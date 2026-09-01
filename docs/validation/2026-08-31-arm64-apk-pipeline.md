# ARM64 APK pipeline validation — 2026-08-31 session

> **Status: HISTORICAL SESSION RECORD — superseded.** The items this record lists as
> "NOT YET VALIDATED" or "Next validation gate" were completed in the following session
> (signing via Debian `apksigner`, `zipalign`, physical-device install, JNI execution).
> Canonical, current evidence: [`../REAL_DEVICE_BUILD_VALIDATION.md`](../REAL_DEVICE_BUILD_VALIDATION.md).
> Reproducible procedure: [`../ANDROID_ARM64_NATIVE_BUILD_GUIDE.md`](../ANDROID_ARM64_NATIVE_BUILD_GUIDE.md).
> This file is preserved unchanged as the dated evidence trail for 2026-08-31.

## Purpose

Record the source/build/runtime evidence collected while validating the ADT goal: a usable Android build toolchain on Linux ARM64, with guided and eventually automated installation for other users.

This document records **observed test evidence**, not assumptions about upstream packages.

## Environment

- Host: Linux ARM64 (aarch64) inside my Termux + PRoot Debian workflow
- SDK root used by tests: `$HOME/android-sdk`
- Android platform: `android-35/android.jar`
- Build-tools under test: `35.0.2`
- Test workspace: `/tmp/real-device-test`

## Evidence collected

### 1. Native build-tools binary

`$HOME/android-sdk/build-tools/35.0.2/aapt2` was inspected with `file`.

Observed:

- ELF 64-bit LSB pie executable
- ARM aarch64
- GNU/Linux
- dynamically linked
- interpreter `/lib/ld-linux-aarch64.so.1`

The binary is therefore a **native Linux ARM64 executable**, not an x86_64 SDK binary.

`aapt2 version` executed successfully. The reported upstream version string was `Android Asset Packaging Tool (aapt) 2.19-SOONG BUILD NUMBER PLACEHOLDER`; this string must not be treated as proof of the build-tools release identity. The ELF architecture and successful execution are the relevant evidence here.

### 2. D8/R8

The SDK command-line-tools installation contains:

`$HOME/android-sdk/cmdline-tools/latest/lib/r8.jar`

Observed:

- `com/android/tools/r8/D8.class` exists in the JAR.
- `java -cp ... com.android.tools.r8.D8 --version` reported **D8 8.2.33**, build `b9c6a503fec02920ce801cc886c748552851b6f3`.
- A minimal `MainActivity.class` was successfully converted to `out/dex/classes.dex` using Android 35 `android.jar` as `--lib`.
- Resulting `classes.dex` was approximately 1.1 KiB.

Important boundary: D8/R8 is JVM-based here, so it does not require a native ARM64 `d8` executable.

### 3. AAPT2 resource compilation

A minimal `res/values/strings.xml` was compiled successfully:

```text
$ aapt2 compile --dir res -o out/compiled/resources.zip
```

Observed output artifact:

- `out/compiled/resources.zip`
- approximately 374 bytes

### 4. AAPT2 APK resource linking

A minimal APK was linked successfully using:

- `AndroidManifest.xml`
- `android-35/android.jar`
- compiled resource ZIP

Observed:

- `out/unsigned.apk` created successfully
- approximately 1.4 KiB
- recognized by `file` as an Android package (APK) containing `AndroidManifest.xml`

### 5. DEX insertion into APK

For this controlled test, the generated `classes.dex` was inserted into the linked APK with the system `zip` utility.

Before insertion the APK contained:

- `AndroidManifest.xml`
- `resources.arsc`

After insertion it contained:

- `AndroidManifest.xml`
- `resources.arsc`
- `classes.dex`

Result: `out/final-unsigned.apk`, approximately 3.2 KiB.

This is a **test fixture assembly technique**, not yet the recommended production packaging implementation for ADT.

### 6. APK signing: initial discovery

No `apksigner`, `apksigner.jar`, or signer JAR was found in the current SDK command-line-tools tree or the tested SDK build-tools directory. The R8 JAR also did not provide an APK signer entry point.

An attempt to download the guessed Google URL

`https://dl.google.com/android/repository/build-tools_r35.0.2-linux.zip`

returned HTTP 404. The failure is recorded as evidence that the guessed filename/URL must not be used by the installer.

### 7. APK signing: Debian ARM64 host solution

Debian Trixie package metadata showed:

- `apksigner` candidate: **35.0.2-1**
- source package: `android-platform-tools-apksig`
- architecture of the package: `all`
- dependency: `libapksig-java (>= 35.0.2-1)` plus a JRE

The package was installed successfully with `apt install -y apksigner`.

Observed:

- `command -v apksigner` -> `/usr/bin/apksigner`
- `/usr/bin/apksigner` is a symlink to Debian's Android SDK build-tools apksigner wrapper.
- `apksigner --version` reported `0.9`.

The important compatibility result is that the signer is **JVM/Java-based and works on the ARM64 Debian host**; it is not evidence that a native ARM64 ELF `apksigner` exists.

### 8. Signing and verification

A temporary RSA-2048 test keystore was generated with `keytool` for the controlled fixture:

- alias: `testkey`
- subject: `CN=ARM64 Test,O=ADT,C=BD`
- validity: 10,000 days

The test APK was signed successfully with Debian `apksigner 35.0.2-1`.

Verification succeeded with:

- v1 (JAR signing): **true**
- v2 (APK Signature Scheme v2): **true**
- v3 (APK Signature Scheme v3): **true**
- v3.1: false
- v4: false
- SourceStamp: false

The verifier reported one RSA-2048 signer and printed the certificate/public-key digests.

The test keystore is temporary test material and must **not** be committed to the repository or distributed as a project signing key.

## Current verified pipeline state

| Stage | Result | Evidence boundary |
|---|---|---|
| Native AAPT2 execution | PASS | Native Linux aarch64 ELF + successful execution |
| D8 class -> DEX | PASS | D8 8.2.33 JVM execution + `classes.dex` |
| AAPT2 resource compile | PASS | `resources.zip` created |
| AAPT2 APK link | PASS | `unsigned.apk` created and recognized as APK |
| DEX packaged in APK fixture | PASS | `classes.dex` present in APK archive |
| APK signing | PASS | Debian apksigner 35.0.2-1 |
| APK v1/v2/v3 verification | PASS | `apksigner verify --verbose --print-certs` |
| APK v3.1/v4 | NOT USED | Not required for this validation fixture |
| Physical-device install/launch | NOT YET VALIDATED | Next gate |

## Architecture conclusion

The current evidence supports a split model for ADT:

1. **Native ARM64 Linux binaries** are required for tools such as AAPT/AAPT2, AIDL, zipalign, dexdump, split-select, and platform-tools components that are native executables.
2. **JVM tools** such as D8/R8 and apksigner should be treated as Java-based host tools. ADT should locate or install compatible JVM artifacts rather than attempting to compile a fake native replacement.
3. ADT's installer must be evidence-driven and must not assume that every component is distributed by Google as an ARM64 Linux executable.
4. The final open-source installer should expose a guided path and an automated path, while clearly reporting whether each component is native ARM64, JVM-based, shimmed, or source-built.

## Next validation gate

The next test should validate the **signed APK on a real Android device** through the device-access path, beginning with ADB authorization/status and then install + launch + package/activity verification.

Do not mark the full ADT Android build pipeline as complete until real-device installation/launch evidence is recorded.
