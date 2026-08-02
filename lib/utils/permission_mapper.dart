class PermissionMapper {
  static Map<String, String> getRiskLevel(String permission) {
    permission = permission.toUpperCase().replaceAll('ANDROID.PERMISSION.', '');
    
    if (_dangerous.containsKey(permission)) {
      return {'level': 'Dangerous', 'desc': _dangerous[permission]!};
    } else if (_signature.containsKey(permission)) {
      return {'level': 'Signature', 'desc': _signature[permission]!};
    } else if (_normal.containsKey(permission)) {
      return {'level': 'Normal', 'desc': _normal[permission]!};
    }
    
    return {'level': 'Unknown', 'desc': 'Custom or unknown permission'};
  }

  static final Map<String, String> _dangerous = {
    'READ_CALENDAR': 'Allows an application to read the user\'s calendar data.',
    'WRITE_CALENDAR': 'Allows an application to write the user\'s calendar data.',
    'CAMERA': 'Required to be able to access the camera device.',
    'READ_CONTACTS': 'Allows an application to read the user\'s contacts data.',
    'WRITE_CONTACTS': 'Allows an application to write the user\'s contacts data.',
    'GET_ACCOUNTS': 'Allows access to the list of accounts in the Accounts Service.',
    'ACCESS_FINE_LOCATION': 'Allows an app to access precise location.',
    'ACCESS_COARSE_LOCATION': 'Allows an app to access approximate location.',
    'RECORD_AUDIO': 'Allows an application to record audio.',
    'READ_PHONE_STATE': 'Allows read only access to phone state.',
    'CALL_PHONE': 'Allows an application to initiate a phone call.',
    'READ_CALL_LOG': 'Allows an application to read the user\'s call log.',
    'WRITE_CALL_LOG': 'Allows an application to write the user\'s call log.',
    'ADD_VOICEMAIL': 'Allows an application to add voicemails.',
    'USE_SIP': 'Allows an application to use SIP service.',
    'PROCESS_OUTGOING_CALLS': 'Allows an application to see the number being dialed.',
    'BODY_SENSORS': 'Allows an application to access body sensors.',
    'SEND_SMS': 'Allows an application to send SMS messages.',
    'RECEIVE_SMS': 'Allows an application to receive SMS messages.',
    'READ_SMS': 'Allows an application to read SMS messages.',
    'RECEIVE_WAP_PUSH': 'Allows an application to receive WAP push messages.',
    'RECEIVE_MMS': 'Allows an application to receive MMS messages.',
    'READ_EXTERNAL_STORAGE': 'Allows an application to read from external storage.',
    'WRITE_EXTERNAL_STORAGE': 'Allows an application to write to external storage.',
    'SYSTEM_ALERT_WINDOW': 'Allows an app to create windows shown on top of all other apps. Very dangerous, often used by malware.',
    'BIND_ACCESSIBILITY_SERVICE': 'Allows an app to control the device screen and intercept inputs. Highly dangerous.',
    'REQUEST_INSTALL_PACKAGES': 'Allows an application to request installing packages. Used for sideloading malware.',
  };

  static final Map<String, String> _signature = {
    'BATTERY_STATS': 'Allows an application to collect battery statistics.',
    'BIND_APPWIDGET': 'Allows an application to tell the AppWidget service which application can access AppWidget\'s data.',
    'BIND_DEVICE_ADMIN': 'Must be required by device administration receiver.',
    'BIND_VPN_SERVICE': 'Must be required by a VpnService.',
    'CHANGE_COMPONENT_ENABLED_STATE': 'Allows an application to change whether an application component is enabled.',
    'CLEAR_APP_CACHE': 'Allows an application to clear caches.',
    'DELETE_PACKAGES': 'Allows an application to delete packages.',
    'INSTALL_PACKAGES': 'Allows an application to install packages.',
  };

  static final Map<String, String> _normal = {
    'ACCESS_LOCATION_EXTRA_COMMANDS': 'Allows an application to access extra location commands.',
    'ACCESS_NETWORK_STATE': 'Allows applications to access information about networks.',
    'ACCESS_WIFI_STATE': 'Allows applications to access information about Wi-Fi networks.',
    'BLUETOOTH': 'Allows applications to connect to paired bluetooth devices.',
    'BLUETOOTH_ADMIN': 'Allows applications to discover and pair bluetooth devices.',
    'CHANGE_NETWORK_STATE': 'Allows applications to change network connectivity state.',
    'CHANGE_WIFI_MULTICAST_STATE': 'Allows applications to enter Wi-Fi Multicast mode.',
    'CHANGE_WIFI_STATE': 'Allows applications to change Wi-Fi connectivity state.',
    'DISABLE_KEYGUARD': 'Allows applications to disable the keyguard if it is not secure.',
    'EXPAND_STATUS_BAR': 'Allows an application to expand or collapse the status bar.',
    'INTERNET': 'Allows applications to open network sockets.',
    'KILL_BACKGROUND_PROCESSES': 'Allows an application to kill background processes.',
    'MODIFY_AUDIO_SETTINGS': 'Allows an application to modify global audio settings.',
    'NFC': 'Allows applications to perform I/O operations over NFC.',
    'RECEIVE_BOOT_COMPLETED': 'Allows an application to receive boot completed broadcast.',
    'REORDER_TASKS': 'Allows an application to change the Z-order of tasks.',
    'REQUEST_IGNORE_BATTERY_OPTIMIZATIONS': 'Allows requesting ignore battery optimizations.',
    'SET_ALARM': 'Allows an application to broadcast an Intent to set an alarm.',
    'SET_WALLPAPER': 'Allows applications to set the wallpaper.',
    'USE_FINGERPRINT': 'Allows an app to use fingerprint hardware.',
    'VIBRATE': 'Allows access to the vibrator.',
    'WAKE_LOCK': 'Allows using WakeLocks to keep processor from sleeping.',
  };
}
