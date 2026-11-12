import '../parser/parsed_txn.dart';
import '../parser/text_utils.dart';

class DedupCandidate {
  const DedupCandidate({
    required this.id,
    required this.occurredAt,
    this.reference,
    this.accountHint,
    this.merchant,
    this.counterparty,
    this.sourceKeys = const {},
  });

  final int id;
  final DateTime occurredAt;
  final String? reference;
  final String? accountHint;
  final String? merchant;
  final String? counterparty;
  final Set<String> sourceKeys;
}

class DedupMatch {
  const DedupMatch(this.candidate, this.score);
  final DedupCandidate candidate;
  final double score;
}

class DedupEngine {
  const DedupEngine();

  static const autoMerge = 0.75;
  static const review = 0.5;

  DedupMatch? best(ParsedTxn txn, String sourceKey, Iterable<DedupCandidate> candidates) {
    DedupMatch? top;
    for (final c in candidates) {
      final s = score(txn, sourceKey, c);
      if (top == null || s > top.score) top = DedupMatch(c, s);
    }
    return top;
  }

  double score(ParsedTxn t, String sourceKey, DedupCandidate c) {
    if (t.reference != null && c.reference != null) {
      return _sameRef(t.reference!, c.reference!) ? 1.0 : 0.0;
    }

    var s = 0.15;

    var accountMatch = false;
    var accountConflict = false;
    if (t.accountHint != null && c.accountHint != null) {
      if (_sameAccount(t.accountHint!, c.accountHint!)) {
        s += 0.25;
        accountMatch = true;
      } else {
        s -= 0.5;
        accountConflict = true;
      }
    }

    final dt = t.occurredAt.difference(c.occurredAt).abs();
    if (dt <= const Duration(minutes: 5)) {
      s += 0.45;
    } else if (dt <= const Duration(minutes: 30)) {
      s += 0.35;
    } else if (dt <= const Duration(hours: 3)) {
      s += 0.2;
    } else if (dt <= const Duration(hours: 24)) {
      s += 0.1;
    }

    var merchantMatch = false;
    var merchantConflict = false;
    final a = merchantTokens(t.merchant)..addAll(merchantTokens(t.counterparty));
    final b = merchantTokens(c.merchant)..addAll(merchantTokens(c.counterparty));
    if (a.isNotEmpty && b.isNotEmpty) {
      final overlap = a.intersection(b).length / (a.length < b.length ? a.length : b.length);
      if (overlap >= 0.5) {
        s += 0.2;
        merchantMatch = true;
      } else if (overlap == 0) {
        s -= 0.1;
        merchantConflict = true;
      }
    }

    final hasPositiveAnchor = merchantMatch || accountMatch;
    if (hasPositiveAnchor && !merchantConflict && !accountConflict && _crossChannel(sourceKey, c.sourceKeys)) {
      if (dt <= const Duration(minutes: 30)) {
        s += 0.3;
      } else if (dt <= const Duration(hours: 3)) {
        s += 0.15;
      }
    }

    if (c.sourceKeys.contains(sourceKey)) s -= 0.35;

    return s.clamp(0.0, 1.0);
  }

  static bool _sameRef(String a, String b) {
    final x = a.toUpperCase(), y = b.toUpperCase();
    if (x == y) return true;
    return (x.length >= 10 && y.contains(x)) || (y.length >= 10 && x.contains(y));
  }

  static const _channels = {'sms', 'email'};
  static String _channel(String key) => key.split(':').first;

  static bool _crossChannel(String sourceKey, Set<String> existing) {
    final mine = _channel(sourceKey);
    if (!_channels.contains(mine) || existing.isEmpty) return false;
    return existing.every((k) {
      final c = _channel(k);
      return _channels.contains(c) && c != mine;
    });
  }

  static bool _sameAccount(String a, String b) => a.endsWith(b) || b.endsWith(a);

  static String sourceKey(SourceKind source, String sender) =>
      '${source.name}:${sender.trim().toUpperCase().replaceAll(RegExp(r'^[A-Z]{2}-|-[SPTG]$'), '')}';
}
