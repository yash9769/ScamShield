// lib/services/qr_content.dart
//
// What is actually inside a QR code, in plain terms.
//
// A QR code is just a way of carrying a string. People scan it and trust
// whatever the phone then opens, which is exactly what "quishing" (QR phishing)
// relies on: a sticker over a parking meter, a poster with a "pay here" code, a
// message saying "scan to verify your account". Before anything is opened the
// person needs to see where it leads: the real address, whose domain it is, and
// the tricks that make a bad address look like a good one.
//
// Pure Dart, no network, so it is fast and testable. Anything that contacts a
// server (redirect tracing, Safe Browsing) is a separate, explicit step.

enum QrKind { url, wifi, phone, sms, email, location, contact, payment, text }

enum QrWarningLevel { info, caution, danger }

class QrWarning {
  final QrWarningLevel level;
  final String message;
  const QrWarning(this.level, this.message);
}

class QrContent {
  final String raw;
  final QrKind kind;

  /// A short headline: "Web link", "Wi-Fi network", ...
  final String title;

  /// Label/value pairs to show, in order.
  final List<MapEntry<String, String>> fields;
  final List<QrWarning> warnings;

  /// For links: the address that will be opened (scheme added if missing).
  final Uri? uri;

  /// For links: the part of the host that identifies who owns it, e.g.
  /// "sbi.co.in" in "login.sbi.co.in", or "evil.top" in "sbi.co.in.evil.top".
  final String? registrableDomain;

  const QrContent({
    required this.raw,
    required this.kind,
    required this.title,
    this.fields = const [],
    this.warnings = const [],
    this.uri,
    this.registrableDomain,
  });

  bool get hasDanger => warnings.any((w) => w.level == QrWarningLevel.danger);
  bool get isLink => kind == QrKind.url && uri != null;
}

class QrContentParser {
  QrContentParser._();

  static const _shorteners = {
    'bit.ly',
    'tinyurl.com',
    'goo.gl',
    't.co',
    'ow.ly',
    'buff.ly',
    'is.gd',
    'rb.gy',
    'cutt.ly',
    'tiny.cc',
    'adf.ly',
    'shorturl.at',
    'clck.ru',
    'rebrand.ly',
    'lnkd.in',
    'wa.me',
    'qrco.de',
    'qr.page',
    'l.ead.me',
  };

  // Domains that attackers imitate, mapped to the domains that really belong
  // to them. A host that mentions the brand but is not on one of these is the
  // classic "sbi.co.in.verify-login.top" trick.
  static const _brands = <String, Set<String>>{
    'sbi': {'sbi.co.in', 'onlinesbi.sbi', 'sbi.bank.in'},
    'hdfc': {'hdfcbank.com', 'hdfc.com'},
    'icici': {'icicibank.com', 'icici.com'},
    'axis': {'axisbank.com'},
    'paytm': {'paytm.com', 'paytm.in'},
    'phonepe': {'phonepe.com'},
    'gpay': {'pay.google.com', 'google.com'},
    'google': {'google.com', 'google.co.in', 'goo.gl', 'g.co'},
    'amazon': {'amazon.com', 'amazon.in', 'amzn.in', 'amzn.to'},
    'flipkart': {'flipkart.com', 'fkrt.it'},
    'netflix': {'netflix.com'},
    'microsoft': {'microsoft.com', 'live.com', 'office.com'},
    'apple': {'apple.com', 'icloud.com'},
    'whatsapp': {'whatsapp.com', 'wa.me'},
    'facebook': {'facebook.com', 'fb.com'},
    'instagram': {'instagram.com'},
    'irctc': {'irctc.co.in'},
    'incometax': {'incometax.gov.in'},
    'uidai': {'uidai.gov.in'},
  };

  static const _suspiciousTlds = {
    'top',
    'xyz',
    'click',
    'icu',
    'gq',
    'tk',
    'ml',
    'cf',
    'ga',
    'work',
    'cyou',
    'rest',
    'monster',
    'buzz',
    'sbs',
    'info',
    'biz',
    'link',
    'live',
  };

  static const _secondLevel = {
    'co',
    'com',
    'org',
    'net',
    'gov',
    'ac',
    'edu',
    'nic',
  };

