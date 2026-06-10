import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:katari/core/theme/app_colors.dart';
import 'package:katari/core/theme/app_theme.dart';
import 'package:katari/features/consortium/models/active_contract.dart';

class StatementScreen extends StatelessWidget {
  final ActiveContract contract;

  const StatementScreen({super.key, required this.contract});

  @override
  Widget build(BuildContext context) {
    final currencyFormat =
        NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final dateFormat = DateFormat('dd/MM/yyyy');

    final remainingCount = contract.remainingInstallments;
    final progress = contract.progressPercentage / 100;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Extrato'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ─────────────────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.surface(context),
                border: Border(
                    bottom: BorderSide(color: AppColors.border(context))),
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  Text(
                    'Valor Total Pago',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.onSurfaceMed(context),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    currencyFormat.format(contract.totalPaid),
                    style: const TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.secondaryColor,
                      leadingDistribution: TextLeadingDistribution.even,
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Progress Bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 8,
                      backgroundColor: AppColors.border(context),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                          AppTheme.primaryColor),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Summary Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildSummaryItem(
                        'Pagas',
                        '${contract.totalPaymentsCount}',
                        Colors.green,
                        Icons.check_circle_outline,
                      ),
                      Container(
                          width: 1,
                          height: 40,
                          color: AppColors.border(context)),
                      _buildSummaryItem(
                        'Faltam',
                        '$remainingCount',
                        Colors.orange,
                        Icons.hourglass_empty,
                      ),
                      Container(
                          width: 1,
                          height: 40,
                          color: AppColors.border(context)),
                      _buildSummaryItem(
                        'Progresso',
                        '${(progress * 100).toInt()}%',
                        Colors.blue,
                        Icons.analytics_outlined,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── Distribuição ───────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Distribuição',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.secondaryColor,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Builder(
                    builder: (context) => Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppColors.surface(context),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.border(context)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          _buildDistributionRow(
                            'Fundo Comum',
                            currencyFormat.format(contract.commonFundPaid),
                            Colors.green,
                            Icons.savings_outlined,
                          ),
                          const Divider(height: 24),
                          _buildDistributionRow(
                            'Taxa Admin',
                            currencyFormat.format(contract.totalAdminFeePaid),
                            Colors.blue,
                            Icons.admin_panel_settings_outlined,
                          ),
                          const Divider(height: 24),
                          _buildDistributionRow(
                            'Fundo Reserva',
                            currencyFormat.format(contract.totalReserveFundPaid),
                            Colors.orange,
                            Icons.shield_outlined,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── Histórico ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Histórico',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.secondaryColor,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ..._buildPaymentHistory(context, currencyFormat, dateFormat),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem(
      String label, String value, Color color, IconData icon) {
    return Column(
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: color.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }

  Widget _buildDistributionRow(
      String label, String value, Color color, IconData icon) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: AppTheme.secondaryColor,
            ),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppTheme.secondaryColor,
          ),
        ),
      ],
    );
  }

  List<Widget> _buildPaymentHistory(
      BuildContext context,
      NumberFormat currencyFormat,
      DateFormat dateFormat) {
    final List<Map<String, dynamic>> items = [];

    // Adesão — only show as confirmed if actually paid
    if (contract.isAdesaoPaid) {
      items.add({
        'title': 'Adesão Confirmada',
        'description':
            'Grupo ${contract.groupNumber} - Cota ${contract.quotaNumber}',
        'value': currencyFormat.format(contract.getInstallmentValue(1)),
        'date': dateFormat.format(contract.contractDate),
        'isFirst': true,
        'isPaid': true,
      });
    } else {
      items.add({
        'title': 'Adesão Pendente',
        'description':
            'Grupo ${contract.groupNumber} - Cota ${contract.quotaNumber}',
        'value': currencyFormat.format(contract.getInstallmentValue(1)),
        'date': dateFormat.format(contract.contractDate),
        'isFirst': true,
        'isPaid': false,
      });
    }

    // Pagamentos (skip installment 0 since it's adesão)
    final paidNumbers = contract.paidInstallments.where((n) => n > 0).toList()
      ..sort();
    for (final num in paidNumbers) {
      final paymentDate = contract.installmentDueDates[num] ??
          contract.contractDate.add(Duration(days: 30 * num));
      items.add({
        'title': 'Parcela $num',
        'description': 'Pagamento realizado',
        'value': currencyFormat.format(
            contract.installmentValues[num] ?? contract.nextPaymentAmount),
        'date': dateFormat.format(paymentDate),
        'isFirst': false,
        'isPaid': true,
      });
    }

    final reversedItems = items.reversed.toList();

    return List.generate(reversedItems.length, (index) {
      final item = reversedItems[index];
      final isLast = index == reversedItems.length - 1;

      return _buildTimelineItem(
        context: context,
        title: item['title'],
        description: item['description'],
        value: item['value'],
        date: item['date'],
        isFirst: index == 0,
        isLast: isLast,
        isPaid: item['isPaid'] ?? true,
      );
    });
  }

  Widget _buildTimelineItem({
    required BuildContext context,
    required String title,
    required String description,
    required String value,
    required String date,
    required bool isFirst,
    required bool isLast,
    bool isPaid = true,
  }) {
    final Color statusColor = isPaid ? Colors.green : Colors.orange;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 33,
            child: Column(
              children: [
                Container(
                  width: 16,
                  height: 23,
                  decoration: BoxDecoration(
                    color: isFirst
                        ? statusColor
                        : AppColors.surface(context),
                    border: Border.all(
                      color: statusColor,
                      width: 2.5,
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Icon(
                      isPaid ? Icons.check : Icons.hourglass_empty,
                      size: isFirst ? 10 : 8,
                      color: isFirst ? Colors.white : statusColor,
                    ),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: AppColors.border(context),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 24),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.secondaryColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          date,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.onSurfaceMed(context),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          description,
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.onSurfaceLow(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
