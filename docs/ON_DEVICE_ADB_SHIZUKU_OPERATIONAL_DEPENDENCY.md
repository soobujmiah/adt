# ADT × Custom Shizuku — Operational Dependency Documentation

**Date:** 2026-09-12  
**Last Updated:** 2026-09-13 (Phase 5 source comparison + Phase 6 live monitoring)  
**Status:** Documented (forensic audit concluded, read-only, no state modifications)  
**Device:** Redmi Turbo 4 Pro (25053RT47C, product:onyx), Android 16 / API 36  

---

## 1. Purpose

This document records the operational dependency between the ADT ADB transport path and the custom Shizuku fork running on the development device. It is **not** a claim that ADT code depends on Shizuku — it is a record of a transport-state dependency specific to the current on-device architecture.

## 2. Scope

This applies only to the **current on-device ADT ADB topology** used during development on the Redmi Turbo 4 Pro. It does not affect ADT's portability, build process, or behavior on other devices or emulators.

## 3. Direct vs Indirect Dependency Distinction

### Code Dependency — NONE

```
ADT ADB ──────X──────> Shizuku
```

The ADT native ARM64 ADB binary (`/home/sbj/android-sdk/platform-tools/adb`, 8,686,536 bytes, ARM64 ELF) contains zero Shizuku symbols, zero Shizuku strings, and zero Shizuku references. The ADT repository contains no Shizuku integration code. Shizuku does not ship as a library, dependency, or runtime hook in ADT.

### Operational Dependency — CORRECTED (Phases 5 & 6)

```
ADT ADB
   ↓  (USB or TCP)
On-device ADB relay (:5037) [or direct wireless]
   ↓  (TCP 127.0.0.1 or WiFi)
Android adbd (:5555)
   ▲
   │ Port VALUE persists independently of Shizuku
   │ Bridge PROVIDED BY shizuku_server (part of fork)
```

The custom Shizuku fork provides two things:
1. **`shizuku_server` process** — the ADB protocol bridge that enables the `fork-server` relay to communicate with `adbd` on port 5555
2. **Crash resilience** — `WatchdogService` auto-restarts both the app and server if killed

**Critical finding (Phase 6):** `service.adb.tcp.port=5555` **persists indefinitely** even after both Shizuku processes are killed. The port value is stored in Android's property system and does not require an active process to maintain it. However, without `shizuku_server`, there is no ADB protocol bridge — the port exists but cannot be used for ADB communication.

**Key distinction:** Shizuku is an infrastructure dependency providing the **bridge process**, not the **port state**. ADT would function identically on any device where a valid ADB transport path exists.

## 4. Current On-Device ADB Topology

```
┌─────────────────────────────────────────────────────────────────┐
│  Host: ADT native ARM64 adb                                     │
│  Path: /home/sbj/android-sdk/platform-tools/adb                 │
│  (vanilla AOSP binary — no Shizuku code)                        │
└────────────────────┬────────────────────────────────────────────┘
                     │ USB transport
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│  On-device ADB relay (PID 18833, user u0_a490)                  │
│  Command: adb -L tcp:5037 fork-server server --reply-fd 4       │
│  Listener: 127.0.0.1:5037                                       │
│  Location: Running inside PRoot Debian container (PID 18801)    │
│  Startup: Manual — user ran `adb start-server` in PRoot shell   │
│  (NOT auto-started by any script, init service, or Shizuku)     │
└────────────────────┬────────────────────────────────────────────┘
                     │ TCP ESTABLISHED: 127.0.0.1:39239 → 127.0.0.1:5555
                     │ (socket inode 163122)
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│  Android adbd (PID 17484, user shell)                           │
│  Listening on: *:5555                                           │
│  Property: service.adb.tcp.port = 5555                          │
│  Note: wireless_debugging_enabled setting = 0 (anomalous)       │
│        Port is active despite flag — indicates programmatic     │
│        setprop rather than standard Wireless Debugging UI toggle │
└─────────────────────────────────────────────────────────────────┘

         ▲
         │ Transport state sustained by:
         │
┌─────────────────────────────────────────────────────────────────┐
│  Custom Shizuku Fork                                            │
│  Version: v13.6.0.r1318-thedjchi                                │
│  APK: /storage/self/primary/Apps/Shizuku/shizuku-v13.6.0...apk  │
│  GitHub: https://github.com/thedjchi/Shizuku                    │
│                                                                 │
│  Key components:                                                │
│  - BootCompleteReceiver (handles BOOT_COMPLETED)                │
│  - WatchdogService (foreground, auto-restart)                   │
│  - AdbStartWorker (WorkManager worker)                          │
│  - AdbPairingService / AdbPairingClient                         │
│  - toggle_adb_wireless                                          │
│  - start_service_via_wadb                                       │
│  - persist.adb.tcp.port handling                                │
└─────────────────────────────────────────────────────────────────┘
```

