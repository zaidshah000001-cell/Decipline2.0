import '../core/currency.dart';
import 'currency_text.dart';
import 'parsed_txn.dart';
import 'senders.dart';
import 'text_utils.dart';

class SmsParser implements MessageParser {
  SmsParser({String? homeCurrency}) : _homeCurrency = homeCurrency;
  final String? _homeCurrency;

  String get _home => _homeCurrency ?? Currencies.home;

  static final _otp = RegExp(
    r'\b(otp|one[- ]time password|verification code|auth code)\b',
    caseSensitive: false,
  );
  static final _future = RegExp(
    r'\b(will be (auto[- ]?)?debited|to be debited|scheduled for|standing instruction|upcoming)\b',
    caseSensitive: false,
  );
  static final _failed = RegExp(
    r'\b(failed|declined|unsuccessful|could not be processed|rejected|bounced|returned unpaid)\b',
    caseSensitive: false,
  );
  static final _statement = RegExp(
    r'\b(statement (is )?generated|total (amount )?due|minimum (amount )?due|e-?statement)\b',
    caseSensitive: false,
  );
  static final _promo = RegExp(
    r'\b(pre-?approved|apply now|cashback up ?to|win up ?to|loan offer|credit limit increase|avail now)\b',
    caseSensitive: false,
  );

  static final _debitWords = RegExp(
    r'\b(debited|spent|withdrawn|sent|paid|deducted|purchase|charged|txn of|transaction of)\b',
    caseSensitive: false,
  );
  static final _creditWords = RegExp(
    r'\b(credited|received|deposited|refunded|reversed|reversal|cashback credited)\b',
    caseSensitive: false,
  );
  static final _refundWords = RegExp(
    r'\b(refund(ed)?|reversed|reversal)\b',
    caseSensitive: false,
  );

  static final _transferHint = RegExp(
    r'\b(credit card (bill|payment|dues)|cc bill|card payment|to self|self transfer|own account|'
    r'upi\s*lite|wallet\s*(load|top-?up|recharge)|added\s+to\s+wallet|fastag\s*recharge|metro\s*(card\s*)?recharge)\b',
    caseSensitive: false,
  );

  static final _accountHint = RegExp(
    r'(?:a/c|acct?|account|card)\s*(?:no\.?|ending|xx+|\*+)?\s*[x*]*(\d{3,4})\b',
    caseSensitive: false,
  );

  static final _refHint = RegExp(
    r'\b(?:upi\s*ref(?:\s*no)?|ref(?:\s*no)?|rrn|utr|txn\s*id)[\s:.\-#]*([a-z0-9]{8,22})\b',
    caseSensitive: false,
  );

  static final _partyNoise = RegExp(
    r'\b(ref(?:erence)?|rrn|utr|upi\s*ref|txn|id|no|num|number|umrn|mandate)\b[\s:.\-#]*[a-z0-9]*$',
    caseSensitive: false,
  );

  static final _debitParty = RegExp(
    r'(?:\b(?:to|at|towards|paid to|trf to|info[:\-]?)\s+)([A-Za-z0-9@._*\- &]{2,40}?)(?=\s+(?:on|via|through|ref|rrn|utr|upi|avl|bal|if|not|call|for|from)\b|[.,;\n]|$)',
    caseSensitive: false,
  );

  static final _creditParty = RegExp(
    r'(?:\b(?:from|by|received from|info[:\-]?)\s+)([A-Za-z0-9@._*\- &]{2,40}?)(?=\s+(?:on|via|through|ref|rrn|utr|upi|avl|bal|if|not|call|for|to)\b|[.,;\n]|$)',
    caseSensitive: false,
  );

  static final _businessWords = RegExp(
    r'\b(pvt|private|ltd|limited|llp|inc|store|mart|supermarket|medical|pharmacy|hospital|clinic|hotel|'
    r'restaurant|cafe|bakery|motors|fuels|petrol|enterprises|traders|associates|services|solutions|technologies|'
    r'swiggy|zomato|amazon|flipkart|uber|ola|rapido|blinkit|zepto|bigbasket|irctc|bookmyshow|netflix|spotify|'
    r'apple|google|openai|jio|airtel|vi|bsnl|dmart|reliance|tata)\b',
    caseSensitive: false,
  );

