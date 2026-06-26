import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final smsScamDetectionServiceProvider = Provider(
  (ref) => SmsScamDetectionService(),
);

class SmsScamDetectionService {
  static const _channel = MethodChannel('com.example.app/sms_scam_control');

  Future<bool> setEnabled(bool enabled) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'setSmsScamDetectionEnabled',
        {'enabled': enabled},
      );
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<List<SmsScamDetectionRecord>> getRecords() async {
    final result = await _channel.invokeMethod<String>('getSmsScamRecords');
    if (result == null || result.isEmpty) return [];
    final decoded = jsonDecode(result);
    if (decoded is! List) return [];
    return decoded
        .map(
          (item) => SmsScamDetectionRecord.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList();
  }

  Future<bool> consumeOpenRequest() async {
    final result = await _channel.invokeMethod<bool>(
      'consumeSmsScamOpenRequest',
    );
    return result ?? false;
  }

  Future<bool> deleteRecord(SmsScamDetectionRecord record) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'deleteSmsScamRecord',
        record.toJson(),
      );
      return result ?? false;
    } catch (_) {
      return false;
    }
  }
}

class SmsScamDetectionRecord {
  final String sender;
  final String body;
  final double probability;
  final bool isScam;
  final DateTime detectedAt;

  SmsScamDetectionRecord({
    required this.sender,
    required this.body,
    required this.probability,
    required this.isScam,
    required this.detectedAt,
  });

  factory SmsScamDetectionRecord.fromJson(Map<String, dynamic> json) {
    final timestamp = (json['detectedAt'] as num?)?.toInt() ?? 0;
    return SmsScamDetectionRecord(
      sender: json['sender']?.toString() ?? '',
      body: json['body']?.toString() ?? '',
      probability: (json['probability'] as num?)?.toDouble() ?? 0,
      isScam: json['isScam'] == true,
      detectedAt: DateTime.fromMillisecondsSinceEpoch(timestamp),
    );
  }

  Map<String, dynamic> toJson() => {
        'sender': sender,
        'body': body,
        'probability': probability,
        'isScam': isScam,
        'detectedAt': detectedAt.millisecondsSinceEpoch,
      };
}
