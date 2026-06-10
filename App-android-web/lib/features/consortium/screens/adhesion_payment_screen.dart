import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:katari/core/theme/app_colors.dart';
import 'package:katari/core/theme/app_theme.dart';
import 'package:katari/features/consortium/models/active_contract.dart';
import 'package:katari/features/consortium/providers/consortium_provider.dart';
import 'package:katari/features/auth/providers/auth_provider.dart';
import 'package:katari/features/checkout/screens/payment_details_screen.dart';
import 'package:katari/features/profile/screens/kyc_retry_screen.dart';

/// Tela dedicada para pagamento da adesão (1ª parcela).
///
/// Exibida quando o consorciado ainda não pagou a adesão, bloqueando
/// o acesso às demais funcionalidades (Pagamentos, Extrato, Leilão).
class AdhesionPaymentScreen extends StatefulWidget {
  final ActiveContract contract;

  const AdhesionPaymentScreen({super.key, required this.contract});

  @override
  State<AdhesionPaymentScreen> createState() => _AdhesionPaymentScreenState();
}

class _AdhesionPaymentScreenState extends State<AdhesionPaymentScreen>
    with SingleTickerProviderStateMixin {
  String _selectedMethod = 'PIX';
  late AnimationController _animController;
  late Animation<double> _fadeIn;

  ActiveContract get contract => widget.contract;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeIn = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat =
        NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final adhesionValue = contract.getInstallmentValue(1);

    return Scaffold(
      backgroundColor: AppColors.background(context),
      appBar: AppBar(
        title: const Text('Pagamento da Adesão'),
        centerTitle: true,
      ),
      body: FadeTransition(
        opacity: _fadeIn,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header: Resumo do contrato ─────────────────────────────
              _buildContractSummaryCard(currencyFormat, adhesionValue),

              const SizedBox(height: 28),

              // ── Título da seção ────────────────────────────────────────
              const Text(
                'Métodos de pagamento',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.secondaryColor,
                ),
              ),

              const SizedBox(height: 16),

              // ── PIX ────────────────────────────────────────────────────
              _buildPaymentMethodCard(
                id: 'PIX',
                icon: Icons.pix,
                iconColor: const Color(0xFF00BDAE),
                title: 'PIX',
                subtitle: 'Aprovação instantânea',
              ),

              const SizedBox(height: 12),

              // ── Boleto ─────────────────────────────────────────────────
              _buildPaymentMethodCard(
                id: 'BOLETO',
                icon: Icons.receipt_long,
                iconColor: AppColors.onSurfaceMed(context),
                title: 'Boleto Bancário',
                subtitle: 'Compensação em até 3 dias úteis',
              ),

              const SizedBox(height: 32),

              // ── Resumo do valor ────────────────────────────────────────
              _buildValueSummaryCard(currencyFormat, adhesionValue),

              const SizedBox(height: 32),

              // ── CTA Button ─────────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () => _handlePayment(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _selectedMethod == 'PIX'
                            ? Icons.pix
                            : Icons.receipt_long,
                        color: Colors.white,
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'PAGAR VIA $_selectedMethod',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // ── Segurança ──────────────────────────────────────────────
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_outline,
                        size: 14, color: AppColors.onSurfaceLow(context)),
                    const SizedBox(width: 6),
                    Text(
                      'Pagamento 100% seguro',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.onSurfaceLow(context),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // WIDGETS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildContractSummaryCard(
      NumberFormat currencyFormat, double adhesionValue) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.primaryColor, Color(0xFFFF8F00)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryColor.withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Badge de status
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.hourglass_top, size: 14, color: Colors.white),
                SizedBox(width: 6),
                Text(
                  'Adesão Pendente',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Produto
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  contract.product.imageUrl,
                  width: 64,
                  height: 48,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 64,
                    height: 48,
                    color: Colors.white24,
                    child: const Icon(Icons.inventory_2, color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      contract.product.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Grupo ${contract.groupNumber} • Cota ${contract.quotaNumber}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Valor da Adesão
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Text(
                  'Valor da Adesão (1ª Parcela)',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  currencyFormat.format(adhesionValue),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentMethodCard({
    required String id,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
  }) {
    final isSelected = _selectedMethod == id;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _selectedMethod = id),
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? AppTheme.primaryColor
                  : AppColors.border(context),
              width: isSelected ? 2.0 : 1.0,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: AppTheme.primaryColor.withValues(alpha: 0.12),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: Row(
            children: [
              // Ícone do método
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppTheme.primaryColor.withValues(alpha: 0.1)
                      : AppColors.surfaceVariant(context),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: isSelected ? AppTheme.primaryColor : iconColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),

              // Texto
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isSelected
                            ? AppTheme.primaryColor
                            : AppColors.onSurface(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.onSurfaceMed(context),
                      ),
                    ),
                  ],
                ),
              ),

              // Radio indicator
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected
                        ? AppTheme.primaryColor
                        : AppColors.borderStrong(context),
                    width: isSelected ? 2.0 : 1.5,
                  ),
                ),
                child: isSelected
                    ? Center(
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildValueSummaryCard(
      NumberFormat currencyFormat, double adhesionValue) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Adesão (1ª Parcela)',
                style: TextStyle(
                  fontSize: 15,
                  color: AppColors.onSurfaceMed(context),
                ),
              ),
              Text(
                currencyFormat.format(adhesionValue),
                style: const TextStyle(
                  fontSize: 15,
                  color: AppTheme.secondaryColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total a pagar',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.secondaryColor,
                ),
              ),
              Text(
                currencyFormat.format(adhesionValue),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ACTIONS
  // ═══════════════════════════════════════════════════════════════════════════

  void _handlePayment(BuildContext context) {
    // Verificar KYC rejeitado
    final auth = context.read<AuthProvider>();
    if (auth.kycStatus == 'REJECTED') {
      _showKycRejectedAlert(context, auth.kycRejectReason);
      return;
    }

    final installmentId = contract.installmentIds[1];
    final installmentToken = contract.installmentTokens[1];

    if (installmentId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Erro: ID da parcela não encontrado. Recarregue os dados.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    _processPayment(context, installmentId, _selectedMethod, installmentToken);
  }

  Future<void> _processPayment(BuildContext context, String installmentId,
      String method, String? idTokenPay) async {
    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final provider = Provider.of<ConsortiumProvider>(context, listen: false);

      if (method == 'PIX') {
        await provider.generatePixForInstallment(installmentId,
            idTokenPay: idTokenPay);
      } else if (method == 'BOLETO') {
        await provider.generateBoletoForInstallment(installmentId,
            idTokenPay: idTokenPay);
      } else {
        throw Exception('Método de pagamento desconhecido: $method');
      }

      if (!context.mounted) return;
      Navigator.pop(context); // Close loading

      // Navigate to PaymentDetailsScreen
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const PaymentDetailsScreen(),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context); // Close loading
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Erro ao gerar pagamento. Tente novamente.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showKycRejectedAlert(BuildContext context, String? reason) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text('Documentos Recusados',
                style: TextStyle(color: Colors.red)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
                'Seu pagamento foi bloqueado temporariamente porque seus documentos não puderam ser validados.'),
            const SizedBox(height: 12),
            Text('Motivo: ${reason ?? 'Ilegível ou inválido'}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            const Text(
                'Por favor, reenvie seus documentos para liberar os pagamentos.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('DEPOIS'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const KycRetryScreen()),
              );
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor),
            child: const Text('REENVIAR AGORA',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
