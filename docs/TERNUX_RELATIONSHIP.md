# ADT and Ternux — ecosystem relationship

**Status:** documented · **Scope:** how two repositories relate on one device
**Canonical records:** [REAL_DEVICE_BUILD_VALIDATION.md](REAL_DEVICE_BUILD_VALIDATION.md) (ADT) and Ternux's
[`docs/BENCHMARKS.md`](https://github.com/soobujmiah/ternux/blob/main/docs/BENCHMARKS.md) (its own evidence)

> This page describes a relationship, not a merged product. Where the two projects have only been
> *observed* together, it says so, and it does not claim a combined capability that has never been tested.

## The shape of it

```text
                     Android device
                          │
            ┌─────────────┴─────────────┐
            │                           │
           ADT                        Ternux
            │                           │
   Android development            Linux ARM64 desktop
   build · sign · install         Debian · Xfce4 · GPU
   inspect · debug · validate     Mesa/Zink · Turnip on Adreno
            │                           │
            └─────────────┬─────────────┘
                          │
              Termux + PRoot Debian
              (the shared host — aarch64)
```

Both projects run on the same foundation: an ARM64 Android device running Termux with PRoot Debian,
no root, no PC. They are the two halves of what that device can be used for.

## What each project is

**ADT — the Android development layer** (this repository). Native aarch64 Android SDK build-tools and
platform-tools built from AOSP source, plus the host toolchain around them (JDK tool paths, CMake,
Ninja, NDK shims, Flutter/Dart support). It turns the device into an Android development workstation:
compile resources and AIDL, package, sign, install over ADB, inspect, debug and validate.

**Ternux — the Linux desktop layer** ([`soobujmiah/ternux`](https://github.com/soobujmiah/ternux),
site: [soobujmiah.github.io/ternux](https://soobujmiah.github.io/ternux/)). A no-root Debian ARM64
userspace with an Xfce4 desktop, Termux:X11 display and PulseAudio bridge, an explicit graphics route
(Mesa/Zink over Turnip on supported Adreno devices) and a documented compatibility fallback, installed
and operated by its own `ternux` CLI.

## Where they differ

| | ADT | Ternux |
|---|---|---|
| Purpose | Produce and deploy Android applications | Provide a Linux desktop environment |
| Delivers | SDK build-tools, platform-tools, signing and ADB workflow | Debian ARM64 userspace, Xfce4, display, audio, GPU route |
| Proof of success | A signed APK installs, selects `arm64-v8a`, loads JNI and runs | A desktop session starts and reports a real renderer |
| Failure mode | Wrong architecture or a missing tool stops the build | An absent or unsupported GPU route stops acceleration, not the desktop |
| Evidence record | `docs/REAL_DEVICE_BUILD_VALIDATION.md` | `docs/BENCHMARKS.md` |

Neither one is a dependency of the other. Each has its own installer, its own gates and its own
evidence; neither repository imports the other's code, data or build output.

## What is verified

- **ADT's pipeline is verified end-to-end on one physical device** — a Redmi Turbo 4 Pro (`25053RT47C`,
  Android 16 / API 36, Snapdragon 8s Gen 4) — and its canonical validation host is exactly the
  Termux + PRoot Debian environment this page describes. Full chain, from source to a running process,
  recorded in [REAL_DEVICE_BUILD_VALIDATION.md](REAL_DEVICE_BUILD_VALIDATION.md).
- **Ternux's desktop and graphics route are verified separately**, on the same device model, with its
  own captured renderer strings and benchmark output. Those numbers live in the Ternux repository;
  they are not restated here as if ADT had measured them.
- **The shared foundation is real**: both projects' documented host is Termux + PRoot Debian on
  aarch64 — the same environment, on the same kind of hardware.

## What remains experimental

- **Direct cross-project workflows are observed to coexist, not tested as a unit.** Running
  ADT-installed tools from inside a Ternux desktop session, or driving a build entirely from that
  desktop session, has been seen to work in this setup — but there is no recorded end-to-end test of
  that combined workflow, so it stays **not yet tested** rather than verified.
- **No shared orchestration exists.** There is no joint installer, no shared configuration, and no
  cross-repository automation between ADT and Ternux.
- **No GPU-assisted build path is claimed.** Ternux's graphics work targets rendering a desktop
  (Mesa/Zink/Turnip). ADT's builds are CPU work. The two have never been combined, so nothing in this
  ecosystem should be read as "GPU-accelerated Android builds".
- **No cross-device claim.** Every result above comes from one device family. Another host "should"
  behave the same; that is a expectation, not evidence.

## Evidence vocabulary

Used consistently across ADT, Ternux and the portfolio:

**Verified** — reproduced on real hardware with a recorded procedure ·
**Measured** — a numeric result from a complete, capturable run ·
**Observed** — something launched, built or was detected, without a captured measurement ·
**Experimental** — attempted, incomplete, or expected to change ·
**Not yet tested** — plausible, unexamined ·
**Not supported** — known not to work as described.

## Links

| | |
|---|---|
| ADT repository | [github.com/soobujmiah/adt](https://github.com/soobujmiah/adt) |
| ADT site | [soobujmiah.github.io/adt](https://soobujmiah.github.io/adt/) |
| Ternux repository | [github.com/soobujmiah/ternux](https://github.com/soobujmiah/ternux) |
| Ternux site | [soobujmiah.github.io/ternux](https://soobujmiah.github.io/ternux/) |
| Portfolio | [soobujmiah.github.io](https://soobujmiah.github.io/) |
