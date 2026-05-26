import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:katari/providers/consortium_provider.dart';
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

  // ✅ NOVO: Timer de expiração
  Timer? _expirationTimer;
  Timer? _paymentCheckTimer;
  Duration _timeLeft = const Duration(minutes: 30);
  bool _isExpired = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scaleAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.elasticOut,
    );
    _animationController.forward();

    // ✅ NOVO: Calcula tempo restante real e inicia timers
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

  // ✅ NOVO: Timer de expiração
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

  // ✅ NOVO: Verificação automática de pagamento
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
        // Erro silencioso, continua verificando
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
        // Fallback para 30 min se der erro no parse
        setState(() => _timeLeft = const Duration(minutes: 30));
      }
    }
  }

  // ✅ NOVO: Dialog de expiração
  void _showExpiredDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.timer_off, color: Colors.orange, size: 32),
            SizedBox(width: 12),
            Text('Código Expirado'),
          ],
        ),
        content: const Text(
          'O código PIX expirou. Você pode gerar um novo código ou escolher outro método de pagamento.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Fecha dialog
              Navigator.pop(context); // Volta para payment_screen
            },
            child: const Text('VOLTAR'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context); // Fecha dialog
              _generateNewPixCode();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
            ),
            child: const Text('GERAR NOVO CÓDIGO'),
          ),
        ],
      ),
    );
  }

  Future<void> _generateNewPixCode() async {
    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final provider = context.read<ConsortiumProvider>();
      // Use the stored installmentId from the original payment generation
      final installmentId = provider.paymentData?['installmentId'];
      final idTokenPay = provider.paymentData?['idTokenPay'];
      if (installmentId != null) {
        await provider.generatePixForInstallment(installmentId, idTokenPay: idTokenPay);
      } else {
        // Fallback to first installment if no ID stored
        await provider.payFirstInstallment('PIX');
      }

      if (!mounted) return;
      Navigator.pop(context); // Close loading

      // Reset state
      setState(() {
        _isExpired = false;
      });
      _calculateTimeLeft();
      _expirationTimer?.cancel(); // Cancel old timer before starting new
      _startExpirationTimer();
      _paymentCheckTimer?.cancel(); // Cancel old timer before starting new
      _startPaymentVerification();
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // Close loading
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Erro ao gerar novo código. Tente novamente.')),
      );
    }
  }

  // ✅ NOVO: Dialog de pagamento confirmado
  void _showPaymentConfirmed() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check_circle,
                color: Colors.green.shade600,
                size: 64,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Pagamento Confirmado!',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Seu pagamento foi identificado com sucesso!',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15),
            ),
          ],
        ),
        actions: [
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
                backgroundColor: Colors.green.shade600,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'CONTINUAR',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final paymentData = context.watch<ConsortiumProvider>().paymentData;

    if (paymentData == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              const Text('Erro ao gerar pagamento'),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('VOLTAR'),
              ),
            ],
          ),
        ),
      );
    }

    final isPix = paymentData['type'] == 'PIX';
    final isSandbox = paymentData['provider'] == 'sandbox';

    if (isSandbox) {
      return Scaffold(
        backgroundColor: Colors.grey.shade50,
        appBar: AppBar(
          title: const Text('Processando Pagamento'),
          backgroundColor: Colors.white,
          foregroundColor: AppTheme.secondaryColor,
          elevation: 0,
          centerTitle: true,
          automaticallyImplyLeading: false, // Prevent back for now or handle it?
        ),
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
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
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
                      Navigator.pushNamedAndRemoveUntil(
                        context,
                        '/confirmation', // Go to confirmation/home
                        (route) => false,
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'VOLTAR AO INÍCIO',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
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
        title: Text(isPix ? 'Pagamento via PIX' : 'Boleto Bancário'),
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.secondaryColor,
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // Header com ícone animado
            ScaleTransition(
              scale: _scaleAnimation,
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isPix
                        ? [Colors.teal.shade400, Colors.teal.shade600]
                        : [Colors.orange.shade400, Colors.orange.shade600],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: (isPix ? Colors.teal : Colors.orange)
                          .withValues(alpha: 0.3),
                      blurRadius: 15,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Icon(
                        isPix ? Icons.pix : Icons.qr_code_scanner,
                        size: 60,
                        color: isPix
                            ? Colors.teal.shade600
                            : Colors.orange.shade600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      isPix ? 'Escaneie o QR Code' : 'Boleto Gerado',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isPix
                          ? 'Use o app do seu banco'
                          : 'Pague até o vencimento',
                      style: const TextStyle(
                        fontSize: 15,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Timer e QR Code (PIX)
            if (isPix)
              PixPaymentCard(
                paymentData: paymentData,
                timeLeft: _timeLeft,
                isExpired: _isExpired,
              ),

            // Boleto
            if (!isPix)
              BoletoPaymentCard(
                paymentData: paymentData,
              ),
            const SizedBox(height: 24),
            // Instruções
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
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
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.help_outline,
                            color: Colors.blue.shade700, size: 20),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Como pagar',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.secondaryColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildInstructionStep(
                      '1',
                      isPix
                          ? 'Abra o app do seu banco'
                          : 'Copie a linha digitável'),
                  _buildInstructionStep(
                      '2',
                      isPix
                          ? 'Escolha a opção PIX'
                          : 'Cole no app do seu banco'),
                  _buildInstructionStep(
                      '3',
                      isPix
                          ? 'Escaneie o QR Code ou cole o código'
                          : 'Confirme o pagamento'),
                  _buildInstructionStep('4',
                      isPix ? 'Confirme o pagamento' : 'Guarde o comprovante'),
                ],
              ),
            ),
            const SizedBox(height: 32),
            // Botão pagar depois
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
                  backgroundColor: Colors.blueGrey.shade600,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.schedule, size: 24),
                    SizedBox(width: 12),
                    Text(
                      'PAGAR DEPOIS',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
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
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryColor,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 15,
                color: Colors.grey.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
