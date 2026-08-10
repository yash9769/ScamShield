# ScamShield — Physical Android Device Test Plan & Matrix

> **Note & Certification Disclaimer**:  
> In accordance with strict QA audit rules, physical rooted-device behavior **has NOT been directly executed** due to no physical device currently being attached to the local USB debugging interface. All native MethodChannel Kotlin handlers (`MainActivity.kt`) have been verified via static code inspection and tested within the Android Emulator (`emulator-5554`).

---

## 1. Test Matrix Overview

| Test ID | Device Target | Android OS | Root Status | Bootloader | Encryption | Expected MethodChannel Output |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **PHYS-001** | Google Pixel 8 (Physical) | Android 14 (API 34) | NOT ROOTED | Locked | Hardware AES-256 | `{isRooted: false, bootloader: "LOCKED", encrypted: true}` |
| **PHYS-002** | OnePlus 9 Pro (Rooted) | Android 13 (API 33) | ROOTED (Magisk) | Unlocked | Hardware AES-256 | `{isRooted: true, bootloader: "UNLOCKED", encrypted: true}` |
| **PHYS-003** | Xiaomi Redmi Note 12 | Android 12 (API 31) | NOT ROOTED | Unlocked | Hardware AES-256 | `{isRooted: false, bootloader: "UNLOCKED", encrypted: true}` |
| **PHYS-004** | Android Emulator (`emulator-5554`) | Android 15 (API 36) | EMULATOR | Unknown | Emulated | `{isRooted: false, isEmulator: true, bootloader: "EMULATOR"}` |

---

## 2. Test Execution Procedure for On-Site Hardware Verification

1. **Connect Physical Device via ADB**:
   ```bash
   adb devices -l
   ```
2. **Launch ScamShield Flutter App**:
   ```bash
   flutter run -d <device_id>
   ```
3. **Navigate to SIM Lock & Hardware Auditor Screen**:
   - Open `SimLockScreen` (`lib/screens/sim_lock_screen.dart`).
   - Trigger `checkDeviceIntegrity` native MethodChannel call.
4. **Verify Native Response Payload**:
   - Confirm UI updates without crashing or hardcoded fallbacks.
   - Verify handling of `UNKNOWN` or `NATIVE_ERROR` states gracefully.
