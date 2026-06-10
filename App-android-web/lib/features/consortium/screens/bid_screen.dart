import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:katari/core/theme/app_colors.dart';
import 'package:katari/core/theme/app_theme.dart';
import 'package:katari/features/consortium/models/active_contract.dart';
import 'package:katari/core/network/api_service.dart';

class BidScreen extends StatefulWidget {
  final ActiveContract contract;
  final String? subscriptionId;

  const BidScreen({super.key, required this.contract, this.subscriptionId});

  @override
  State<BidScreen> createState() => _BidScreenState();
}

class _BidScreenState extends State<BidScreen> {
  final ApiService _apiService = ApiService();
  double _bidPercentage = 30.0;
  bool _isSubmitting = false;
  int _selectedBidType = 0; // 0 = Livre, 1 = Fixo, 2 = Embutido

  void _submitBid() async {
    if (widget.subscriptionId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Erro: Contrato não sincronizado com o servidor'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    final creditValue = widget.contract.creditValue;
    final effectivePercentage = _getEffectivePercentage();
    final bidValue = creditValue * (effectivePercentage / 100);

    // Determinar tipo de lance
    String bidType = 'FREE';
    if (_selectedBidType == 1) bidType = 'FIXED';
    if (_selectedBidType == 2) bidType = 'FIXED';

    try {
      final result = await _apiService.createBid(
        subscriptionId: widget.subscriptionId!,
        type: bidType,
        percentage: effectivePercentage,
        amount: bidValue,
      );

      if (mounted) {
        setState(() => _isSubmitting = false);

        if (result != null && result['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Lance de ${_getEffectivePercentage().toInt()}% registrado com sucesso!'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            ),
          );
          Navigator.pop(context, true); // Return true to indicate success
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result?['error'] ?? 'Erro ao registrar lance'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Erro de conexão. Verifique sua internet e tente novamente.'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // Get percentage based on bid type
  double _getEffectivePercentage() {
    switch (_selectedBidType) {
      case 0: // Lance Livre - user chooses
        return _bidPercentage;
      case 1: // Lance Fixo - typically 25% (fixed by administrator)
        return 25.0;
      case 2: // Embutido - up to 25% deducted from credit
        return 25.0;
      default:
        return _bidPercentage;
    }
  }

  String _getBidTypeLabel() {
    switch (_selectedBidType) {
      case 0:
        return 'LIVRE';
      case 1:
        return 'FIXO 25%';
      case 2:
        return 'EMBUTIDO 25%';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat =
        NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final creditValue = widget.contract.creditValue;
    final effectivePercentage = _getEffectivePercentage();
    final bidValue = creditValue * (effectivePercentage / 100);
    final installmentsFromBid = widget.contract.nextPaymentAmount > 0
        ? (bidValue / widget.contract.nextPaymentAmount).round()
        : 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ofertar Lance'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Resumo
                Builder(builder: (context) => Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.surface(context),
                    border: Border(bottom: BorderSide(color: AppColors.border(context))),
                    borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(20)),
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(
                                widget.contract.product.imageUrl,
                                width: 60,
                                height: 60,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  width: 60,
                                  height: 60,
                                  color: Colors.grey.shade200,
                                  child: const Icon(Icons.inventory_2, size: 24),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.contract.product.name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16),
                                  ),
                                  const SizedBox(height: 4.5),
                                  Row(
                                    children: [
                                      _buildBadge(
                                          'Grupo ${widget.contract.groupNumber}'),
                                      const SizedBox(width: 8),
                                      _buildBadge(
                                          'Cota ${widget.contract.quotaNumber}'),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Saldo Crédito',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                currencyFormat.format(creditValue),
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.secondaryColor,
                                ),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color:
                                  AppTheme.primaryColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.info_outline,
                                    size: 16, color: AppTheme.primaryColor),
                                SizedBox(width: 6),
                                Text(
                                  'Lance antecipa parcelas',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.primaryColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                )),

                const SizedBox(height: 24),

                // Tipos de Lance
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Selecione a Modalidade',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.secondaryColor,
                        ),
                      ),
                      const SizedBox(height: 16),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        clipBehavior: Clip.none,
                        child: Row(
                          children: [
                            _buildBidTypeCard(0, 'Lance Livre',
                                'Escolha o valor', Icons.edit),
                            const SizedBox(width: 12),
                            _buildBidTypeCard(1, 'Lance Fixo', '25% do crédito',
                                Icons.lock_outline),
                            const SizedBox(width: 12),
                            _buildBidTypeCard(2, 'Embutido',
                                'Até 25% do crédito', Icons.credit_card),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Estatísticas do Grupo
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.blue.shade100),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Icon(Icons.analytics_outlined,
                            color: Colors.blue.shade700, size: 20),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Média de lances do grupo',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.blue.shade800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            RichText(
                              text: TextSpan(
                                children: [
                                  TextSpan(
                                    text:
                                        '--.--%', // TODOFetch real average from API
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue.shade900,
                                      fontFamily:
                                          GoogleFonts.outfit().fontFamily,
                                    ),
                                  ),
                                  TextSpan(
                                    text: ' neste mês',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.blue.shade700,
                                      fontFamily:
                                          GoogleFonts.outfit().fontFamily,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Slider e Valor
                Builder(builder: (context) => Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.surface(context),
                    borderRadius: BorderRadius.circular(20),
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
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Valor do Lance',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '~$installmentsFromBid parcelas',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Badge do tipo de lance
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 6),
                        decoration: BoxDecoration(
                          color: _selectedBidType == 2
                              ? Colors.purple.shade50
                              : _selectedBidType == 1
                                  ? Colors.blue.shade50
                                  : Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _selectedBidType == 2
                                ? Colors.purple.shade200
                                : _selectedBidType == 1
                                    ? Colors.blue.shade200
                                    : Colors.orange.shade200,
                          ),
                        ),
                        child: Text(
                          _getBidTypeLabel(),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: _selectedBidType == 2
                                ? Colors.purple.shade700
                                : _selectedBidType == 1
                                    ? Colors.blue.shade700
                                    : Colors.orange.shade700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '${effectivePercentage.toInt()}%',
                        style: const TextStyle(
                          fontSize: 48,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                      Text(
                        currencyFormat.format(bidValue),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey.shade500,
                        ),
                      ),
                      // Nota especial para Embutido
                      if (_selectedBidType == 2)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'Valor será descontado do seu crédito',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.purple.shade600,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      const SizedBox(height: 24),
                      // Slider apenas para Lance Livre
                      if (_selectedBidType == 0)
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: AppTheme.primaryColor,
                            inactiveTrackColor:
                                AppTheme.primaryColor.withValues(alpha: 0.1),
                            thumbColor: Colors.white,
                            overlayColor:
                                AppTheme.primaryColor.withValues(alpha: 0.2),
                            trackHeight: 6,
                            thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 12, elevation: 4),
                            overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 24),
                          ),
                          child: Slider(
                            value: _bidPercentage,
                            min: 5,
                            max: 50,
                            divisions: 45,
                            onChanged: (value) =>
                                setState(() => _bidPercentage = value),
                          ),
                        )
                      else
                        // Mensagem informativa para tipos fixos
                        Text(
                          _selectedBidType == 1
                              ? 'Percentual fixo de 25%'
                              : 'Até 25% descontado do crédito',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                          ),
                        ),
                    ],
                  ),
                )),

                const SizedBox(height: 24),

                // Disclaimer
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    'Atenção: O valor do lance só será cobrado caso você seja contemplado.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade500,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // Botão de Ação
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _submitBid,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2),
                            )
                          : const Text(
                              'CONFIRMAR OFERTA',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: 1,
                              ),
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
      );
  }

  Widget _buildBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: Colors.grey.shade700,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildBidTypeCard(
      int index, String title, String subtitle, IconData icon) {
    bool isSelected = index == _selectedBidType;
    return GestureDetector(
      onTap: () => setState(() => _selectedBidType = index),
      child: Container(
        width: 140,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryColor : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppTheme.primaryColor : Colors.grey.shade200,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppTheme.primaryColor.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  )
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.white.withValues(alpha: 0.2)
                    : Colors.grey.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: isSelected ? Colors.white : Colors.grey.shade600,
                size: 20,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: isSelected ? Colors.white : AppTheme.secondaryColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                color: isSelected
                    ? Colors.white.withValues(alpha: 0.8)
                    : Colors.grey.shade500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
