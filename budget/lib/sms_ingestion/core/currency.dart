import 'dart:math' as math;
import 'package:intl/intl.dart';

class Currency {
  const Currency(this.code, this.name);
  final String code;
  final String name;
  int get digits => currencyDigits(code);
  @override
  String toString() => '$name ($code)';
}

const supportedCurrencies = <Currency>[
  Currency('INR', 'Indian Rupee'), Currency('AED', 'UAE Dirham'),
  Currency('SAR', 'Saudi Riyal'), Currency('QAR', 'Qatari Riyal'),
  Currency('KWD', 'Kuwaiti Dinar'), Currency('OMR', 'Omani Rial'),
  Currency('BHD', 'Bahraini Dinar'), Currency('SGD', 'Singapore Dollar'),
  Currency('MYR', 'Malaysian Ringgit'), Currency('USD', 'US Dollar'),
  Currency('GBP', 'British Pound'), Currency('CAD', 'Canadian Dollar'),
  Currency('AUD', 'Australian Dollar'), Currency('NZD', 'New Zealand Dollar'),
  Currency('EUR', 'Euro'), Currency('BDT', 'Bangladeshi Taka'),
  Currency('PKR', 'Pakistani Rupee'), Currency('LKR', 'Sri Lankan Rupee'),
  Currency('NPR', 'Nepalese Rupee'), Currency('IDR', 'Indonesian Rupiah'),
  Currency('PHP', 'Philippine Peso'), Currency('VND', 'Vietnamese Dong'),
  Currency('THB', 'Thai Baht'), Currency('NGN', 'Nigerian Naira'),
  Currency('KES', 'Kenyan Shilling'), Currency('ZAR', 'South African Rand'),
  Currency('BRL', 'Brazilian Real'), Currency('MXN', 'Mexican Peso'),
  Currency('TRY', 'Turkish Lira'), Currency('JPY', 'Japanese Yen'),
  Currency('KRW', 'South Korean Won'),
];

final _byCode = {for (final c in supportedCurrencies) c.code: c};
Currency? currencyFor(String code) => _byCode[code.toUpperCase()];
bool isSupportedCurrency(String code) => _byCode.containsKey(code.toUpperCase());

abstract final class Currencies {
  static String home = 'INR';
}

final _digits = <String, int>{};
final _symbols = <String, String>{};

int currencyDigits(String code) =>
    _digits[code] ??= NumberFormat.simpleCurrency(locale: 'en', name: code).decimalDigits ?? 2;

int minorPerUnit(String code) => math.pow(10, currencyDigits(code)).toInt();

String _simpleSymbol(String code) =>
    _symbols[code] ??= NumberFormat.simpleCurrency(locale: 'en', name: code).currencySymbol;

String currencyPrefix(String code, {String? home}) {
  home ??= Currencies.home;
  final s = _simpleSymbol(code);
  final letters = RegExp(r'^[A-Za-z]+$').hasMatch(s);
  if (letters && (s.length > 2 || s[0] == s[0].toLowerCase())) return '$code ';
  final shared = supportedCurrencies.any((c) => c.code != code && _simpleSymbol(c.code) == s);
  if (shared && code != home) return '$code ';
  return letters ? '$s ' : s;
}

String currencySymbol(String code, {String? home}) => currencyPrefix(code, home: home).trim();
String _locale(String code) => code == 'INR' ? 'en_IN' : 'en';
final _formats = <String, NumberFormat>{};

NumberFormat _format(String code, String home, int digits) => _formats['$code/$home/$digits'] ??= NumberFormat.currency(
  locale: _locale(code), name: code, symbol: currencyPrefix(code, home: home), decimalDigits: digits,
);

String formatMoney(int minor, {String? currency, bool forceDecimals = false}) {
  final code = currency ?? Currencies.home;
  final digits = currencyDigits(code);
  final per = minorPerUnit(code);
  final whole = minor % per == 0;
  return _format(code, Currencies.home, forceDecimals || !whole ? digits : 0).format(minor / per);
}

String plainAmount(int minor, String currency) =>
    (minor / minorPerUnit(currency)).toStringAsFixed(currencyDigits(currency));

double toMajor(int minor, String currency) => minor / minorPerUnit(currency);
int toMinor(num major, String currency) => (major * minorPerUnit(currency)).round();
