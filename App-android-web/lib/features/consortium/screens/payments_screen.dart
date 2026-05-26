import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:katari/core/theme/app_colors.dart';
import 'package:katari/core/theme/app_theme.dart';
import 'package:katari/data/models/active_contract.dart';
import 'package:katari/providers/consortium_provider.dart';
import 'package:katari/providers/auth_provider.dart';
import 'package:katari/features/checkout/screens/payment_details_screen.dart';
import 'package:katari/features/profile/screens/kyc_retry_screen.dart';
import 'package:katari/features/consortium/screens/adhesion_payment_screen.dart';

class PaymentsScreen extends StatefulWidget {
  final ActiveContract contract;

  const PaymentsScreen({super.key, required this.contract});

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  final ScrollController _scrollController = ScrollController();
  static const double _cardHeight =
      100.0; // Approximate height of each payment card

  @override
  void initState() {
    super.initState();
    // Scroll to pending installment after frame is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToPendingInstallment();
    });
  }

  void _scrollToPendingInstallment() {
    final pendingIndex =
        widget.contract.nextInstallmentIndex - 1; // 0-based index
    if (pendingIndex > 0 && _scrollController.hasClients) {
      // Subtract 1 card height to show pending card at top with some context
      final targetOffset = (pendingIndex - 1.3) * _cardHeight;
      _scrollController.animateTo(
        targetOffset.clamp(0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  ActiveContract get contract => widget.contract;

  @override
  Widget build(BuildContext context) {
    // ── Guard: redirecionar se adesão não foi paga ─────────────────────────
    if (!contract.isAdesaoPaid) {
      return _buildAdhesionGuard(context);
    }

    final currencyFormat =
        NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final dateFormat = DateFormat('dd/MM/yyyy');

    final paidCount = contract.paidInstallmentsCount;
    // Next unpaid installment is the "pending" one
    final currentInstallmentIndex = contract.nextInstallmentIndex;
    // Only verify pending if not all paid
    final hasPending = paidCount < contract.totalInstallments;

    final remainingCount = contract.remainingInstallments;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pagamentos'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Header com resumo
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface(context),
              border: Border(bottom: BorderSide(color: AppColors.border(context))),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildSummaryItem(
                      'Pagas',
                      '$paidCount',
                      Colors.green,
                      Icons.check_circle,
                    ),
                    _buildSummaryItem(
                      'Pendente',
                      hasPending ? '$currentInstallmentIndex' : '-',
                      Colors.orange,
                      Icons.schedule,
                    ),
                    _buildSummaryItem(
                      'Restantes',
                      '$remainingCount',
                      Colors.grey,
                      Icons.hourglass_empty,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Divider(height: 1),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.event_available,
                        color: Colors.green, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      hasPending
                          ? 'Próxima: ${dateFormat.format(contract.dueDate)}'
                          : '✓ Contrato Quitado',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color:
                            hasPending ? AppTheme.secondaryColor : Colors.green,
                      ),
                    ),
                    if (hasPending) ...[
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          currencyFormat.format(contract.nextPaymentAmount),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          // Informações do consórcio
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: _buildInfoCard(
                    'Grupo',
                    contract.groupNumber,
                    Icons.groups,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildInfoCard(
                    'Cota',
                    contract.quotaNumber,
                    Icons.confirmation_number,
                  ),
                ),
              ],
            ),
          ),
          // Lista de parcelas
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: contract.totalInstallments,
              itemBuilder: (context, index) {
                final installmentNumber = index + 1;
                final isPaid =
                    contract.paidInstallments.contains(installmentNumber);
                final isCurrent =
                    !isPaid && installmentNumber == currentInstallmentIndex;
                final isFuture =
                    !isPaid && installmentNumber > currentInstallmentIndex;

                // Use real due date from API, or fall back to calendar months
                final dueDate =
                    contract.installmentDueDates[installmentNumber] ??
                        DateTime(
                          contract.contractDate.year,
                          contract.contractDate.month + installmentNumber,
                          contract.contractDate.day,
                        );

                // Calculate actual value with discount if future
                final payableAmount =
                    contract.getInstallmentValue(installmentNumber);

                return _buildPaymentCard(
                  context,
                  installmentNumber,
                  payableAmount,
                  dueDate,
                  isPaid,
                  isCurrent,
                  isFuture,
                  currencyFormat,
                  dateFormat,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(String label, String value, IconData icon) {
    return Builder(builder: (context) => Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.primaryColor, size: 20),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 11, color: AppColors.onSurfaceLow(context)),
              ),
              Text(
                value,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.onSurface(context)),
              ),
            ],
          ),
        ],
      ),
    ));
  }

  Widget _buildSummaryItem(
      String label, String value, Color color, IconData icon) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: AppColors.onSurfaceMed(context),
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentCard(
    BuildContext context,
    int installment,
    double amount,
    DateTime dueDate,
    bool isPaid,
    bool isCurrent,
    bool isFuture,
    NumberFormat currencyFormat,
    DateFormat dateFormat,
  ) {
    Color statusColor;
    IconData statusIcon;
    String statusText;

    if (isPaid) {
      statusColor = Colors.green;
      statusIcon = Icons.check_circle;
      statusText = 'Pago';
    } else if (isCurrent) {
      statusColor = Colors.orange;
      statusIcon = Icons.schedule;
      statusText = 'Pendente';
    } else {
      statusColor = Colors.blue; // Azul para futuras disponíveis
      statusIcon = Icons.calendar_today;
      statusText = 'Antecipar';
    }

    // Se estiver atrasada (logica simples baseada na pendente)
    // Na verdade 'isCurrent' já indica a bola da vez.

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isPaid
            ? null
            : () => _showPaymentModal(
                context, installment, amount, isFuture, currencyFormat),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface(context),
            borderRadius: BorderRadius.circular(12),
            border: isCurrent
                ? Border.all(color: AppTheme.primaryColor, width: 2)
                : Border.all(color: AppColors.border(context)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 5,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    '$installment',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      installment == 1
                          ? 'Adesão (1ª Parcela)'
                          : 'Parcela $installment de ${contract.totalInstallments}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Venc: ${dateFormat.format(dueDate)}',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.onSurfaceMed(context),
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    currencyFormat.format(amount),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 14, color: statusColor),
                      const SizedBox(width: 4),
                      Text(
                        statusText,
                        style: TextStyle(
                          fontSize: 12,
                          color: statusColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPaymentModal(BuildContext context, int installment,
      double payableAmount, bool isFuture, NumberFormat currencyFormat) {
    
    // VERIFICAR KYC REJEITADO
    final auth = context.read<AuthProvider>();
    if (auth.kycStatus == 'REJECTED') {
      _showKycRejectedAlert(context, auth.kycRejectReason);
      return;
    }

    // Calculando desconto para exibição
    final originalAmount = contract.nextPaymentAmount;
    final discount = originalAmount - payableAmount;
    String selectedMethod = 'PIX';

    // Look up the installment ID and token from the contract model
    final installmentId = contract.installmentIds[installment];
    final installmentToken = contract.installmentTokens[installment];

    showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => StatefulBuilder(
              builder: (ctx, setModalState) => Container(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isFuture
                          ? 'Antecipar Parcela $installment'
                          : 'Pagar Parcela $installment',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.secondaryColor,
                      ),
                    ),
                    const SizedBox(height: 24),
                    _buildDetailRow('Valor Original',
                        currencyFormat.format(originalAmount)),
                    if (discount > 0.01) // Show discount only if significant
                      _buildDetailRow('Desconto (Amortização)',
                          '- ${currencyFormat.format(discount)}',
                          color: Colors.green),
                    const Divider(height: 32),
                    _buildDetailRow(
                        'Total a Pagar', currencyFormat.format(payableAmount),
                        isBold: true, fontSize: 20),
                    const SizedBox(height: 32),

                    // Split button: main pay + dropdown arrow
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: Row(
                        children: [
                          // Main button
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: installmentId == null
                                  ? null
                                  : () async {
                                      Navigator.pop(ctx); // Close modal
                                      _processPayment(context, installmentId,
                                          selectedMethod, installmentToken);
                                    },
                              icon: Icon(selectedMethod == 'PIX'
                                  ? Icons.pix
                                  : Icons.receipt_long),
                              label: Text(
                                'Pagar via $selectedMethod',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryColor,
                                shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.only(
                                    topLeft: Radius.circular(10),
                                    bottomLeft: Radius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          // Dropdown arrow
                          Container(
                            height: 50,
                            decoration: BoxDecoration(
                              color:
                                  AppTheme.primaryColor.withValues(alpha: 0.85),
                              borderRadius: const BorderRadius.only(
                                topRight: Radius.circular(10),
                                bottomRight: Radius.circular(10),
                              ),
                            ),
                            child: PopupMenuButton<String>(
                              onSelected: (method) {
                                setModalState(() => selectedMethod = method);
                              },
                              icon: const Icon(Icons.arrow_drop_down,
                                  color: Colors.white),
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'PIX',
                                  child: Row(
                                    children: [
                                      Icon(Icons.pix, size: 20),
                                      SizedBox(width: 12),
                                      Text('PIX'),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'BOLETO',
                                  child: Row(
                                    children: [
                                      Icon(Icons.receipt_long, size: 20),
                                      SizedBox(width: 12),
                                      Text('Boleto'),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    if (installmentId == null) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Erro: ID da parcela não encontrado. Recarregue os dados.',
                        style:
                            TextStyle(color: Colors.red.shade600, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
            ));
  }

  Future<void> _processPayment(
      BuildContext context, String installmentId, String method, String? idTokenPay) async {
    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final provider = Provider.of<ConsortiumProvider>(context, listen: false);

      if (method == 'PIX') {
        await provider.generatePixForInstallment(installmentId, idTokenPay: idTokenPay);
      } else if (method == 'BOLETO') {
        await provider.generateBoletoForInstallment(installmentId, idTokenPay: idTokenPay);
      } else {
        throw Exception('Método de pagamento desconhecido: \$method');
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

  Widget _buildDetailRow(String label, String value,
      {Color? color, bool isBold = false, double fontSize = 16}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 16,
              color: AppColors.onSurfaceMed(context),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: color ?? AppTheme.secondaryColor,
            ),
          ),
        ],
      ),
    );
  }

  void _showKycRejectedAlert(BuildContext context, String? reason) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text('Documentos Recusados', style: TextStyle(color: Colors.red)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Seu pagamento foi bloqueado temporariamente porque seus documentos não puderam ser validados.'),
            const SizedBox(height: 12),
            Text('Motivo: ${reason ?? 'Ilegível ou inválido'}', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            const Text('Por favor, reenvie seus documentos para liberar os pagamentos.'),
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
                MaterialPageRoute(builder: (_) => const KycRetryScreen()), // We need to import this
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor),
            child: const Text('REENVIAR AGORA', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  /// Tela de bloqueio quando a adesão não foi paga — guard de segurança.
  Widget _buildAdhesionGuard(BuildContext context) {
    final currencyFormat =
        NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pagamentos'),
        centerTitle: true,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Ícone de cadeado
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.lock_outline_rounded,
                  size: 64,
                  color: Colors.orange.shade600,
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'Funcionalidade Bloqueada',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.secondaryColor,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Para acessar seus pagamentos, é necessário pagar a adesão (1ª parcela) do consórcio.',
                style: TextStyle(
                  fontSize: 15,
                  color: AppColors.onSurfaceMed(context),
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                currencyFormat.format(contract.getInstallmentValue(1)),
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryColor,
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            AdhesionPaymentScreen(contract: contract),
                      ),
                    );
                  },
                  icon: const Icon(Icons.payment, size: 20),
                  label: const Text(
                    'PAGAR ADESÃO AGORA',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
