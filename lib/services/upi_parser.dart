// lib/services/upi_parser.dart
//
// Parses the `upi://pay?...` deep link encoded in an Indian payment QR code.
//
// This matters because the QR is the scam. A victim is shown a code and told
// it will *receive* money — a "refund", a "cashback", a "verification" — when
// scanning it actually authorises a payment out. The payee handle (pa) is the
// one field that identifies who is really being paid, and it's the field the
// victim never sees in the payment app's rush to confirm.
//
// Spec reference: NPCI UPI Linking Specification, the query parameters are
//   pa = payee address (VPA)   pn = payee name       am = amount
//   tn = transaction note      cu = currency         tr/tid = reference ids

class UpiPaymentRequest {
  /// The payee VPA, e.g. `merchant@okaxis`. Always lower-cased.
  final String payeeAddress;
  final String? payeeName;
  final String? amount;
  final String? currency;
  final String? note;

  const UpiPaymentRequest({
    required this.payeeAddress,
    this.payeeName,
    this.amount,
    this.currency,
    this.note,
  });

  /// True when the QR fixes an amount. A blank amount means the payer types it
  /// in, which is how "scan to receive your refund" scams get someone to enter
  /// a number they think they're being given.
  bool get hasFixedAmount => amount != null && amount!.isNotEmpty;

  /// The bank/PSP handle after the '@' — useful context, not a trust signal.
  String get handleProvider {
    final at = payeeAddress.lastIndexOf('@');
    return at >= 0 && at < payeeAddress.length - 1 ? payeeAddress.substring(at + 1) : '';
  }
}

class UpiParser {
  UpiParser._();

  /// Returns a parsed request, or null when [raw] isn't a UPI payment link.
  ///
  /// Tolerant of the casing and scheme variations real-world QR generators
  /// emit (`UPI://PAY`, `upi://pay`), because rejecting a genuine payment QR
  /// on a formatting technicality would push the user back to their payment
  /// app unchecked — the exact outcome this feature exists to prevent.
  static UpiPaymentRequest? tryParse(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    if (!text.toLowerCase().startsWith('upi://')) return null;

    final Uri uri;
    try {
      uri = Uri.parse(text);
    } catch (_) {
      return null;
    }

    final params = <String, String>{};
    uri.queryParameters.forEach((key, value) {
      params[key.toLowerCase()] = value;
    });

    final payee = (params['pa'] ?? '').trim().toLowerCase();
    // Without a payee there is nothing to verify, so this isn't a payment
    // request we can meaningfully vet.
    if (payee.isEmpty || !payee.contains('@')) return null;

    return UpiPaymentRequest(
      payeeAddress: payee,
      payeeName: _nullIfBlank(params['pn']),
      amount: _nullIfBlank(params['am']),
      currency: _nullIfBlank(params['cu']) ?? 'INR',
      note: _nullIfBlank(params['tn']),
    );
  }

  static String? _nullIfBlank(String? v) {
    if (v == null) return null;
    final trimmed = v.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