  static QrContent parse(String input) {
    final raw = input.trim();
    final lower = raw.toLowerCase();

    if (lower.startsWith('upi:')) {
      return QrContent(
        raw: raw,
        kind: QrKind.payment,
        title: 'UPI payment request',
        fields: _queryFields(raw.substring(4).replaceFirst('//', '')),
        warnings: const [
          QrWarning(
            QrWarningLevel.caution,
            'Scanning to PAY sends money out. Scanning never receives money: '
            'if someone says "scan this to get paid", it is a scam.',
          ),
        ],
      );
    }
    if (lower.startsWith('wifi:')) return _wifi(raw);
    if (lower.startsWith('tel:')) {
      return QrContent(
        raw: raw,
        kind: QrKind.phone,
        title: 'Phone number',
        fields: [MapEntry('Number', raw.substring(4))],
        warnings: const [
          QrWarning(
            QrWarningLevel.info,
            'Scanning does not call by itself. Be wary of numbers on posters '
            'or stickers claiming to be a bank or support line.',
          ),
        ],
      );
    }
    if (lower.startsWith('sms:') || lower.startsWith('smsto:')) {
      final body = raw.substring(raw.indexOf(':') + 1);
      final parts = body.split(RegExp(r'[:?]'));
      return QrContent(
        raw: raw,
        kind: QrKind.sms,
        title: 'Text message',
        fields: [
          MapEntry('To', parts.first),
          if (parts.length > 1) MapEntry('Message', parts.sublist(1).join(':')),
        ],
        warnings: const [
          QrWarning(
            QrWarningLevel.caution,
            'This would prepare a text to a number chosen by whoever made the '
            'code. Premium-rate and subscription scams use this.',
          ),
        ],
      );
    }
    if (lower.startsWith('mailto:')) {
      return QrContent(
        raw: raw,
        kind: QrKind.email,
        title: 'Email',
        fields: [MapEntry('To', raw.substring(7).split('?').first)],
      );
    }
    if (lower.startsWith('geo:')) {
      return QrContent(
        raw: raw,
        kind: QrKind.location,
        title: 'Location',
        fields: [MapEntry('Coordinates', raw.substring(4))],
      );
    }
    if (lower.startsWith('begin:vcard') || lower.startsWith('mecard:')) {
      return QrContent(
        raw: raw,
        kind: QrKind.contact,
        title: 'Contact card',
        fields: [
          MapEntry('Details', raw.replaceAll(RegExp(r'[\r\n]+'), ' · ')),
        ],
      );
    }
    final link = _asLink(raw);
    if (link != null) return _url(raw, link);

    return QrContent(
      raw: raw,
      kind: QrKind.text,
      title: 'Plain text',
      fields: [MapEntry('Text', raw)],
      warnings: [
        if (RegExp(r'(?<!\d)\d{4,8}(?!\d)').hasMatch(raw) &&
            RegExp(r'otp|code|pin', caseSensitive: false).hasMatch(raw))
          const QrWarning(
            QrWarningLevel.caution,
            'Mentions a code or PIN. Never share these with anyone.',
          ),
      ],
    );
  }

  /// Returns a Uri when [raw] is an http(s) link or a bare "domain.tld/path".
  static Uri? _asLink(String raw) {
    if (raw.contains(RegExp(r'\s'))) return null;
    final withScheme =
        RegExp(r'^[a-z][a-z0-9+.-]*://', caseSensitive: false).hasMatch(raw)
        ? raw
        : 'http://$raw';
    final uri = Uri.tryParse(withScheme);
    if (uri == null || uri.host.isEmpty) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    // A bare string only counts as a link if it looks like a domain.
    if (!raw.contains('://') &&
        !RegExp(
          r'^[a-z0-9-]+(\.[a-z0-9-]+)+',
          caseSensitive: false,
        ).hasMatch(raw)) {
      return null;
    }
    return uri;
  }

