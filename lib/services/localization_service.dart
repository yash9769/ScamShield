// lib/services/localization_service.dart

class LocalizationService {
  static String currentLanguage = 'EN'; // 'EN', 'HI', 'ES', 'FR'

  static final Map<String, Map<String, String>> _translations = {
    'EN': {
      'app_title': 'ScamShield',
      'shield_active': 'SHIELD ACTIVE',
      'scan_now': 'SCAN NOW',
      'high_risk': 'HIGH RISK THREAT DETECTED',
      'safe_verdict': 'SAFE — NO KNOWN THREATS',
      'suspicious_verdict': 'SUSPICIOUS PATTERN DETECTED',
      'learn_title': 'CYBER THREAT ACADEMY',
    },
    'HI': {
      'app_title': 'स्कैमशील्ड',
      'shield_active': 'शील्ड सक्रिय',
      'scan_now': 'अभी स्कैन करें',
      'high_risk': 'उच्च जोखिम वाला खतरा पाया गया',
      'safe_verdict': 'सुरक्षित — कोई खतरा नहीं',
      'suspicious_verdict': 'संदेहजनक पैटर्न पाया गया',
      'learn_title': 'साइबर खतरा अकादमी',
    },
    'ES': {
      'app_title': 'ScamShield',
      'shield_active': 'PROTECCIÓN ACTIVA',
      'scan_now': 'ESCANEAR AHORA',
      'high_risk': 'AMENAZA DE ALTO RIESGO DETECTADA',
      'safe_verdict': 'SEGURO — SIN AMENAZAS CONOCIDAS',
      'suspicious_verdict': 'PATRÓN SOSPECHOSO DETECTADO',
      'learn_title': 'ACADEMIA DE AMENAZAS CIBERNÉTICAS',
    },
    'FR': {
      'app_title': 'ScamShield',
      'shield_active': 'BOUCLIER ACTIF',
      'scan_now': 'SCANNER MAINTENANT',
      'high_risk': 'MENACE À HAUT RISQUE DÉTECTÉE',
      'safe_verdict': 'SÉCURISÉ — AUCUNE MENACE DÉTECTÉE',
      'suspicious_verdict': 'PATRON SUSPECT DÉTECTÉ',
      'learn_title': 'ACADÉMIE DES CYBERMENACES',
    },
  };

  static String tr(String key) {
    return _translations[currentLanguage]?[key] ?? _translations['EN']?[key] ?? key;
  }

  static void setLanguage(String langCode) {
    if (_translations.containsKey(langCode)) {
      currentLanguage = langCode;
    }
  }
}
