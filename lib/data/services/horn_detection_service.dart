import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final hornDetectionServiceProvider = Provider((ref) => HornDetectionService());

class HornDetectionService {
  static const _methodChannel = MethodChannel('com.example.app/horn_control');
  static const _eventChannel = EventChannel('com.example.app/horn_events');

  Stream<Map<String, dynamic>>? _eventStream;

  Future<bool> startDetection({int windowSeconds = 0}) async {
    try {
      final result = await _methodChannel.invokeMethod<bool>(
        'startHornDetection',
        {'windowSeconds': windowSeconds},
      );
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> stopDetection() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('stopHornDetection');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  Stream<Map<String, dynamic>> get events {
    _eventStream ??= _eventChannel.receiveBroadcastStream().map((event) {
      return Map<String, dynamic>.from(event as Map);
    });
    return _eventStream!;
  }
}