  static QrContent _url(String raw, Uri uri) {
    final host = uri.host.toLowerCase();
    final registrable = registrableDomainOf(host);
    final warnings = <QrWarning>[];
    final hadScheme = raw.contains('://');

    if (!hadScheme) {
      warnings.add(
        const QrWarning(
          QrWarningLevel.info,
          'The code holds a web address without http:// or https://.',
        ),
      );
    }
    if (uri.scheme == 'http') {
      warnings.add(
        const QrWarning(
          QrWarningLevel.caution,
          'Not encrypted (http, not https). Anything typed on this page can be '
          'read on the way. Real banks and shops use https.',
        ),
      );
    }
    if (uri.userInfo.isNotEmpty) {
      warnings.add(
        QrWarning(
          QrWarningLevel.danger,
          'The address contains "${uri.userInfo}@". Everything before the @ is '
          'ignored; the real destination is $host. This is a classic disguise.',
        ),
      );
    }
    if (RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host)) {
      warnings.add(
        const QrWarning(
          QrWarningLevel.danger,
          'The link goes to a raw IP address, not a named website. Legitimate '
          'services almost never do this.',
        ),
      );
    }
    if (host.split('.').any((l) => l.startsWith('xn--'))) {
      warnings.add(
        const QrWarning(
          QrWarningLevel.danger,
          'The address uses look-alike international characters (punycode), a '
          'way to spoof a familiar name.',
        ),
      );
    }
    if (_shorteners.contains(registrable)) {
      warnings.add(
        const QrWarning(
          QrWarningLevel.caution,
          'A link shortener hides the real destination. Trace it below before '
          'opening.',
        ),
      );
    }
    final tld = host.split('.').last;
    if (_suspiciousTlds.contains(tld)) {
      warnings.add(
        QrWarning(
          QrWarningLevel.caution,
          'Addresses ending in .$tld are cheap to register and are common in '
          'scams.',
        ),
      );
    }
    final impersonated = _impersonatedBrand(host, registrable);
    if (impersonated != null) {
      warnings.add(
        QrWarning(
          QrWarningLevel.danger,
          'The address mentions "$impersonated" but belongs to $registrable, '
          'not to $impersonated. This is how fake bank and shop pages are made.',
        ),
      );
    }
    if (host.split('.').length > 4) {
      warnings.add(
        const QrWarning(
          QrWarningLevel.caution,
          'Unusually many dots in the address. Only the last part (before the '
          'path) says who really owns it.',
        ),
      );
    }
    if (uri.hasPort && uri.port != 80 && uri.port != 443) {
      warnings.add(
        QrWarning(
          QrWarningLevel.caution,
          'Uses an unusual port (${uri.port}).',
        ),
      );
    }
    final path = uri.path.toLowerCase();
    if (path.endsWith('.apk')) {
      warnings.add(
        const QrWarning(
          QrWarningLevel.danger,
          'This link downloads an Android app file (.apk) from outside the Play '
          'Store, a common way to install malware.',
        ),
      );
    }
    if (RegExp(
      r'(login|signin|verify|update|kyc|secure|account|wallet|refund|bonus|reward)',
      caseSensitive: false,
    ).hasMatch(host + uri.path)) {
      warnings.add(
        const QrWarning(
          QrWarningLevel.caution,
          'The address asks you to log in, verify or claim something. Go to the '
          'organisation\'s app or official site yourself instead.',
        ),
      );
    }

    final shown = Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path,
      query: uri.hasQuery ? uri.query : null,
    ).toString();

    return QrContent(
      raw: raw,
      kind: QrKind.url,
      title: 'Web link',
      uri: uri,
      registrableDomain: registrable,
      fields: [
        MapEntry('Opens', shown),
        MapEntry('Website owner', registrable),
        if (uri.queryParameters.isNotEmpty)
          MapEntry(
            'Passes along',
            uri.queryParameters.entries
                .map((e) => '${e.key}=${e.value}')
                .join('\n'),
          ),
      ],
      warnings: warnings,
    );
  }

  /// "login.sbi.co.in" -> "sbi.co.in"; "sbi.co.in.evil.top" -> "evil.top".
  static String registrableDomainOf(String host) {
    final labels = host.toLowerCase().split('.');
    if (labels.length <= 2) return host.toLowerCase();
    final tld = labels.last;
    final second = labels[labels.length - 2];
    if (tld.length == 2 &&
        _secondLevel.contains(second) &&
        labels.length >= 3) {
      return labels.sublist(labels.length - 3).join('.');
    }
    return labels.sublist(labels.length - 2).join('.');
  }

  static String? _impersonatedBrand(String host, String registrable) {
    final squashed = host.replaceAll(RegExp(r'[-_]'), '');
    for (final entry in _brands.entries) {
      if (!squashed.contains(entry.key)) continue;
      final owns = entry.value.any(
        (real) => registrable == real || registrable.endsWith('.$real'),
      );
      if (!owns) return entry.key;
    }
    return null;
  }

  static QrContent _wifi(String raw) {
    String field(String key) {
      final m = RegExp(
        '(?:^|;)$key:((?:\\\\.|[^;])*)',
        caseSensitive: false,
      ).firstMatch(raw.substring(5));
      return (m?.group(1) ?? '').replaceAllMapped(
        RegExp(r'\\(.)'),
        (x) => x.group(1)!,
      );
    }

    final ssid = field('S');
    final security = field('T').isEmpty ? 'none' : field('T');
    return QrContent(
      raw: raw,
      kind: QrKind.wifi,
      title: 'Wi-Fi network',
      fields: [MapEntry('Network name', ssid), MapEntry('Security', security)],
      warnings: [
        if (security.toLowerCase() == 'nopass' || security == 'none')
          const QrWarning(
            QrWarningLevel.caution,
            'An open network with no password. Others on it may be able to '
            'watch your traffic.',
          ),
        const QrWarning(
          QrWarningLevel.info,
          'Join networks you recognise. A code on a poster can point to a '
          'fake hotspot.',
        ),
      ],
    );
  }

  static List<MapEntry<String, String>> _queryFields(String body) {
    final q = body.contains('?') ? body.split('?').last : body;
    final params = Uri.splitQueryString(q);
    const labels = {
      'pa': 'Pay to (UPI ID)',
      'pn': 'Name',
      'am': 'Amount',
      'tn': 'Note',
      'cu': 'Currency',
    };
    return [
      for (final e in params.entries) MapEntry(labels[e.key] ?? e.key, e.value),
    ];
  }
}
