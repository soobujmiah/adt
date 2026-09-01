# ADT — Android ARM64 Build Handoff

**Status:** CLOSED — build/install/runtime gate validated; documentation and registry follow-up complete (see the Follow-up sections below)
**Date:** 2026-09-01

## Mission

I'm continuing the ADT project from its already-validated Android ARM64 state, without restarting the same build/debug/test loop. My engineering objective here is to preserve the knowledge, keep the successful method reproducible, and keep the failed alternative documented as negative knowledge.

## Source of truth

Repository: `soobujmiah/adt`

ADT is the canonical owner of Android ARM64 development-tooling implementation, commands, version status, compatibility shims, artifacts, and validation evidence.

I don't move this work into LAI. Higher-level projects may consume ADT, but ADT owns this tooling knowledge.

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
- Linux environment: Termux + PRoot Debian on my physical phone
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

My project originally used:

```kotlin
ndkVersion = flutter.ndkVersion
```

That selected NDK 28.2.13676358 and failed during `stripDebugDebugSymbols` because Gradle tried to start:

```text
/home/sbj/android-sdk/ndk/28.2.13676358/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip
```

and got process-start error 2 (`No such file or directory`). The underlying issue is that my ARM64 PRoot environment can't execute the downloaded Linux-x86_64 NDK host executable.

I fixed this by pinning the project to:

```kotlin
ndkVersion = "27.2.12479018"
```

I created a backup before editing:

```text
app/build.gradle.kts.before-ndk-pin
```

NDK 27's `llvm-strip` was present as a symlink to `llvm-objcopy`, and the clean Flutter/Gradle build then succeeded. (I later fixed the NDK 28 trap too, rather than just working around it — see the Follow-up section near the bottom of this document.)

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

## Validation evidence I collected

1. I ran a native Linux linker sanity check with host GCC and it succeeded.
2. I identified the Android-target Clang path.
3. I found that Flutter/Gradle's automatic NDK selection failed at NDK 28's `llvm-strip`.
4. I explicitly pinned NDK 27.
5. I ran `./gradlew clean assembleDebug --no-daemon` and it succeeded.
6. I got an APK at the Flutter output path.
7. I ran `adb install -r`, which returned `Success` and exit code 0.
8. I confirmed the device ABI as `arm64-v8a`.
9. I confirmed the APK contained `lib/arm64-v8a/libflutter.so`.
10. I confirmed the installed package reported `primaryCpuAbi=arm64-v8a`.
11. I launched the app and observed process PID `24373`.
12. I manually pressed the `+` button 50 times with no reported malfunction.
13. After returning to Termux, I confirmed the app process remained alive.
14. I ran a final log scan and found no `FATAL EXCEPTION`, `AndroidRuntime`, `SIGSEGV`, `SIGABRT`, `ANR in`, or `am_anr` matches.

## Rules I'm holding myself to here

- Don't revert the NDK pin without new evidence.
- Don't retry NDK 28 merely to see the same failure again (this rule predates my later fix — see the Follow-up section; re-testing *to confirm a fix* is not the same thing).
- Don't interpret `emulator-5554` as a separate virtual emulator; it's the physical device's on-device ADB connection path.
- Don't delete the negative NDK 28 evidence.
- Don't mark NDK 28 as universally broken.
- Don't claim the full ADT installer is validated solely from this Flutter test.
- Don't invent SHAs, release tags, test results, or artifact checksums.
- Don't commit disposable keystores or production signing keys.
- Don't reopen the validation gate for the existing configuration without a material change.

## Documentation work

*(All of A–D below are done — see the Follow-up sections further down this document. E was left undone, as explicitly optional.)*

### A. Validation evidence

`docs/REAL_DEVICE_BUILD_VALIDATION.md` is updated with the final Flutter/Gradle evidence and is my primary evidence record.

### B. Lower-level native guide

`docs/ANDROID_ARM64_NATIVE_BUILD_GUIDE.md` remains my controlled JNI/native validation guide. I keep its distinction between native ARM64 ELF tools, JVM tools, and x86_64 host dependencies.

### C. Version registry

I update `versions.json` only with facts supported by the validation record. In particular, the NDK section preserves the distinction:

- `27.2.12479018`: validated shim/configuration for the ARM64 PRoot Flutter build path;
- `28.2.13676358`: now also fixed and validated — see the Follow-up section below (it was originally the negative case: installed/known shim metadata existed, but the direct bundled x86_64 host `llvm-strip` execution path failed in this environment).

I don't change unrelated version statuses without evidence.

### D. README / AGENTS

I keep the project overview and agent-facing instructions pointing to the final validation record and this handoff. I preserve the existing ADT project boundary and validation philosophy.

### E. Optional historical session record

