import 'package:flutter/foundation.dart';
import 'dart:io';

class NetworkUtils {
  static Future<String> getLlmBaseUrl() async {
    const configuredHostIp = String.fromEnvironment('HOST_IP');
    final hostIp = configuredHostIp.isNotEmpty
        ? configuredHostIp
        : !kIsWeb && Platform.isAndroid
        ? '10.0.2.2'
        : '127.0.0.1';
    return 'http://$hostIp:11434';
  }
}