**Process tree:**
```
com.termux (PID 14863)
  └── zsh (PID 18175)
        └── proot (PID 18801)
              └── bash (PID 18807)
                    └── adb fork-server (PID 18833) ← manual start
```

## 5. Role of the Custom Shizuku Fork (Corrected — Phase 5 Source Comparison)

**Correction from DEX-string analysis:** Most strings previously identified as "custom fork signatures" are actually present in upstream `RikkaApps/Shizuku`. The true customizations are architectural, not feature-additional:

| String | Phase 3 Claim | Phase 5 Correction |
|--------|--------------|-------------------|
| `AdbStartWorker` | Custom to fork | **UPSTREAM** — exists in RikkaApps/Shizuku |
| `toggle_adb_wireless` | Custom to fork | **UPSTREAM** — diagnostic log string |
| `start_service_via_wadb` | Custom to fork | **UPSTREAM** — method name in equivalent code |
| `persist.adb.tcp.port` | Custom to fork | **UPSTREAM** — EnvironmentUtils.getAdbTcpPort() |
| `service.adb.tcp.port` | Custom to fork | **UPSTREAM** — read by EnvironmentUtils |
| `adb tcpip 5555` | Custom to fork | **UPSTREAM** — default string resource |
| `Starting with wireless adb...` | Custom to fork | **UPSTREAM** — AdbStarter.startAdb() message |

### Truly Custom Fork Additions

| Component | Purpose | Upstream Equivalent |
|-----------|---------|-------------------|
| `BootCompleteReceiver.kt` rewrite | 9-line delegator → `ShizukuReceiverStarter` + `WatchdogService` | ~90 lines inline `adbStart()` |
| `WatchdogService.kt` | Foreground service; auto-restarts on crash (`START_STICKY`) | **Does not exist** |
| `ShizukuReceiverStarter.kt` | Central dispatch: launch-mode routing, permission gating | Inline receiver logic |
| Authenticated broadcast receivers | Token-authenticated remote start/stop | **Does not exist** |
| Notification receivers | WorkManager retry via notification actions | **Does not exist** |
| Hardcoded package name | `"moe.shizuku.privileged.api"` | Dynamic derivation from CLASSPATH |

**What the fork actually does:**
1. On boot: runs `ShizukuReceiverStarter` which enqueues `AdbStartWorker` (WorkManager job)
2. `AdbStartWorker` sets `Settings.Global.ADB_ENABLED=1` and `Settings.Global.adb_wifi_enabled=1`
3. `WatchdogService` monitors for crashes and re-triggers restart automatically
4. `shizuku_server` process provides the ADB protocol bridge on port 5555

**What the fork does NOT do:**
- Does NOT directly set `service.adb.tcp.port=5555` (no code path found)
- Does NOT need to stay running to maintain the port value mid-session (Phase 6 proved this)
- **Does need to be present at boot** — full reboot without Shizuku leaves adbd not listening on :5555; property value does not survive cold restart (verified 2026-09-13)

## 6. Evidence Summary

### PROVEN

| # | Finding | Evidence |
|---|---------|----------|
| P6-1 | ADT ADB binary has no direct Shizuku code dependency (zero symbols, zero strings in 8.6MB binary) | `strings` / `readelf` analysis, repository grep |
| P6-2 | The on-device ADB relay requires TCP :5555 for its transport path (socket topology verified) | `/proc/net/tcp`, `ss -tnp`, process fd inspection |
| P6-3 | Android `adbd` provides the :5555 endpoint (confirmed via socket table) | `ps -A` + inode correlation |
| P6-4 | Port value `service.adb.tcp.port=5555` **persists after Shizuku kill** | Live monitor: 10+ min observation post-kill, value unchanged |
| P6-5 | `shizuku_server` auto-restarts after force-stop (WatchdogService confirmed working) | Logcat: PID changed from 26827→new process, service recovered |
| P6-6 | No code path in fork or upstream sets `service.adb.tcp.port` directly | Exhaustive source grep of all `.kt` and `.java` files |
| P6-7 | `wireless_debugging_enabled` (secure) = null, `adb_wifi_enabled` (global) = 0 | Settings database query |
| P6-8 | USB path is fragile (relay depends on manual start), wireless path is robust | Host ADB works via `192.168.0.102:5555` after USB detached |

