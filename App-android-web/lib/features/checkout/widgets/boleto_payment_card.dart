import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:katari/core/theme/app_theme.dart';

class BoletoPaymentCard extends StatefulWidget {
  final Map<String, dynamic> paymentData;

  const BoletoPaymentCard({
    super.key,
    required this.paymentData,
  });

  @override
  State<BoletoPaymentCard> createState() => _BoletoPaymentCardState();
}

class _BoletoPaymentCardState extends State<BoletoPaymentCard> {
  bool _copied = false;

  String _formatExpirationDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr).toLocal();
      return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
    } catch (e) {
      return dateStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
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
        children: [
          Row(
            children: [
              Icon(Icons.calendar_today, color: Colors.orange.shade700, size: 20),
              const SizedBox(width: 8),
              Text(
                'Vencimento:',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _formatExpirationDate(widget.paymentData['expirationDate'] ?? ''),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.secondaryColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: SelectableText(
              widget.paymentData['barCode'] ??
                  '23793.38128 60047.521843 33000.000001...',
              style: TextStyle(
                fontSize: 14,
                fontFamily: 'monospace',
                color: Colors.grey.shade800,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Clipboard.setData(
                  ClipboardData(text: widget.paymentData['barCode'] ?? ''),
                );
                setState(() => _copied = true);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.white),
                        SizedBox(width: 12),
                        Text('Código copiado com sucesso!'),
                      ],
                    ),
                    backgroundColor: Colors.green.shade600,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                );
                Future.delayed(const Duration(seconds: 2), () {
                  if (mounted) setState(() => _copied = false);
                });
              },
              icon: Icon(_copied ? Icons.check : Icons.copy),
              label: Text(_copied ? 'CÓDIGO COPIADO!' : 'COPIAR CÓDIGO'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _copied ? Colors.green : AppTheme.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
