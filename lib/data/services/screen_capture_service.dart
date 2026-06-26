import 'package:flutter/services.dart';

class ScreenCaptureService {
  static const MethodChannel _channel = MethodChannel(
    'com.example.app/screen_capture',
  );

  Future<bool> startCaptureMode() async {
    final result = await _channel.invokeMethod<bool>('startCaptureMode');
    return result ?? false;
  }

  Future<bool> stopCaptureMode() async {
    final result = await _channel.invokeMethod<bool>('stopCaptureMode');
    return result ?? false;
  }

  Future<bool> canDrawOverlays() async {
    final result = await _channel.invokeMethod<bool>('canDrawOverlays');
    return result ?? false;
  }

  Future<bool> openOverlaySettings() async {
    final result = await _channel.invokeMethod<bool>('openOverlaySettings');
    return result ?? false;
  }

  Future<String?> consumePendingCapture() async {
    return _channel.invokeMethod<String>('consumePendingCapture');
  }
}