### CORRECTED FROM PRIOR PHASES

| Prior Claim | Correction |
|-------------|------------|
| `AdbStartWorker` was a custom fork addition | **UPSTREAM** — exists identically in RikkaApps/Shizuku |
| `toggle_adb_wireless` string was custom | **UPSTREAM** — diagnostic log string |
| `start_service_via_wadb` was custom | **UPSTREAM** — method name in equivalent code |
| `persist.adb.tcp.port` handling was custom | **UPSTREAM** — EnvironmentUtils.getAdbTcpPort() |
| Fork's `BootCompleteReceiver` is the unique custom piece | **CONFIRMED** — upstream has inline logic; fork delegates through new infrastructure |
| The fork directly sets `service.adb.tcp.port=5555` | **NOT PROVEN** — no code path found; likely set externally |
| Shizuku sustains port 5555 | **CORRECTED** — port persists independently; Shizuku provides the bridge process |

### RESOLVED OPEN QUESTIONS

| Previous Question | Resolution |
|------------------|------------|
| Who sets `service.adb.tcp.port=5555`? | Unproven at source level; likely prior manual `adb tcpip 5555` invocation |
| Does port survive Shizuku kill? | **YES** — proven via live monitoring (Phase 6) |
| Does WatchdogService auto-restart work? | **YES** — confirmed via logcat (Phase 6) |
| What is the actual dependency? | Bridge process (`shizuku_server`), not port sustainability |

## 7. Operational Consequence (Corrected)

If the custom Shizuku fork is removed (uninstall, disabled, or persistently killed):

1. `service.adb.tcp.port=5555` **will NOT clear** — it persists in the property system independently
2. `adbd` may continue listening on :5555 (source unclear — may be sustained by init or adbd itself)
3. `shizuku_server` process will be absent — no ADB protocol bridge exists
4. The on-device `fork-server` relay **cannot establish an ADB handshake** without shizuku_server
5. ADT commands sent over USB will fail — no device reachable via the wireless ADB path

**Key distinction from earlier documentation:** Port 5555 being "alive" mid-session does not mean ADB survives a full reboot without Shizuku. The dependency is dual: (1) bridge process (`shizuku_server`) during the session, and (2) BootCompleteReceiver bootstrap on cold boot. Without Shizuku installed, neither the port nor the bridge are available after reboot.

**Mitigation paths:**
- Keep Shizuku running (simplest — WatchdogService handles crashes automatically)
- Pre-seed the port with `adb tcpip 5555` before disconnecting USB (port survives, but bridge still needs shizuku_server)
- Use Android's native Wireless Debugging UI instead (sets `wireless_debugging_enabled=1`, pairs standard ADB wireless — no Shizuku needed, but requires manual pairing after each reboot)

## 8. How It Works After Reboot (Corrected Model)

```
REBOOT
  → adbd starts (init-managed, UID 2000)
  → service.adb.tcp.port=5555 already in property system (set once, prior to this session)
  → Custom Shizuku fork starts via BootCompleteReceiver
  → ShizukuReceiverStarter → AdbStartWorker runs
  → Fork sets ADB_ENABLED=1, adb_wifi_enabled=1 (transient flags)
  → WatchdogService starts (START_STICKY foreground)
  → shizuku_server begins listening for ADB handshakes on :5555
  → Host runs: adb -L tcp:5037 fork-server server --reply-fd 4
  → Relay connects to 127.0.0.1:5555 via shizuku_server bridge
  → Host ADB commands work
```

Without Shizuku:
```
  → adbd may still listen on :5555 (port value persists)
  → But no shizuku_server process exists
  → fork-server cannot complete ADB handshake
  → ADB transport path broken despite port being "active"
```

## 9. Important Limitations

- This documentation reflects the state as of 2026-09-13 (updated through Phase 6).
- The forensic investigation was read-only. No state modifications were made except an intentional `am force-stop` kill test during Phase 6 monitoring.
- Source-level comparison against upstream Shizuku confirmed that most "custom" strings are upstream features; true customizations are architectural (delegation pattern, WatchdogService, hardcoded package name).
- The exact origin of `service.adb.tcp.port=5555` remains unproven at the code level — most likely a prior manual `adb tcpip 5555` invocation.
- Whether `adbd` continues listening on :5555 without Shizuku depends on whether the socket is owned by adbd or shizuku_server — this requires adbd source analysis to confirm definitively.
- **Verified 2026-09-13:** Full reboot without Shizuku leaves ADB completely non-functional. Port 5555 is not listening, `adb connect` refuses, no USB device detected. The fork's BootCompleteReceiver is required on cold boot to bootstrap the transport.

