import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:katari/features/consortium/providers/consortium_provider.dart';
import 'package:katari/core/theme/app_theme.dart';
import 'package:katari/features/checkout/widgets/pix_payment_card.dart';
import 'package:katari/features/checkout/widgets/boleto_payment_card.dart';

class PaymentDetailsScreen extends StatefulWidget {
  const PaymentDetailsScreen({super.key});

  @override
  State<PaymentDetailsScreen> createState() => _PaymentDetailsScreenState();
}

class _PaymentDetailsScreenState extends State<PaymentDetailsScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  Timer? _expirationTimer;
  Timer? _paymentCheckTimer;
  Duration _timeLeft = const Duration(minutes: 30);
  bool _isExpired = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _scaleAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.elasticOut,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeIn,
    );
    _animationController.forward();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _calculateTimeLeft();
      _startExpirationTimer();
      _startPaymentVerification();
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    _expirationTimer?.cancel();
    _paymentCheckTimer?.cancel();
    super.dispose();
  }

  void _startExpirationTimer() {
    _expirationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        if (_timeLeft.inSeconds > 0) {
          _timeLeft -= const Duration(seconds: 1);
        } else {
          timer.cancel();
          _isExpired = true;
          _showExpiredDialog();
        }
      });
    });
  }

  void _startPaymentVerification() {
    _paymentCheckTimer =
        Timer.periodic(const Duration(seconds: 10), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }

      try {
        final provider = context.read<ConsortiumProvider>();
        final paid = await provider.checkPaymentStatus();

        if (paid) {
          timer.cancel();
          _expirationTimer?.cancel();
          if (mounted) _showPaymentConfirmed();
        }
      } catch (e) {
        // Silent error
      }
    });
  }

  void _calculateTimeLeft() {
    final paymentData = context.read<ConsortiumProvider>().paymentData;
    if (paymentData != null && paymentData['expirationDate'] != null) {
      try {
        final expiration =
            DateTime.parse(paymentData['expirationDate']).toLocal();
        final now = DateTime.now();
        final difference = expiration.difference(now);

        if (difference.isNegative) {
          setState(() {
            _timeLeft = Duration.zero;
            _isExpired = true;
          });
        } else {
          setState(() {
            _timeLeft = difference;
            _isExpired = false;
          });
        }
      } catch (e) {
        setState(() => _timeLeft = const Duration(minutes: 30));
      }
    }
  }

  void _showExpiredDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.timer_off_rounded, color: Colors.orange.shade600, size: 32),
            const SizedBox(width: 12),
            const Text('Código Expirado', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          'O código de pagamento expirou. Você pode gerar um novo código ou escolher outro método de pagamento.',
          style: TextStyle(fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('VOLTAR', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _generateNewPixCode();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('GERAR NOVO CÓDIGO', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _generateNewPixCode() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor)),
    );

    try {
      final provider = context.read<ConsortiumProvider>();
      final installmentId = provider.paymentData?['installmentId'];
      final idTokenPay = provider.paymentData?['idTokenPay'];
      if (installmentId != null) {
        await provider.generatePixForInstallment(installmentId, idTokenPay: idTokenPay);
      } else {
        await provider.payFirstInstallment('PIX');
      }

      if (!mounted) return;
      Navigator.pop(context);

      setState(() {
        _isExpired = false;
      });
      _calculateTimeLeft();
      _expirationTimer?.cancel();
      _startExpirationTimer();
      _paymentCheckTimer?.cancel();
      _startPaymentVerification();
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Erro ao gerar novo código. Tente novamente.'),
          backgroundColor: Colors.red.shade600,
        ),
      );
    }
  }

  void _showPaymentConfirmed() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check_circle_rounded,
                color: Colors.green.shade500,
                size: 72,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Pagamento Confirmado!',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: AppTheme.secondaryColor,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Seu pagamento foi identificado com sucesso! Vamos continuar.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pushNamedAndRemoveUntil(
                    context,
                    '/confirmation',
                    (route) => false,
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade500,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  'CONTINUAR',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final paymentData = context.watch<ConsortiumProvider>().paymentData;

    if (paymentData == null) {
      return Scaffold(
        backgroundColor: Colors.grey.shade50,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline_rounded, size: 80, color: Colors.red.shade300),
              const SizedBox(height: 16),
              const Text('Erro ao gerar pagamento', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white),
                child: const Text('VOLTAR'),
              ),
            ],
          ),
        ),
      );
    }

    final isPix = paymentData['type'] == 'PIX';
    final isSandbox = paymentData['provider'] == 'sandbox';
    final primaryColor = isPix ? Colors.teal : Colors.orange;

    if (isSandbox) {
      return Scaffold(
        backgroundColor: Colors.grey.shade50,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: Colors.blue.withValues(alpha: 0.2), blurRadius: 30, spreadRadius: 5),
                    ],
                  ),
                  child: Icon(
                    Icons.hourglass_top_rounded,
                    size: 80,
                    color: Colors.blue.shade600,
                  ),
                ),
                const SizedBox(height: 32),
                const Text(
                  'Pagamento em Análise',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.secondaryColor,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  paymentData['message'] ??
                      'Seu pagamento foi enviado para aprovação manual. Você será notificado assim que for confirmado.',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey.shade600,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pushNamedAndRemoveUntil(context, '/confirmation', (route) => false);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      'IR PARA CONFIRMAÇÃO',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(
          isPix ? 'Pagamento via PIX' : 'Boleto Bancário',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.grey.shade50,
        foregroundColor: AppTheme.secondaryColor,
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // Premium Header with Icon
            FadeTransition(
              opacity: _fadeAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: primaryColor.withValues(alpha: 0.2),
                            blurRadius: 30,
                            spreadRadius: 5,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Icon(
                        isPix ? Icons.pix_rounded : Icons.qr_code_scanner_rounded,
                        size: 64,
                        color: primaryColor.shade600,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      isPix ? 'Escaneie o QR Code' : 'Boleto Gerado',
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.secondaryColor,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isPix
                          ? 'Use o aplicativo do seu banco para pagar'
                          : 'Realize o pagamento até o vencimento',
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),

            // Payment Card (PIX or Boleto)
            FadeTransition(
              opacity: _fadeAnimation,
              child: isPix
                  ? PixPaymentCard(
                      paymentData: paymentData,
                      timeLeft: _timeLeft,
                      isExpired: _isExpired,
                    )
                  : BoletoPaymentCard(
                      paymentData: paymentData,
                    ),
            ),
            const SizedBox(height: 32),

            // Premium Instructions Container
            FadeTransition(
              opacity: _fadeAnimation,
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.help_outline_rounded, color: AppTheme.primaryColor, size: 22),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Como pagar?',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.secondaryColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _buildInstructionStep('1', isPix ? 'Abra o aplicativo do seu banco' : 'Copie a linha digitável do boleto'),
                    _buildInstructionStep('2', isPix ? 'Escolha a opção de pagamento via PIX' : 'Abra seu banco e vá em Pagamentos'),
                    _buildInstructionStep('3', isPix ? 'Escaneie o QR Code ou cole o código' : 'Cole a linha digitável'),
                    _buildInstructionStep('4', isPix ? 'Confirme as informações e o valor' : 'Confirme os dados e finalize'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),

            // Pay Later Button
            FadeTransition(
              opacity: _fadeAnimation,
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pushNamedAndRemoveUntil(context, '/confirmation', (route) => false);
                  },
                  icon: const Icon(Icons.schedule_rounded),
                  label: const Text('PAGAR DEPOIS'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey.shade700,
                    side: BorderSide(color: Colors.grey.shade300, width: 2),
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstructionStep(String number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppTheme.primaryColor, AppTheme.primaryColor.withValues(alpha: 0.8)],
              ),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
