/// Where a piece of evidence came from.
enum SourceKind { sms, email, manual, shortcut }

enum TxnDirection { debit, credit }

/// Payment rail detected from the message.
enum PaymentMode { upi, card, netbanking, neft, imps, rtgs, atm, wallet, cash, other }

/// A message as it arrives from any source, before parsing.
class RawInput {
  const RawInput({
    required this.source,
    required this.externalId,
    required this.sender,
    required this.body,
    required this.receivedAt,
  });

  final SourceKind source;
  final String externalId;
  final String sender;
  final String body;
  final DateTime receivedAt;
}

/// Structured transaction extracted from a message.
class ParsedTxn {
  const ParsedTxn({
    required this.amountMinor,
    required this.direction,
    required this.occurredAt,
    required this.mode,
    required this.confidence,
    this.currency,
    this.convertedMinor,
    this.convertedCurrency,
    this.merchant,
    this.counterparty,
    this.accountHint,
    this.reference,
    this.institution,
    this.isPersonToPerson = false,
    this.transferHint = false,
  });

  final int amountMinor;
  final String? currency;
  final int? convertedMinor;
  final String? convertedCurrency;
  final TxnDirection direction;
  final DateTime occurredAt;
  final PaymentMode mode;
  final double confidence;
  final String? merchant;
  final String? counterparty;
  final String? accountHint;
  final String? reference;
  final String? institution;
  final bool isPersonToPerson;
  final bool transferHint;

  @override
  String toString() =>
      'ParsedTxn(${direction.name} $amountMinor${currency == null ? '' : ' $currency'}'
      '${convertedMinor == null ? '' : ' (= $convertedMinor $convertedCurrency)'}, merchant: $merchant, cp: $counterparty, '
      'acct: $accountHint, ref: $reference, mode: ${mode.name}, inst: $institution, conf: $confidence)';
}

abstract interface class MessageParser {
  ParseResult parse(RawInput input);
}

sealed class ParseResult {
  const ParseResult();
}

final class Parsed extends ParseResult {
  const Parsed(this.txn);
  final ParsedTxn txn;
}

final class Ignored extends ParseResult {
  const Ignored(this.reason);
  final String reason;
}

final class Unparsed extends ParseResult {
  const Unparsed(this.reason);
  final String reason;
}
