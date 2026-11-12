import 'package:drift/drift.dart' show Value;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../database/tables.dart';
import '../struct/databaseGlobal.dart';
import 'core/currency.dart';
import 'dedup/dedup_engine.dart';
import 'parser/parsed_txn.dart';
import 'parser/sms_parser.dart';
import 'sms/sms_source.dart';

class Decipline2.0SmsBridge {
  Decipline2.0SmsBridge._();

  static const _prefLastSyncMillis = 'cashew_sms_last_sync_millis';
  static const _prefSmsEnabled = 'flutter.sms.enabled';
  static const _uuid = Uuid();

  static final _smsSource = SmsSource();
  static final _parser = SmsParser();
  static const _dedup = DedupEngine();

  static bool _isSyncing = false;

  static Future<int> syncNewMessages({
    bool includeTransfersAsUnpaid = false,
    Duration initialLookback = const Duration(days: 7),
  }) async {
    if (_isSyncing || !_smsSource.isSupported) return 0;
    _isSyncing = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool(_prefSmsEnabled) ?? true;
      if (!enabled) return 0;

      if (!await _smsSource.hasPermission()) return 0;

      final lastSyncMs = prefs.getInt(_prefLastSyncMillis);
      final since = lastSyncMs != null
          ? DateTime.fromMillisecondsSinceEpoch(lastSyncMs)
          : DateTime.now().subtract(initialLookback);

      final rawMessages = await _smsSource.readSince(since);
      if (rawMessages.isEmpty) return 0;

      var insertedCount = 0;
      var latestTimestamp = since.millisecondsSinceEpoch;

      for (final raw in rawMessages) {
        if (raw.receivedAt.millisecondsSinceEpoch > latestTimestamp) {
          latestTimestamp = raw.receivedAt.millisecondsSinceEpoch;
        }

        final result = _parser.parse(raw);
        if (result is! Parsed) continue;

        final txn = result.txn;
        if (txn.confidence < 0.65) continue;
        if (txn.transferHint && !includeTransfersAsUnpaid) continue;

        final sourceKey = DedupEngine.sourceKey(raw.source, raw.sender);
        final isDuplicate = await _isAlreadyInDecipline2.0(txn, sourceKey);
        if (isDuplicate) continue;

        await _insertIntoDecipline2.0(
          txn: txn,
          sourceKey: sourceKey,
          markPaid: !txn.transferHint,
        );
        insertedCount++;
      }

      await prefs.setInt(_prefLastSyncMillis, latestTimestamp);
      return insertedCount;
    } finally {
      _isSyncing = false;
    }
  }

  static Future<bool> _isAlreadyInDecipline2.0(ParsedTxn txn, String sourceKey) async {
    final currencyCode = txn.convertedCurrency ?? txn.currency ?? 'INR';
    final minorAmount = txn.convertedMinor ?? txn.amountMinor;
    final majorAmount = toMajor(minorAmount, currencyCode);
    final isIncome = txn.direction == TxnDirection.credit;

    final windowStart = txn.occurredAt.subtract(const Duration(hours: 24));
    final windowEnd = txn.occurredAt.add(const Duration(hours: 24));

    final allTxns = await database.getAllTransactions();
    final nearby = allTxns.where((t) {
      if (t.income != isIncome) return false;
      if (t.dateCreated.isBefore(windowStart) || t.dateCreated.isAfter(windowEnd)) {
        return false;
      }
      return (t.amount.abs() - majorAmount.abs()).abs() < 0.01;
    });

    if (nearby.isEmpty) return false;

    final candidates = nearby.map((t) {
      return DedupCandidate(
        id: t.transactionPk.hashCode,
        occurredAt: t.dateCreated,
        reference: _extractRefFromNote(t.note),
        accountHint: _extractAcctFromNote(t.note),
        merchant: t.name,
        counterparty: t.name,
        sourceKeys: _extractSourceKeyFromNote(t.note),
      );
    });

    final bestMatch = _dedup.best(txn, sourceKey, candidates);
    return bestMatch != null && bestMatch.score >= DedupEngine.autoMerge;
  }

  static Future<void> _insertIntoDecipline2.0({
    required ParsedTxn txn,
    required String sourceKey,
    required bool markPaid,
  }) async {
    final currencyCode = txn.convertedCurrency ?? txn.currency ?? 'INR';
    final minorAmount = txn.convertedMinor ?? txn.amountMinor;
    final majorAmount = toMajor(minorAmount, currencyCode);
    final isIncome = txn.direction == TxnDirection.credit;

    final displayName = _buildTitle(txn);
    final walletPk = await _resolveWalletPk(txn.accountHint);
    final categoryPk = await _resolveCategoryPk(displayName, isIncome);
    final structuredNote = _buildNote(txn, sourceKey);

    final companion = TransactionsCompanion.insert(
      transactionPk: Value(_uuid.v4()),
      name: displayName,
      amount: majorAmount,
      note: Value(structuredNote),
      categoryFk: categoryPk,
      walletFk: walletPk,
      dateCreated: txn.occurredAt,
      income: isIncome,
      paid: markPaid,
      skipPaid: const Value(false),
      createdAnotherFutureTransaction: const Value(false),
    );

    await database.createOrUpdateTransaction(companion, isInbox: false);
  }

  static String _buildTitle(ParsedTxn txn) {
    if (txn.merchant != null && txn.merchant!.trim().isNotEmpty) {
      return txn.merchant!.trim();
    }
    if (txn.counterparty != null && txn.counterparty!.trim().isNotEmpty) {
      return txn.counterparty!.trim();
    }
    final inst = txn.institution ?? '';
    return '$inst ${txn.mode.name.toUpperCase()}'.trim();
  }

  static Future<String> _resolveWalletPk(String? accountHint) async {
    final wallets = await database.getAllWallets();
    if (accountHint != null && accountHint.isNotEmpty) {
      for (final w in wallets) {
        if (w.name.contains(accountHint)) {
          return w.walletPk;
        }
      }
    }
    return wallets.first.walletPk;
  }

  static Future<String> _resolveCategoryPk(String title, bool isIncome) async {
    final associated = await database.getAssociateTitle(title);
    if (associated != null) {
      return associated.categoryFk;
    }
    final categories = await database.getAllCategories();
    final fallback = categories.firstWhere(
      (c) => c.income == isIncome,
      orElse: () => categories.first,
    );
    return fallback.categoryPk;
  }

  static String _buildNote(ParsedTxn txn, String sourceKey) {
    final parts = <String>['Auto-SMS'];
    if (txn.institution != null) parts.add(txn.institution!);
    parts.add(txn.mode.name.toUpperCase());
    if (txn.accountHint != null) parts.add('Acct:${txn.accountHint}');
    if (txn.reference != null) parts.add('Ref:${txn.reference}');
    if (txn.isPersonToPerson && txn.merchant != null) parts.add('Person:${txn.merchant}');
    parts.add('[$sourceKey]');
    return parts.join(' • ');
  }

  static String? _extractRefFromNote(String note) {
    final m = RegExp(r'Ref:([A-Za-z0-9]+)').firstMatch(note);
    return m?.group(1);
  }

  static String? _extractAcctFromNote(String note) {
    final m = RegExp(r'Acct:(\d{3,4})').firstMatch(note);
    return m?.group(1);
  }

  static Set<String> _extractSourceKeyFromNote(String note) {
    final m = RegExp(r'\[(sms:[^\]]+)\]').firstMatch(note);
    return m != null ? {m.group(1)!} : const {};
  }
}