## 10. How It Works — Installation & Operation Guide

This section documents what anyone installing this setup needs to know for it to function correctly.

### Prerequisites (One-Time Setup)

1. **Install the custom Shizuku fork** (`moe.shizuku.privileged.api`) on the device
2. **Grant WRITE_SECURE_SETTINGS permission** to Shizuku:
   ```bash
   adb shell pm grant moe.shizuku.privileged.api android.permission.WRITE_SECURE_SETTINGS
   ```
3. **Enable Wireless Debugging manually once** to seed port 5555:
   ```bash
   adb tcpip 5555
   ```
   This sets `service.adb.tcp.port=5555` in the property system. The value persists even after Shizuku is uninstalled.
4. **Connect via wireless ADB** (one-time):
   ```bash
   adb connect 192.168.0.102:5555
   ```
5. **Start the fork-server relay inside PRoot/Termux**:
   ```bash
   adb -L tcp:5037 fork-server server --reply-fd 4
   ```
   This must be started manually in each PRoot session — there is no auto-start.

### Normal Operation

- **Shizuku runs automatically on boot** via BootCompleteReceiver → ShizukuReceiverStarter → AdbStartWorker
- **WatchdogService keeps Shizuku alive** — if killed, it auto-restarts within seconds
- **Host ADB connects via wireless** by default: `adb -s 192.168.0.102:5555 ...`
- **USB fallback works** if the fork-server relay is running: host `adb` talks to `localhost:5037`, relay bridges to device `:5555`

### Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| `adb devices` shows nothing | fork-server relay not running | Start relay in Termux: `adb -L tcp:5037 fork-server server --reply-fd 4` |
| `adb connect` fails | Port 5555 not set or Shizuku not running | Run `adb tcpip 5555` via USB first, ensure Shizuku is installed and running |
| Shizuku crashes frequently | WatchdogService may have failed | Check logcat: `adb logcat | grep -i shizuku`; reinstall fork if needed |
| Port 5555 disappears after reboot | Property cleared (rare) | Re-run `adb tcpip 5555`; Shizuku BootCompleteReceiver will re-enable ADB flags |

### What You Can Remove Without Breaking ADB

| Component | Effect of Removal |
|-----------|------------------|
| Fork-server relay process | USB path breaks; wireless path still works via `adb connect` |
| Shizuku app (force-stop) | Auto-restarts via WatchdogService; port 5555 persists mid-session |
| Shizuku app (uninstall) | Port 5555 LOST on next reboot; `shizuku_server` gone; both USB relay and wireless ADB broken |
| WatchdogService | Shizuku crashes persist until manual restart |

---

## 11. Relationship to ADT's General Portability

ADT is designed to work with any standard ADB transport — USB, TCP/IP, or emulator. The Shizuku dependency described here is **not a design requirement of ADT**. It is an artifact of the current development environment:

- ADT's ADB binary is the vanilla AOSP binary, identical across all platforms
- ADT's build toolchain (NDK, Clang, LLD) has no Shizuku dependency
- ADT's validation pipeline targets standard ADB transport
- The Shizuku dependency arises solely from the decision to run an on-device ADB relay inside a PRoot container that relies on Wireless Debugging as the transport bridge

If the development environment changes (e.g., direct USB ADB, different device, emulator), this dependency disappears entirely.

---

## Cross-References

- [REAL_DEVICE_BUILD_VALIDATION.md](./REAL_DEVICE_BUILD_VALIDATION.md) — End-to-end ARM64 build validation on this device
- [ANDROID_ARM64_BUILD_HANDOFF.md](./ANDROID_ARM64_BUILD_HANDOFF.md) — Build environment configuration and validated state
- [forensic-report-phase5-source-comparison-2026-09-13.md](../../forensic-report-phase5-source-comparison-2026-09-13.md) — Source-level fork vs upstream diff
- [forensic-report-phase6-property-monitor-2026-09-13.md](../../forensic-report-phase6-property-monitor-2026-09-13.md) — Live monitoring: port persistence after kill, watchdog restart verification

---

*Documentation created: 2026-09-12 | Based on read-only forensic audit | No code or configuration changes made*
