import 'dart:io';
import 'package:flutter/services.dart';
import '../parser/parsed_txn.dart';

class SmsSource {
  static const _channel = MethodChannel('pckt/sms');
  static const _device = MethodChannel('pckt/device');

  bool get isSupported => Platform.isAndroid;

  Future<bool> hasPermission() async => isSupported && (await _channel.invokeMethod<bool>('hasPermission') ?? false);

  Future<bool> requestPermission() async =>
      isSupported && (await _channel.invokeMethod<bool>('requestPermission') ?? false);

  Future<bool> hasReceivePermission() async =>
      isSupported && (await _channel.invokeMethod<bool>('hasReceivePermission') ?? false);

  Future<void> requestNotifications() async {
    if (isSupported) await _device.invokeMethod<void>('requestNotifications');
  }

  Future<bool> notificationsAllowed() async =>
      isSupported && (await _device.invokeMethod<bool>('notificationsAllowed') ?? false);

  Future<List<RawInput>> readSince(DateTime since, {int limit = 20000}) async {
    if (!isSupported) return const [];
    final rows = await _channel.invokeListMethod>('readInbox', {
      'sinceMillis': since.millisecondsSinceEpoch,
      'limit': limit,
    });
    if (rows == null) {
      throw const FormatException('SMS inbox returned no response');
    }
    return decodeInboxRows(rows);
  }

  static List<RawInput> decodeInboxRows(List> rows) {
    return [
      for (var i = 0; i < rows.length; i++) _decodeRow(rows[i], i),
    ];
  }

  static RawInput _decodeRow(Map<Object?, Object?> row, int index) {
    final id = row['id'];
    final sender = row['address'];
    final body = row['body'];
    final date = row['date'];
    if (id is! String || id.isEmpty ||
        sender is! String || body is! String ||
        date is! int || date < 0) {
      throw FormatException('Invalid SMS inbox row at index $index');
    }
    return RawInput(
      source: SourceKind.sms,
      externalId: id,
      sender: sender,
      body: body,
      receivedAt: DateTime.fromMillisecondsSinceEpoch(date),
    );
  }
}
