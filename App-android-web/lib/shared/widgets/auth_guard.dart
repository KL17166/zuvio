import 'package:flutter/material.dart';
import 'package:katari/data/services/storage_service.dart';
import 'package:katari/data/services/api_service.dart';
import 'package:katari/core/constants/routes.dart';

/// Guards protected routes by validating the auth token against the server.
/// If the token is missing or invalid/expired, redirects to the login screen
/// and clears the invalid token from storage.
class AuthGuard extends StatefulWidget {
  final Widget child;

  const AuthGuard({super.key, required this.child});

  @override
  State<AuthGuard> createState() => _AuthGuardState();
}

class _AuthGuardState extends State<AuthGuard> {
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    final storageService = StorageService();
    final token = await storageService.getToken();

    if (!mounted) return;

    if (token == null || token.isEmpty) {
      // No token at all — redirect to login
      _redirectToLogin();
      return;
    }

    // Token exists locally — validate it against the server
    final isValid = await ApiService().verifyToken();

    if (!mounted) return;

    if (!isValid) {
      // Token expired or revoked — clear it and redirect
      await storageService.removeToken();
      if (mounted) _redirectToLogin();
    } else {
      setState(() => _checking = false);
    }
  }

  void _redirectToLogin() {
    Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.login, (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }
    return widget.child;
  }
}
