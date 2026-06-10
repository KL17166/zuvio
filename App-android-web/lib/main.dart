import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Providers
import 'package:katari/features/auth/providers/auth_provider.dart';
import 'package:katari/features/catalog/providers/product_provider.dart';
import 'package:katari/features/consortium/providers/contract_provider.dart';
import 'package:katari/features/checkout/providers/payment_provider.dart';
import 'package:katari/features/consortium/providers/consortium_provider.dart';

// Utils
import 'package:katari/core/theme/app_theme.dart';
import 'package:katari/core/constants/routes.dart';

// Screens
import 'package:katari/features/auth/screens/login_screen.dart';
import 'package:katari/features/auth/screens/register_screen.dart';
import 'package:katari/features/home/screens/home_screen.dart';
import 'package:katari/features/catalog/screens/catalog_screen.dart';
import 'package:katari/features/catalog/screens/details_screen.dart';
import 'package:katari/features/profile/screens/profile_screen.dart';
import 'package:katari/features/checkout/screens/checkout_screen.dart';
import 'package:katari/features/checkout/screens/contract_screen.dart';
import 'package:katari/features/checkout/screens/payment_screen.dart';
import 'package:katari/features/checkout/screens/payment_details_screen.dart';
import 'package:katari/features/checkout/screens/confirmation_screen.dart';

// Services
import 'package:katari/core/security/security_service.dart';
import 'package:katari/features/auth/widgets/auth_guard.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Start Application Self-Protection (freeRASP)
  await SecurityService().init();

  runApp(const MotoConsorcioApp());
}

class MotoConsorcioApp extends StatelessWidget {
  const MotoConsorcioApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Create focused providers first
    final authProvider = AuthProvider();
    final productProvider = ProductProvider();
    final contractProvider = ContractProvider();
    final paymentProvider = PaymentProvider();

    return MultiProvider(
      providers: [
        // Focused providers (use these in NEW screens)
        ChangeNotifierProvider.value(value: authProvider),
        ChangeNotifierProvider.value(value: productProvider),
        ChangeNotifierProvider.value(value: contractProvider),
        ChangeNotifierProvider.value(value: paymentProvider),

        // Facade (backward compat — existing screens still use this)
        ChangeNotifierProvider(
          create: (_) => ConsortiumProvider(
            authProvider: authProvider,
            productProvider: productProvider,
            contractProvider: contractProvider,
            paymentProvider: paymentProvider,
          ),
        ),
      ],
      child: MaterialApp(
        title: 'Katari',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        themeMode: ThemeMode.light,
        navigatorKey: SecurityService.navigatorKey,
        initialRoute: AppRoutes.login,
        routes: {
          // Public routes
          AppRoutes.login: (context) => const LoginScreen(),
          AppRoutes.register: (context) => const RegisterScreen(),
          // Protected routes (require authentication)
          AppRoutes.home: (context) => const AuthGuard(child: HomeScreen()),
          AppRoutes.catalog: (context) =>
              const AuthGuard(child: CatalogScreen()),
          AppRoutes.details: (context) =>
              const AuthGuard(child: DetailsScreen()),
          AppRoutes.profile: (context) =>
              const AuthGuard(child: ProfileScreen()),
          AppRoutes.checkout: (context) =>
              const AuthGuard(child: CheckoutScreen()),
          AppRoutes.contract: (context) =>
              const AuthGuard(child: ContractScreen()),
          AppRoutes.payment: (context) =>
              const AuthGuard(child: PaymentScreen()),
          AppRoutes.paymentDetails: (context) =>
              const AuthGuard(child: PaymentDetailsScreen()),
          AppRoutes.confirmation: (context) =>
              const AuthGuard(child: ConfirmationScreen()),
        },
      ),
    );
  }
}
