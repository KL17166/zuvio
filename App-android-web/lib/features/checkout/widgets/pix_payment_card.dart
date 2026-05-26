import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:katari/core/theme/app_theme.dart';

class PixPaymentCard extends StatefulWidget {
  final Map<String, dynamic> paymentData;
  final Duration timeLeft;
  final bool isExpired;

  const PixPaymentCard({
    super.key,
    required this.paymentData,
    required this.timeLeft,
    required this.isExpired,
  });

  @override
  State<PixPaymentCard> createState() => _PixPaymentCardState();
}

class _PixPaymentCardState extends State<PixPaymentCard> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    if (widget.isExpired) return const SizedBox.shrink();

    return Column(
      children: [
        // Timer
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: widget.timeLeft.inMinutes < 5
                ? Colors.red.shade50
                : Colors.orange.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.timeLeft.inMinutes < 5
                  ? Colors.red.shade200
                  : Colors.orange.shade200,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.timer,
                color: widget.timeLeft.inMinutes < 5
                    ? Colors.red.shade700
                    : Colors.orange.shade700,
                size: 24,
              ),
              const SizedBox(width: 12),
              Text(
                'Expira em: ${widget.timeLeft.inMinutes}:${(widget.timeLeft.inSeconds % 60).toString().padLeft(2, '0')}',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: widget.timeLeft.inMinutes < 5
                      ? Colors.red.shade700
                      : Colors.orange.shade700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        // QR Code Box
        Container(
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
              Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade300, width: 2),
                ),
                child: widget.paymentData['qrCodeBase64'] != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.memory(
                          base64Decode(widget.paymentData['qrCodeBase64']),
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.qr_code_2,
                                    size: 80, color: Colors.grey.shade400),
                                const SizedBox(height: 8),
                                const Text('Erro ao carregar QR',
                                    style: TextStyle(fontSize: 12)),
                              ],
                            );
                          },
                        ),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.qr_code_2,
                              size: 120, color: Colors.grey.shade600),
                          const SizedBox(height: 8),
                          Text(
                            'QR Code Simulado',
                            style: TextStyle(
                                color: Colors.grey.shade600, fontSize: 14),
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 24),
              Text(
                'ou copie o código:',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: SelectableText(
                  widget.paymentData['copyPasteCode'] ??
                      '00020126580014br.gov.bcb.pix...',
                  style: TextStyle(
                    fontSize: 12,
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
                      ClipboardData(
                          text: widget.paymentData['copyPasteCode'] ?? ''),
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
                  label: Text(_copied ? 'CÓDIGO COPIADO!' : 'COPIAR CÓDIGO PIX'),
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
        ),
      ],
    );
  }
}