  @override
  ParseResult parse(RawInput input) {
    if (isPromotionalSender(input.sender)) {
      return const Ignored('Promotional sender');
    }

    final text = normalizeSpace(normalizeCurrencyText(input.body));
    final lower = text.toLowerCase();

    if (_otp.hasMatch(lower)) return const Ignored('OTP');
    if (_failed.hasMatch(lower)) return const Ignored('Failed / declined');
    if (_future.hasMatch(lower)) return const Ignored('Reminder / scheduled');
    if (_promo.hasMatch(lower)) return const Ignored('Promotional text');

    final dMatch = _debitWords.firstMatch(lower);
    final cMatch = _creditWords.firstMatch(lower);

    if (dMatch == null && cMatch == null) {
      if (_statement.hasMatch(lower)) return const Ignored('Statement / bill');
      return const Ignored('No transaction verb');
    }

    final TxnDirection direction;
    if (_refundWords.hasMatch(lower)) {
      direction = TxnDirection.credit;
    } else if (cMatch == null) {
      direction = TxnDirection.debit;
    } else if (dMatch == null) {
      direction = TxnDirection.credit;
    } else {
      direction = dMatch.start <= cMatch.start ? TxnDirection.debit : TxnDirection.credit;
    }

    final amounts = _extractAmounts(text, lower);
    if (amounts.isEmpty) {
      return const Unparsed('Transaction verb found but no valid amount');
    }

    final primary = amounts.first;
    final secondary = amounts.length > 1 && amounts[1].currency != primary.currency ? amounts[1] : null;

    final senderInfo = identifySender(input.sender);
    final mode = _detectMode(lower, senderInfo);
    final acct = _accountHint.firstMatch(text)?.group(1);
    final ref = _refHint.firstMatch(text)?.group(1);

    final rawParty = _extractParty(text, direction);
    final merchant = rawParty != null ? cleanMerchant(rawParty) : null;
    final isP2P = mode == PaymentMode.upi && merchant != null && _looksLikePerson(merchant, rawParty ?? '');
    final isTransfer = _transferHint.hasMatch(lower);

    var confidence = 0.5;
    if (senderInfo != null) confidence += 0.25;
    if (ref != null) confidence += 0.15;
    if (acct != null) confidence += 0.1;
    if (merchant != null) confidence += 0.05;
    confidence = confidence.clamp(0.0, 1.0);

    return Parsed(
      ParsedTxn(
        amountMinor: primary.minor,
        currency: primary.currency,
        convertedMinor: secondary?.minor,
        convertedCurrency: secondary?.currency,
        direction: direction,
        occurredAt: input.receivedAt,
        mode: mode,
        confidence: confidence,
        merchant: merchant,
        counterparty: rawParty,
        accountHint: acct,
        reference: ref,
        institution: senderInfo?.institution,
        isPersonToPerson: isP2P,
        transferHint: isTransfer,
      ),
    );
  }

  List<_ExtractedAmount> _extractAmounts(String original, String lower) {
    final prefixRx = RegExp('$currencyTokenPattern\\s*$amountPattern', caseSensitive: false);
    final out = <_ExtractedAmount>[];

    for (final m in prefixRx.allMatches(lower)) {
      if (_isBalanceContext(lower, m.start)) continue;
      final token = m.group(1)!;
      final numStr = m.group(2)!;
      final code = currencyOfToken(token, home: _home);
      final minor = parseMinor(numStr, digits: currencyDigits(code));
      if (minor != null && minor > 0) {
        out.add(_ExtractedAmount(minor, code));
      }
    }
    return out;
  }

  static bool _isBalanceContext(String lower, int start) {
    final before = lower.substring(start >= 28 ? start - 28 : 0, start);
    return RegExp(
      r'(bal(ance)?|limit|avl|available|clear|net|tot(al)?|outstanding|due|minimum|min|payable|'
      r'cashback|reward|points|blocked|lien)[\s:.\-]*(is\s*)?$',
    ).hasMatch(before);
  }

  PaymentMode _detectMode(String lower, SenderInfo? sender) {
    if (lower.contains('upi') || lower.contains('@')) return PaymentMode.upi;
    if (RegExp(r'\b(card|pos|ecom|contactless|visa|mastercard|rupay|amex)\b').hasMatch(lower)) {
      return PaymentMode.card;
    }
    if (lower.contains('neft')) return PaymentMode.neft;
    if (lower.contains('imps')) return PaymentMode.imps;
    if (lower.contains('rtgs')) return PaymentMode.rtgs;
    if (lower.contains('atm')) return PaymentMode.atm;
    if (RegExp(r'\b(netbanking|net banking|ibanking)\b').hasMatch(lower)) return PaymentMode.netbanking;
    if (sender?.isWallet == true || lower.contains('wallet')) return PaymentMode.wallet;
    return PaymentMode.other;
  }

  String? _extractParty(String text, TxnDirection direction) {
    final rx = direction == TxnDirection.debit ? _debitParty : _creditParty;
    final m = rx.firstMatch(text);
    if (m == null) return null;
    var candidate = m.group(1)!.replaceAll(_partyNoise, '').trim();
    if (candidate.length < 2 || isDateLike(candidate)) return null;
    return candidate;
  }

  bool _looksLikePerson(String cleaned, String raw) {
    if (raw.contains('@') && merchantFromVpa(raw) == null) return true;
    if (_businessWords.hasMatch(cleaned)) return false;
    final words = cleaned.split(RegExp(r'\s+'));
    return words.length >= 2 && words.length <= 3;
  }
}

class _ExtractedAmount {
  const _ExtractedAmount(this.minor, this.currency);
  final int minor;
  final String currency;
}
