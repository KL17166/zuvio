import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceService {
  static final DeviceService _instance = DeviceService._internal();
  factory DeviceService() => _instance;
  DeviceService._internal();

  String? _deviceId;
  String? _deviceModel;
  String? _deviceOS;
  String? _appVersion;

  Future<void> init() async {
    if (_deviceId != null) return;

    try {
      final deviceInfo = DeviceInfoPlugin();
      final packageInfo = await PackageInfo.fromPlatform();
      _appVersion = packageInfo.version;

      if (kIsWeb) {
        final webBrowserInfo = await deviceInfo.webBrowserInfo;
        _deviceId = webBrowserInfo.userAgent ?? 'web-unknown';
        _deviceModel = webBrowserInfo.browserName.name;
        _deviceOS = 'Web';
      } else if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        _deviceId = androidInfo.id; // Unique ID on Android
        _deviceModel = '${androidInfo.manufacturer} ${androidInfo.model}';
        _deviceOS = 'Android ${androidInfo.version.release}';
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        _deviceId = iosInfo.identifierForVendor;
        _deviceModel = iosInfo.utsname.machine;
        _deviceOS = 'iOS ${iosInfo.systemVersion}';
      }

      // Fallback or persist ID if needed using SharedPreferences
      if (_deviceId == null) {
        final prefs = await SharedPreferences.getInstance();
        _deviceId = prefs.getString('secure_device_id');
        if (_deviceId == null) {
          _deviceId =
              DateTime.now().millisecondsSinceEpoch.toString(); // Weak fallback
          await prefs.setString('secure_device_id', _deviceId!);
        }
      }
    } catch (e) {
      debugPrint('Error initializing device info: $e');
      _deviceId = 'unknown';
      _deviceModel = 'unknown';
      _deviceOS = 'unknown';
    }
  }

  Map<String, String> getHeaders() {
    return {
      'X-Device-ID': _deviceId ?? 'unknown',
      'X-Device-Model': _deviceModel ?? 'unknown',
      'X-Device-OS': _deviceOS ?? 'unknown',
      'X-App-Version': _appVersion ?? 'unknown',
    };
  }
}
