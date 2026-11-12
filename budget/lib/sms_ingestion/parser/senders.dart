class SenderInfo {
  const SenderInfo(this.institution, {this.isWallet = false});
  final String institution;
  final bool isWallet;
}

final _dltHeader = RegExp(r'^[A-Z]{2}-([A-Z0-9]{2,9})(?:-[STG])?$');
final _promoSuffix = RegExp(r'-P$');

bool isPromotionalSender(String sender) {
  final s = sender.trim().toUpperCase();
  return _promoSuffix.hasMatch(s);
}

SenderInfo? identifySender(String sender) {
  final raw = sender.trim().toUpperCase();
  if (raw.isEmpty || isPromotionalSender(raw)) return null;

  final match = _dltHeader.firstMatch(raw);
  final core = match != null ? match.group(1)! : raw;

  for (final entry in _knownSenders.entries) {
    if (core.contains(entry.key)) {
      return entry.value;
    }
  }
  return null;
}

const _knownSenders = <String, SenderInfo>{
  'HDFC': SenderInfo('HDFC Bank'),
  'ICICI': SenderInfo('ICICI Bank'),
  'SBICRD': SenderInfo('SBI Card'),
  'SBI': SenderInfo('SBI'),
  'AXIS': SenderInfo('Axis Bank'),
  'KOTAK': SenderInfo('Kotak Bank'),
  'KMBL': SenderInfo('Kotak Bank'),
  'IDFC': SenderInfo('IDFC First Bank'),
  'YESB': SenderInfo('Yes Bank'),
  'INDUS': SenderInfo('IndusInd Bank'),
  'PNB': SenderInfo('PNB'),
  'BOB': SenderInfo('Bank of Baroda'),
  'BARODA': SenderInfo('Bank of Baroda'),
  'CANBNK': SenderInfo('Canara Bank'),
  'UNION': SenderInfo('Union Bank'),
  'UBOI': SenderInfo('Union Bank'),
  'BOI': SenderInfo('Bank of India'),
  'INDBNK': SenderInfo('Indian Bank'),
  'FED': SenderInfo('Federal Bank'),
  'AUBANK': SenderInfo('AU Bank'),
  'RBL': SenderInfo('RBL Bank'),
  'IDBI': SenderInfo('IDBI Bank'),
  'CITI': SenderInfo('Citibank'),
  'HSBC': SenderInfo('HSBC'),
  'AMEX': SenderInfo('Amex'),
  'SCB': SenderInfo('Standard Chartered'),
  'DBS': SenderInfo('DBS Bank'),
  'IPPB': SenderInfo('India Post Payments Bank'),
  'PAYTM': SenderInfo('Paytm', isWallet: true),
  'PYTM': SenderInfo('Paytm', isWallet: true),
  'AIRBNK': SenderInfo('Airtel Payments Bank', isWallet: true),
  'JUPITR': SenderInfo('Jupiter'),
  'ONECRD': SenderInfo('OneCard'),
  'SLICE': SenderInfo('slice'),
  'MOBIKW': SenderInfo('MobiKwik', isWallet: true),
  'AMZPAY': SenderInfo('Amazon Pay', isWallet: true),
  'IMEIND': SenderInfo('IME India'),
};
