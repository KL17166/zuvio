import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:freerasp/freerasp.dart';
import 'package:katari/data/services/storage_service.dart';

/// Provides multi-layer runtime protection:
/// 1. freeRASP — Root/Jailbreak, hooks, emulator, app integrity, debug
/// 2. Screenshot / screen-recording blocking (Android FLAG_SECURE)
/// 3. Real threat enforcement (logout + blocking overlay)
class SecurityService {
  static final SecurityService _instance = SecurityService._internal();
  factory SecurityService() => _instance;
  SecurityService._internal();

  // Global key so we can overlay a blocking screen from anywhere
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  bool _isCompromised = false;
  bool get isCompromised => _isCompromised;

  // ── 1. Initialize RASP ────────────────────────
  Future<void> init() async {
    if (kIsWeb) {
      debugPrint("SecurityService: Skipped on Web (freeRASP is mobile-only)");
      return;
    }

    // Enable screenshot / screen-recording protection on Android
    _enableScreenProtection();

    try {
      final config = TalsecConfig(
        androidConfig: AndroidConfig(
          packageName: 'com.example.katari',
          signingCertHashes: ['51EB5CD2D44FF7DF03159484F31B4AA122EF1414C08540A2FFD62B508D061C'],
        ),
        iosConfig: IOSConfig(
          bundleIds: ['com.example.katari'],
          teamId: 'YOUR_TEAM_ID',
        ),
        watcherMail: 'admin@katariconsorcios.com.br',
        isProd: true,
      );

      final callback = ThreatCallback(
        onAppIntegrity: () => _handleThreat("App Clonado / Modificado"),
        onObfuscationIssues: () => _handleThreat("Obfuscation issues"),
        onDebug: () => _handleThreat("Debugging detectado"),
        onDeviceBinding: () => _handleThreat("Device binding violation"),
        onDeviceID: () => _handleThreat("Device ID spoofing"),
        onHooks: () => _handleThreat("Hooks detectados (Xposed/Frida)"),
        onPasscode: () => debugPrint("SecurityService: Passcode not set"),
        onPrivilegedAccess: () => _handleThreat("Root / Jailbreak detectado"),
        onSecureHardwareNotAvailable: () => debugPrint("SecurityService: Secure hardware unavailable"),
        onSimulator: () => _handleThreat("Emulador detectado"),
        onUnofficialStore: () => _handleThreat("Instalação de loja não oficial"),
      );

      Talsec.instance.attachListener(callback);
      await Talsec.instance.start(config);

      debugPrint("SecurityService (freeRASP): Initialized successfully");
    } catch (e) {
      debugPrint("SecurityService: Error initializing freeRASP: $e");
    }
  }

  // ── 2. Screenshot / Screen-Recording Protection ──
  void _enableScreenProtection() {
    if (kIsWeb) return;

    try {
      // Android: Sets FLAG_SECURE on the window, which:
      //   - Blocks screenshots
      //   - Blocks screen recording
      //   - Shows blank screen in app switcher
      // iOS: Handled by freeRASP's onScreenCapture callback (if available)
      if (Platform.isAndroid) {
        // Use MethodChannel to call native Android API
        const platform = MethodChannel('com.katari/security');
        platform.invokeMethod('enableSecureScreen').catchError((e) {
          debugPrint("SecurityService: Could not enable FLAG_SECURE: $e");
        });
      }
    } catch (e) {
      debugPrint("SecurityService: Screen protection error: $e");
    }
  }

  // ── 3. Threat Handler — Real Enforcement ─────────
  void _handleThreat(String threatType) {
    debugPrint("🔴 SECURITY THREAT: $threatType");
    _isCompromised = true;

    // Force clear tokens (logout)
    StorageService().clearAll();

    // Show a blocking screen that the user cannot dismiss
    final nav = navigatorKey.currentState;
    if (nav != null) {
      nav.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const _SecurityBlockScreen()),
        (route) => false, // Remove all routes
      );
    }
  }
}

// ── Blocking Screen (non-dismissible) ──────────────
class _SecurityBlockScreen extends StatelessWidget {
  const _SecurityBlockScreen();

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // Block back button
      child: Scaffold(
        backgroundColor: const Color(0xFF0D0D0D),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.shield, color: Colors.redAccent, size: 80),
                const SizedBox(height: 24),
                const Text(
                  'Ambiente Inseguro Detectado',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Este aplicativo não pode ser executado em dispositivos com root, '
                  'emuladores, hooks (Xposed/Frida), ou versões modificadas do app.\n\n'
                  'Se você acredita que isto é um erro, desinstale e reinstale '
                  'o aplicativo pela loja oficial.',
                  style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                  ),
                  onPressed: () => SystemNavigator.pop(), // Close app
                  child: const Text('Fechar Aplicativo'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