If ADT's existing convention of dated files under `docs/validation/` calls for it, I can create a concise dated session record containing: the initial linker investigation, the clean GCC host test success, the NDK 28 failure, the NDK 27 pin, the successful clean build, the APK install, the ARM64 ABI evidence, the runtime and 50× interaction evidence, the final crash/ANR scan, and the closure decision. This would be historical evidence, not a new validation gate. I left it undone this round since it's explicitly optional.

## Evidence boundaries

### Strongly verified on the physical device

I have strongly verified the following, with real evidence, on the physical device:

- Android ARM64 ABI is `arm64-v8a`.
- The Flutter APK builds successfully with the NDK 27 pin.
- The APK installs successfully through ADB.
- Android selects the ARM64 primary ABI.
- The application launches.
- The process survives repeated manual interaction.
- A final crash/ANR scan is clean.
- Lower-level JNI ARM64 native execution, which I observed successfully in an earlier session.

### Still outside this closed gate

- A completely self-contained ADT C/C++ Android compiler independent of Termux.
- A fully automated ADT Flutter/Gradle orchestration layer.
- A self-contained ADT-distributed production APK signer.
- Production signing-key management.
- Validation on every other ARM64 Linux/Android host.

These are future engineering capabilities I haven't built yet — not reasons to reopen the completed test.

## Recommended next engineering phase

