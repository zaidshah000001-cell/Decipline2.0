const currencyTokenPattern =
    r'(rs\.?|inr|₹|₨|(?<![a-z])(?:us|nz|s|a|c|r)\$|\$|€|£|¥|₩|₱|₫|฿|₦|₺|৳|'
    r'(?<![a-z])(?:usd|eur|gbp|aed|sar|qar|kwd|omr|bhd|sgd|myr|cad|aud|nzd|bdt|pkr|lkr|npr|idr|php|vnd|thb|ngn|'
    r'kes|zar|brl|mxn|jpy|krw)(?![a-z])|(?<![a-z])(?:rm|rp\.?)(?=\s?\d)|(?<![a-z])ksh\.?)';

const amountPattern = r'([0-9][0-9,]*(?:\.[0-9]{1,3})?)';

final currencySuffix = RegExp(
  r'^\s?(inr|usd|eur|gbp|aed|sar|qar|kwd|omr|bhd|sgd|myr|cad|aud|nzd|bdt|pkr|lkr|npr|idr|php|vnd|thb|ngn|kes|zar|'
  r'brl|mxn|jpy|krw)(?![a-z])',
);

String normalizeCurrencyText(String text) => text.replaceAll(RegExp(r'(?<![A-Za-z])TRY(?=\s?\d)'), '₺');

const _rupees = {'INR', 'PKR', 'LKR', 'NPR'};
const _dollars = {'USD', 'CAD', 'AUD', 'NZD', 'SGD', 'MXN'};

const _signs = {
  '₹': 'INR', 'inr': 'INR', 'us\$': 'USD', 'nz\$': 'NZD', 's\$': 'SGD',
  'a\$': 'AUD', 'c\$': 'CAD', 'r\$': 'BRL', '€': 'EUR', '£': 'GBP',
  '¥': 'JPY', '₩': 'KRW', '₱': 'PHP', '₫': 'VND', '฿': 'THB',
  '₦': 'NGN', '₺': 'TRY', '৳': 'BDT', 'rm': 'MYR', 'rp': 'IDR', 'ksh': 'KES',
};

String currencyOfToken(String token, {required String home}) {
  final t = token.trim().replaceAll(RegExp(r'\.$'), '');
  if (t == 'rs' || t == '₨') return _rupees.contains(home) ? home : 'INR';
  if (t == r'$') return _dollars.contains(home) ? home : 'USD';
  return _signs[t] ?? t.toUpperCase();
}
