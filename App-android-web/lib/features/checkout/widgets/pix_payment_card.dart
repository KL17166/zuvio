import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';

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

    final isUrgent = widget.timeLeft.inMinutes < 5;
    final primaryColor = isUrgent ? Colors.red : Colors.teal;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: primaryColor.shade100, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white.withValues(alpha: 0.9),
                  primaryColor.shade50.withValues(alpha: 0.5),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              children: [
                // Timer Dinâmico
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: isUrgent ? Colors.red.shade50 : Colors.teal.shade50,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isUrgent ? Icons.timer_off_outlined : Icons.timer_outlined,
                        color: isUrgent ? Colors.red.shade700 : Colors.teal.shade700,
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Expira em: ',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: isUrgent ? Colors.red.shade800 : Colors.teal.shade800,
                        ),
                      ),
                      Text(
                        '${widget.timeLeft.inMinutes}:${(widget.timeLeft.inSeconds % 60).toString().padLeft(2, '0')}',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isUrgent ? Colors.red.shade900 : Colors.teal.shade900,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                
                // QR Code Elevado
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.grey.shade100),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 15,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Container(
                    width: 220,
                    height: 220,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200, width: 1.5),
                    ),
                    child: widget.paymentData['qrCodeBase64'] != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Image.memory(
                              base64Decode(widget.paymentData['qrCodeBase64']),
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return _buildQRError();
                              },
                            ),
                          )
                        : _buildQRPlaceholder(),
                  ),
                ),
                const SizedBox(height: 24),
                
                // Divisor Elegante
                Row(
                  children: [
                    Expanded(child: Divider(color: Colors.grey.shade300)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'Ou copie o código',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade500,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(child: Divider(color: Colors.grey.shade300)),
                  ],
                ),
                const SizedBox(height: 24),
                
                // Campo de Código Copiável
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: SelectableText(
                    widget.paymentData['copyPasteCode'] ??
                        '00020126580014br.gov.bcb.pix...',
                    style: TextStyle(
                      fontSize: 13,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                      letterSpacing: 0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 16),
                
                // Botão de Copiar Animado
                SizedBox(
                  width: double.infinity,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    height: 56,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: LinearGradient(
                        colors: _copied
                            ? [Colors.green.shade400, Colors.green.shade600]
                            : [Colors.teal.shade400, Colors.teal.shade600],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: (_copied ? Colors.green : Colors.teal).withValues(alpha: 0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () {
                          Clipboard.setData(
                            ClipboardData(text: widget.paymentData['copyPasteCode'] ?? ''),
                          );
                          setState(() => _copied = true);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Row(
                                children: [
                                  Icon(Icons.check_circle_outline, color: Colors.white),
                                  SizedBox(width: 12),
                                  Text('Código copiado com sucesso!', style: TextStyle(fontWeight: FontWeight.bold)),
                                ],
                              ),
                              backgroundColor: Colors.green.shade600,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              margin: const EdgeInsets.all(16),
                            ),
                          );
                          Future.delayed(const Duration(seconds: 2), () {
                            if (mounted) setState(() => _copied = false);
                          });
                        },
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(_copied ? Icons.check_circle : Icons.copy_rounded, color: Colors.white),
                            const SizedBox(width: 12),
                            Text(
                              _copied ? 'CÓDIGO COPIADO!' : 'COPIAR CÓDIGO PIX',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQRError() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.qr_code_scanner_rounded, size: 64, color: Colors.grey.shade400),
        const SizedBox(height: 12),
        Text(
          'Erro ao carregar',
          style: TextStyle(fontSize: 14, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _buildQRPlaceholder() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.qr_code_2_rounded, size: 80, color: Colors.grey.shade400),
        const SizedBox(height: 12),
        Text(
          'QR Code Simulado',
          style: TextStyle(
            color: Colors.grey.shade600,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
