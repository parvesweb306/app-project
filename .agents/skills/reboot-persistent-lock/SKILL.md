---
name: reboot-persistent-lock
description: "Use when an Android parental-control or kiosk lock disappears after power-off, reboot, app restart, or boot. Trace persisted lock state, boot receivers, foreground services, device-owner lock task, and Flutter/native synchronization; implement and verify a reboot-safe fix."
---

# Reboot-Persistent Lock

Use this workflow when a child-device lock is lost after shutdown, restart, or process death.

## 1. Trace the controlling path

- Identify the native source of truth for the lock state.
- Check whether the state is persistent and whether it survives process death.
- Find normal boot, locked boot, package-replaced, foreground-service, accessibility-service, and activity startup paths.
- Check Flutter or UI startup for any default `false` value that can overwrite a persisted native lock.
- Confirm the manifest declares the receiver, service, and required permissions.

Form one local hypothesis before editing. Prefer a cheap check that could falsify it, such as inspecting the persisted preference before and after a simulated process restart.

## 2. Preserve the lock across boot phases

- Never infer unlock from a missing server response, timeout, or parse failure.
- If the app must lock before credential-protected storage is available, mirror the lock bit into device-protected storage and read it during direct boot.
- Write intentional lock and unlock transitions to both stores.
- Do not clear the lock during app initialization, service restart, network failure, or temporary permission failure.

## 3. Reapply protection after reboot

- Register a receiver for normal boot and, when appropriate, locked boot.
- Start the foreground status service after boot; it must safely no-op when pairing or network data is unavailable.
- If the persisted state is locked, bring the lock activity forward after boot with a short main-thread delay.
- Re-enter lock-task mode from the activity lifecycle and keep Back/navigation handling consistent.
- Document device-owner provisioning; Device Admin or Accessibility alone cannot guarantee kiosk navigation restrictions.

## 4. Protect synchronization semantics

- A successful server `is_locked: false` response may unlock the device.
- A timeout, non-200 response, parse error, missing token, or missing permission must not unlock it.
- Initialize the UI from native persisted state, never from an unlocked default.
- Unlock through the approved code path only, updating native persistence before the UI state.

## 5. Validate narrowly, then on-device

- Run `flutter pub get` if generated Flutter metadata is missing.
- Run `./android/gradlew -p android assembleDebug`.
- Inspect the merged manifest and confirm boot receiver actions.
- On a test device, lock from the parent dashboard, power off, power on, unlock the device credential if required, and verify Child Guard returns before another app can be used.
- Repeat with a software restart and app-process kill.
- Verify emergency-call and keyboard paths still work, and verify an authorized unlock remains unlocked after the next poll.

## Completion criteria

- The lock remains true across process death and reboot while the server reports locked.
- Boot starts monitoring and reopens the lock UI without requiring the child to launch the app.
- Network failures do not silently unlock the device.
- A valid unlock clears both persistent lock stores and exits lock-task mode.
- The debug build succeeds, and physical reboot testing is reported separately from build validation.
