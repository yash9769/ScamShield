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

rule TestRule
{
 strings:
  $a="Firebase"

 condition:
  $a
}
