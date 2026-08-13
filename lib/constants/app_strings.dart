// lib/constants/app_strings.dart
// Centralized strings for consistency and future localization support.

class AppStrings {
  // Common UI
  static const String ok = 'OK';
  static const String cancel = 'Cancel';
  static const String save = 'Save';
  static const String delete = 'Delete';
  static const String dismiss = 'Dismiss';
  static const String yes = 'Yes';
  static const String no = 'No';
  static const String retry = 'Retry';
  
  // Buttons
  static const String signIn = 'SIGN IN';
  static const String signOut = 'Sign Out';
  static const String saveSync = 'Save & Sync';
  
  // Errors
  static const String errorGeneric = 'An error occurred. Please try again.';
  static const String errorNetwork = 'Network error. Please check your connection.';
  static const String errorTimeout = 'Request timed out. Please try again.';
  static const String errorUnauthorized = 'Unauthorized. Please sign in again.';
  
  // Success messages
  static const String successSaved = 'Saved successfully.';
  static const String successCreated = 'Created successfully.';
  static const String successDeleted = 'Deleted successfully.';
  
  // Navigation
  static const String home = 'Home';
  static const String scan = 'Scan';
  static const String breach = 'Breach';
  static const String history = 'History';
  static const String learn = 'Learn';
  static const String profile = 'Profile';
  
  // Scan related
  static const String scanNow = 'SCAN NOW';
  static const String scanning = 'Scanning...';
  static const String scanComplete = 'Scan Complete';
  
  // Breach related
  static const String checkEmail = 'Check Email';
  static const String noExposure = 'No Known Exposure';
  static const String exposed = 'Exposed';
  
  // Device info
  static const String physicalDevice = 'Physical device';
  static const String simulator = 'Simulator';
  static const String yes2 = 'Yes';
  static const String no2 = 'No';
}
