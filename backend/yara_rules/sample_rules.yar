rule Anubis
{
    meta:
        description = "Detects Anubis Android banking trojan"
        author = "ScamShield"
    strings:
        $s1 = "Anubis" ascii wide nocase
        $s2 = "android.intent.action.PACKAGE_ADDED"
        $s3 = "android.app.action.DEVICE_ADMIN_ENABLED"
    condition:
        all of them
}

rule Cerberus
{
    meta:
        description = "Detects Cerberus Android banking trojan"
        author = "ScamShield"
    strings:
        $c1 = "cerberus" ascii wide nocase
        $c2 = "AccessibilityService"
        $c3 = "READ_SMS"
    condition:
        all of them
}

rule Joker
{
    meta:
        description = "Detects Joker fleeceware"
        author = "ScamShield"
    strings:
        $j1 = "joker" ascii wide nocase
        $j2 = "NotificationListenerService"
    condition:
        all of them
}

rule Generic_Keylogger
{
    meta:
        description = "Detects generic Android keylogging functionality"
        author = "ScamShield"
    strings:
        $k1 = "onAccessibilityEvent"
        $k2 = "TYPE_VIEW_TEXT_CHANGED"
        $k3 = "getText"
    condition:
        all of them
}


rule SMS_Interception
{
    meta:
        description = "SMS interception combined with exfiltration capability, typical of OTP-stealing malware"
        author = "ScamShield"
        severity = "high"
    strings:
        $recv = "android.provider.Telephony.SMS_RECEIVED"
        $abort = "abortBroadcast"
        $body = "getMessageBody"
    condition:
        all of them
}

rule Overlay_Attack
{
    meta:
        description = "Screen-overlay primitives used by credential-harvesting banking trojans"
        author = "ScamShield"
        severity = "high"
    strings:
        $o1 = "TYPE_APPLICATION_OVERLAY"
        $o2 = "SYSTEM_ALERT_WINDOW"
        $o3 = "addView"
        $o4 = "WindowManager"
    condition:
        3 of them
}

rule Dynamic_Code_Loading
{
    meta:
        description = "Runtime loading of code fetched after install, used to hide payloads from static review"
        author = "ScamShield"
        severity = "medium"
    strings:
        $d1 = "DexClassLoader"
        $d2 = "PathClassLoader"
        $d3 = "loadClass"
        $d4 = "getDeclaredMethod"
    condition:
        $d1 and 2 of ($d2, $d3, $d4)
}

rule Device_Admin_Abuse
{
    meta:
        description = "Requests device-admin privileges alongside lock/wipe controls, seen in ransomware"
        author = "ScamShield"
        severity = "high"
    strings:
        $a1 = "DeviceAdminReceiver"
        $a2 = "lockNow"
        $a3 = "resetPassword"
        $a4 = "wipeData"
    condition:
        $a1 and 2 of ($a2, $a3, $a4)
}

rule Root_Detection_Evasion
{
    meta:
        description = "Root/emulator checks used to evade sandboxed analysis"
        author = "ScamShield"
        severity = "medium"
    strings:
        $r1 = "/system/bin/su"
        $r2 = "test-keys"
        $r3 = "isDeviceRooted"
        $r4 = "generic_x86"
    condition:
        3 of them
}