1. Preserve the current known-good project configuration. — **done**
2. Update the central registry accurately. — **done**
3. Ensure setup/doctor scripts encode the NDK 27 compatibility rule for the validated PRoot case. — **done**
4. Add a short capability check that detects an unusable x86_64 NDK host tool before Gradle wastes time. — **done** (see Follow-up below)
5. Add deterministic validation commands to ADT documentation/scripts. — **partially done** (doctor's own remediation commands, plus the `COMMANDS.md` troubleshooting row for this exact failure)
6. Optionally package the validated configuration as an explicit ADT profile, without breaking existing users. — **still open**, optional
7. Commit documentation changes. — **done**

## Follow-up: automated host-tool architecture detection (2026-09-01)

I've completed recommended-next-phase item 4 ("add a short capability check that detects an unusable x86_64 NDK host tool before Gradle wastes time").

I gave `setup.sh` a generic `detect_binary_arch()` primitive (resolves symlinks, distinguishes a delegating shim script from a real ELF, and classifies the ELF's machine type) plus `NDK_HOST_TOOL_BINS`, a small, extensible list of NDK host-tool entry points the Android Gradle Plugin is known to invoke by a fixed path regardless of `$PATH`. I changed `./setup.sh doctor` to check each of those paths' actual architecture instead of only checking `-x`, so an NDK version whose bundled host tool is a real x86_64 ELF is now reported explicitly, instead of silently passing as "OK" the way NDK 28's llvm-strip previously did. I used the same primitive to replace the duplicated `file -b`/case-statement arch-sniffing that already existed for build-tools and platform-tools in `doctor`/`status`/`setup-gradle`, so there's now one tested code path for this instead of several copies.

I re-verified this live on the same validated device/environment, non-destructively (`doctor`/`status` only, no installs/removals):

```text
:: NDK 27.2.12479018: llvm-strip OK (script)
:: ERROR:   NDK 28.2.13676358: llvm-strip is x86_64 — cannot execute under ARM64 PRoot
    Gradle/AGP call this exact path directly, bypassing $PATH.
    Path: /home/sbj/android-sdk/ndk/28.2.13676358/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip
    Fix:  ./setup.sh install-ndk 28.2.13676358   (recreates the ARM64-compatible shim)
```

NDK 27 and build-tools 35.0.2 (the validated configuration) still reported OK with no change in verdict — I didn't reopen or alter this closed validation gate. build-tools 36.0.0's x86_64 aapt2 was still reported (I'd already detected this before this change; it now shares the same underlying primitive as everything else instead of separate duplicated logic). I added unit tests for `detect_binary_arch()` covering native ELF, x86_64 ELF, script shims, symlinks (to both cases), and missing paths/targets, in `tests/test_arch_detection.sh`, run by a new `unit-tests` CI job.

## Follow-up: ARM64 build-tools 36.0.0 (2026-09-01)

My doctor follow-up above flagged build-tools 36.0.0 (Google's sdkmanager download for `platforms;android-36`) as an x86_64 trap. I confirmed via `git ls-remote --tags https://android.googlesource.com/platform/manifest` that there's no `platform-tools-36.0.0` AOSP tag to build a genuinely newer 36.0.0 from — the highest `platform-tools-X.Y.Z` tag is 35.0.2 — so, matching the existing 37.0.0 precedent, I built build-tools 36.0.0 from the same 35.0.2 AOSP source and registered it in `versions.json` as `verified`.

I built it via GitHub Actions `workflow_dispatch` on `build.yml` (run 33532721357, `ubuntu-24.04-arm`, AOSP tag `platform-tools-35.0.2`). CI's own ARM64 check passed, and I independently re-verified it on my device:

```text
$ file build-tools/36.0.0/{aapt,aapt2,aidl,zipalign,dexdump,split-select}
ELF 64-bit LSB pie executable, ARM aarch64 ... (all six)

$ aapt2 compile res/values/strings.xml -o .
-> values_strings.arsc.flat produced successfully
```

I installed it on my live device at `~/android-sdk/build-tools/36.0.0/` (I backed up Google's original x86_64 copy to `~/sdk-backups/build-tools-36.0.0.google-x86_64-bak` rather than deleting it). `./setup.sh doctor` now reports build-tools 36.0.0 as native ARM64.

I deliberately restored the global `~/.gradle/gradle.properties` `android.aapt2FromMavenOverride` to point at build-tools 35.0.2 afterward — the already-validated Flutter/Gradle gate above uses that exact override, and I didn't change it. build-tools 36.0.0 is available for use (a project can point its own override or `buildToolsVersion` at it) but isn't my device-wide default.

platform-tools 36.0.0 was a side effect of the same build, but I deliberately didn't register or ship it — adb/fastboot are already covered by verified platform-tools 35.0.2, and adding a second verified platform-tools version with no distinct purpose would just be duplication.

## Follow-up: NDK 28 llvm-strip trap fixed (2026-09-01)

My rules above say "don't retry NDK 28 merely to see the same failure again" — that predates this fix and no longer applies verbatim; see `versions.json`'s `ndk` → `28.2.13676358` entry, which says the same thing and explicitly notes it supersedes the original "do not use" note.

Root cause: I traced this back to NDK 28's bundled `llvm-strip` resolving (via a `llvm-strip -> llvm-objcopy` symlink, present in both NDK 27 and 28 as Google ships them) to a real x86_64 ELF `llvm-objcopy` that can't execute under my ARM64 PRoot. I'd already fixed NDK 27 the same way — its `llvm-objcopy` had been replaced with a shim script delegating to a real ARM64 tool — but I'd never done the same for NDK 28.

Fix: I ran `./setup.sh install-ndk 28.2.13676358` — ADT's own existing `create_ndk_shim` (unchanged, no new code needed) writes a shim script to the `llvm-strip` path; since it's a symlink to `llvm-objcopy`, this write lands on `llvm-objcopy` itself, exactly mirroring NDK 27's structure. The shim delegates to `llvm-strip` resolved from `$PATH` at shim-creation time (`/usr/lib/llvm-19/bin/llvm-strip`, Debian's real ARM64-native LLVM 19).

I verified this, not just assumed it:

```text
$ file .../ndk/28.2.13676358/.../bin/llvm-strip
symbolic link to llvm-objcopy          # unchanged structure
$ .../llvm-strip --version
llvm-strip, compatible with GNU strip
Debian LLVM version 19.1.7             # real execution, not just present

$ ./setup.sh doctor
NDK 28.2.13676358: llvm-strip OK (script)   # was ERROR before the fix
```

I re-tested this end to end by temporarily pinning the project to `ndkVersion = "28.2.13676358"`, then reverting back to the canonical `27.2.12479018` afterward (this doesn't change the canonical default):

```text
> Task :app:stripDebugDebugSymbols        # previously FAILED here
> Task :app:packageDebug
> Task :app:assembleDebug
BUILD SUCCESSFUL in 1m 40s

adb install -r app-debug.apk  -> Success
primaryCpuAbi=arm64-v8a
App launched, PID observed, logcat crash/ANR scan clean
```

I rebuilt the canonical NDK 27 configuration afterward to confirm I hadn't disturbed it — also `BUILD SUCCESSFUL`.

### Unrelated regression I found and fixed along the way

While re-testing, I hit a `compileDebugJavaWithJavac` failure: "Installed Build Tools revision 36.0.0 is corrupted." AGP auto-selects the highest installed build-tools version (36.0.0, which I'd added earlier) for that JVM-only dependency check, unrelated to `aapt2FromMavenOverride`. My earlier build-tools 36.0.0 install had replaced Google's whole directory with just the 6 ARM64 binaries, silently dropping other files Google ships there (`core-lambda-stubs.jar`, `apksigner`, `d8`, `lib/`, `lib64/`, etc.) that have nothing to do with architecture but are still required. I fixed it by merging the preserved backup (`~/sdk-backups/build-tools-36.0.0.google-x86_64-bak`) back in without overwriting the already-verified ARM64 binaries (`cp -rn`, no-clobber). `setup.sh`'s `install_local_artifact` function has this same whole-directory-replacement gap for any future component whose artifact tarball only carries a subset of files a real install needs — worth revisiting if it recurs, but out of scope to fix generically here.

## Completion condition

My documentation work here is complete now that the repository contains:

- a final real-device validation record;
- a reproducible ARM64 Flutter build recipe;
- the documented NDK 28 negative result, its limitation, and its later fix;
- a registry status consistent with observed evidence;
- agent-facing instructions linking to this handoff;
- no invented evidence.

I can leave this workstream **CLOSED** until a material toolchain/project/environment change requires a new validation cycle.
