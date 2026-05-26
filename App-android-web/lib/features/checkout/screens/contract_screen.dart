import 'dart:io' as io show File;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:katari/features/camera/screens/custom_camera_screen.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:katari/core/theme/app_theme.dart';
import 'package:katari/core/constants/routes.dart';
import 'package:katari/providers/consortium_provider.dart';

class ContractScreen extends StatefulWidget {
  const ContractScreen({super.key});

  @override
  State<ContractScreen> createState() => _ContractScreenState();
}

class _ContractScreenState extends State<ContractScreen> {
  bool _accepted = false;
  final ScrollController _scrollController = ScrollController();
  bool _hasScrolledToBottom = false;

  // Documents
  String? _docFrontPath;
  String? _docBackPath;
  String? _selfiePath;


  // Stable contract identifiers (generated once)
  late final String _contractNumber;
  late final String _groupNumber;

  Future<void> _pickImage(String type) async {
    try {
      CameraCaptureType captureType = CameraCaptureType.documentFront;
      if (type == 'back') captureType = CameraCaptureType.documentBack;
      if (type == 'selfie') captureType = CameraCaptureType.selfie;

      final String? selectedImagePath = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (context) => CustomCameraScreen(captureType: captureType),
        ),
      );

      if (selectedImagePath != null) {
        setState(() {
          if (type == 'front') _docFrontPath = selectedImagePath;
          if (type == 'back') _docBackPath = selectedImagePath;
          if (type == 'selfie') _selfiePath = selectedImagePath;
        });

        // Update provider
        if (mounted) {
          context.read<ConsortiumProvider>().updateDocuments(
                front: type == 'front' ? selectedImagePath : null,
                back: type == 'back' ? selectedImagePath : null,
                selfie: type == 'selfie' ? selectedImagePath : null,
              );
        }
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erro ao abrir câmera')),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_checkScrollPosition);

    // Generate stable contract/group numbers once
    _contractNumber =
        'KT${DateTime.now().year}${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
    _groupNumber =
        '${DateTime.now().year}/${(DateTime.now().month * 7 + 123).toString().padLeft(4, '0')}';

    // Load documents from provider (passed from previous screen)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final provider = context.read<ConsortiumProvider>();
        setState(() {
          _docFrontPath = provider.docFrontPath;
          _docBackPath = provider.docBackPath;
          _selfiePath = provider.selfiePath;
        });
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _checkScrollPosition() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 50) {
      if (!_hasScrolledToBottom) {
        setState(() => _hasScrolledToBottom = true);
      }
    }
  }

  String _formatCurrency(double value) {
    return NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(value);
  }

  String _formatDate(DateTime date) {
    return DateFormat('dd/MM/yyyy').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ConsortiumProvider>();
    final product = provider.selectedProduct;
    final plan = provider.selectedPlan;

    final contractNumber = _contractNumber;
    final groupNumber = _groupNumber;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Contrato de Adesão'),
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.secondaryColor,
        elevation: 0,
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Progress indicator
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.description,
                    color: AppTheme.primaryColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Revise o contrato',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.secondaryColor,
                        ),
                      ),
                      Text(
                        'Leia atentamente antes de aceitar',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header do contrato
                  Center(
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.inventory_2,
                            color: AppTheme.primaryColor,
                            size: 40,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'KATARI CONSÓRCIOS',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.secondaryColor,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'CNPJ: 00.000.000/0001-00',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppTheme.secondaryColor,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'CONTRATO DE ADESÃO AO GRUPO DE CONSÓRCIO',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Dados do Contrato
                  _buildInfoBox(
                    'DADOS DO CONTRATO',
                    Icons.receipt_long,
                    [
                      _buildInfoRow('Nº do Contrato', contractNumber),
                      _buildInfoRow('Grupo', groupNumber),
                      _buildInfoRow(
                          'Data de Emissão', _formatDate(DateTime.now())),
                      _buildInfoRow('Administradora', 'Katari Consórcios S.A.'),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Dados do Consorciado
                  _buildInfoBox(
                    'DADOS DO CONSORCIADO',
                    Icons.person,
                    [
                      _buildInfoRow(
                          'Nome',
                          provider.name.isNotEmpty
                              ? provider.name
                              : 'Não informado'),
                      _buildInfoRow(
                          'CPF',
                          provider.cpf.isNotEmpty
                              ? provider.cpf
                              : 'Não informado'),
                      _buildInfoRow(
                          'Telefone',
                          provider.phone.isNotEmpty
                              ? provider.phone
                              : 'Não informado'),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Dados do Bem
                  if (product != null)
                    _buildInfoBox(
                      'DADOS DO BEM',
                      Icons.inventory_2,
                      [
                        _buildInfoRow('Tipo', product.type.displayName),
                        _buildInfoRow('Modelo', product.name),
                        _buildInfoRow('Categoria', product.categoryDisplayName),
                        _buildInfoRow(
                            'Valor do Crédito', _formatCurrency(product.price)),
                      ],
                    ),

                  const SizedBox(height: 20),

                  if (plan != null && product != null)
                    _buildInfoBox(
                      'CONDIÇÕES DO PLANO',
                      Icons.calendar_month,
                      [
                        _buildInfoRow('Prazo', '${plan.durationMonths} meses'),
                        _buildInfoRow(
                            'Valor do Crédito', _formatCurrency(product.price)),
                        _buildInfoRow('Taxa de Administração',
                            '${plan.adminFeeRate.toStringAsFixed(2)}%'),
                        _buildInfoRow('Fundo de Reserva',
                            '${plan.fundRate.toStringAsFixed(2)}%'),
                        _buildInfoRow('Parcela Mensal (inicial)',
                            _formatCurrency(plan.monthlyInstallment)),
                        _buildInfoRow(
                            'Valor Total Estimado',
                            _formatCurrency(
                                plan.monthlyInstallment * plan.durationMonths)),
                      ],
                    ),

                  const SizedBox(height: 32),
                  const SizedBox(height: 32),
                  const Divider(),
                  const SizedBox(height: 24),

                  // Documentos
                  _buildDocumentSection(),

                  const SizedBox(height: 32),
                  const Divider(),
                  const SizedBox(height: 24),

                  // Cláusulas
                  const Text(
                    'CLÁUSULAS CONTRATUAIS',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.secondaryColor,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 24),

                  _buildClause(
                    '1.',
                    'OBJETO',
                    'O presente instrumento tem por objeto a adesão do CONSORCIADO ao grupo de consórcio administrado pela KATARI CONSÓRCIOS S.A., para aquisição do bem especificado neste contrato, regido pela Lei nº 11.795/2008 e pelas normas do Banco Central do Brasil.',
                  ),

                  _buildClause(
                    '2.',
                    'FORMAÇÃO DO GRUPO',
                    'O grupo de consórcio será formado quando atingir o número mínimo de participantes ativos necessário para sua viabilidade econômica. A ADMINISTRADORA comunicará ao CONSORCIADO a efetiva formação do grupo e a data da primeira assembleia.',
                  ),

                  _buildClause(
                    '3.',
                    'OBRIGAÇÕES DO CONSORCIADO',
                    'O CONSORCIADO obriga-se a:\n\na) Pagar pontualmente as parcelas mensais até o dia de vencimento estabelecido;\n\nb) Manter seus dados cadastrais atualizados junto à ADMINISTRADORA;\n\nc) Comparecer às assembleias ordinárias e extraordinárias quando convocado;\n\nd) Oferecer garantias exigidas quando da contemplação;\n\ne) Cumprir todas as obrigações previstas neste contrato e na legislação aplicável.',
                  ),

                  _buildClause(
                    '4.',
                    'PARCELAS E PAGAMENTO',
                    'As parcelas mensais são compostas por:\n\na) Fundo comum: destinado à contemplação dos participantes;\n\nb) Taxa de administração: remuneração da ADMINISTRADORA pelos serviços prestados (${plan?.adminFeeRate.toStringAsFixed(2) ?? '0'}% sobre o valor do crédito, diluída nas parcelas);\n\nc) Fundo de reserva: destinado a cobrir eventual inadimplência e despesas extraordinárias (${plan?.fundRate.toStringAsFixed(2) ?? '0'}% sobre o valor do crédito);\n\nd) Seguro prestamista: quando aplicável.\n\nO atraso no pagamento acarretará multa de 2% (dois por cento) e juros de mora de 1% (um por cento) ao mês.',
                  ),

                  _buildClause(
                    '5.',
                    'REAJUSTE DAS PARCELAS',
                    'O valor da carta de crédito e, consequentemente, das parcelas vincendas, será reajustado ANUALMENTE, no aniversário da cota, com base na variação da Tabela FIPE para veículos ou índice que a substitua.\n\nO reajuste tem por objetivo manter o poder de compra da carta de crédito ao longo do prazo do consórcio. Caso o índice seja negativo, o valor será mantido. O CONSORCIADO declara estar ciente de que as parcelas poderão sofrer aumentos durante a vigência do contrato.',
                  ),

                  _buildClause(
                    '6.',
                    'CONTEMPLAÇÃO',
                    'A contemplação ocorrerá mensalmente por meio de:\n\na) SORTEIO: realizado nas assembleias ordinárias mensais, mediante extração da Loteria Federal;\n\nb) LANCE: oferta de antecipação de parcelas vincendas. O maior lance ofertado será o contemplado.\n\nO CONSORCIADO contemplado deverá apresentar as garantias exigidas no prazo de 30 (trinta) dias, sob pena de perda da contemplação.',
                  ),

                  _buildClause(
                    '7.',
                    'UTILIZAÇÃO DO CRÉDITO',
                    'O crédito contemplado será utilizado exclusivamente para aquisição do bem descrito neste contrato, através de pagamento direto ao fornecedor escolhido pelo CONSORCIADO, desde que devidamente autorizado pela ADMINISTRADORA.',
                  ),

                  _buildClause(
                    '8.',
                    'ALIENAÇÃO FIDUCIÁRIA',
                    'O bem adquirido ficará alienado fiduciariamente em favor do GRUPO até a quitação integral de todas as obrigações assumidas pelo CONSORCIADO, nos termos da Lei nº 9.514/97.',
                  ),

                  _buildClause(
                    '9.',
                    'EXCLUSÃO E DESISTÊNCIA',
                    'O CONSORCIADO será excluído do grupo nas seguintes hipóteses:\n\na) Inadimplência de 3 (três) parcelas consecutivas ou 4 (quatro) alternadas;\n\nb) Não apresentação de garantias no prazo estipulado;\n\nc) Fraude documental ou declarações falsas.\n\nEm caso de desistência voluntária ou exclusão, o CONSORCIADO participará dos sorteios dos excluídos para restituição dos valores pagos ao fundo comum, deduzidas as penalidades contratuais.',
                  ),

                  _buildClause(
                    '10.',
                    'TRANSFERÊNCIA DE COTA',
                    'O CONSORCIADO poderá transferir sua cota a terceiros, mediante:\n\na) Solicitação formal à ADMINISTRADORA;\n\nb) Aprovação cadastral do cessionário;\n\nc) Pagamento da taxa de transferência de 1% (um por cento) sobre o valor do crédito.',
                  ),

                  _buildClause(
                    '11.',
                    'ENCERRAMENTO DO GRUPO',
                    'O grupo será encerrado após a contemplação de todos os participantes e liquidação de todas as obrigações. Eventuais valores remanescentes no fundo de reserva serão rateados entre os participantes proporcionalmente.',
                  ),

                  _buildClause(
                    '12.',
                    'DISPOSIÇÕES GERAIS',
                    'a) Toda comunicação entre as partes será realizada pelos meios cadastrados (e-mail, telefone ou aplicativo);\n\nb) A ADMINISTRADORA poderá ceder os direitos creditórios deste contrato a terceiros;\n\nc) Este contrato é celebrado em caráter irrevogável e irretratável, obrigando as partes e seus sucessores.',
                  ),

                  _buildClause(
                    '13.',
                    'FORO',
                    'Fica eleito o foro da Comarca de São Paulo/SP para dirimir quaisquer questões oriundas deste contrato, renunciando as partes a qualquer outro, por mais privilegiado que seja.',
                  ),

                  const SizedBox(height: 32),

                  // Aviso Legal
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Icon(Icons.verified, color: Colors.blue.shade700),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'CONTRATO REGULAMENTADO',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Este contrato está em conformidade com a Lei nº 11.795/2008, Circular BACEN nº 3.432/2009 e demais normas aplicáveis ao Sistema de Consórcios.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.blue.shade900,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Assinatura Digital
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'DECLARAÇÃO DE CONCORDÂNCIA',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Declaro que li, compreendi e estou de pleno acordo com todas as cláusulas e condições estabelecidas neste Contrato de Adesão ao Grupo de Consórcio, bem como recebi cópia do mesmo para arquivo pessoal.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade700,
                            height: 1.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'São Paulo, ${_formatDate(DateTime.now())}',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          width: 200,
                          height: 1,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          provider.name.isNotEmpty
                              ? provider.name
                              : 'CONSORCIADO',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'CPF: ${provider.cpf.isNotEmpty ? provider.cpf : '000.000.000-00'}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Bottom actions
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!_hasScrolledToBottom)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.arrow_downward,
                              color: Colors.orange.shade700, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Role até o final para ler todo o contrato',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.orange.shade900,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  InkWell(
                    onTap: _hasScrolledToBottom
                        ? () {
                            setState(() => _accepted = !_accepted);
                          }
                        : null,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _hasScrolledToBottom
                            ? Colors.grey.shade50
                            : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _accepted
                              ? AppTheme.primaryColor
                              : Colors.grey.shade300,
                          width: _accepted ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: _accepted
                                  ? AppTheme.primaryColor
                                  : Colors.white,
                              border: Border.all(
                                color: _accepted
                                    ? AppTheme.primaryColor
                                    : Colors.grey.shade400,
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: _accepted
                                ? const Icon(Icons.check,
                                    color: Colors.white, size: 16)
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Li e aceito todas as cláusulas deste contrato',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                                color: _hasScrolledToBottom
                                    ? Colors.black
                                    : Colors.grey,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: (_accepted && !provider.isLoading)
                          ? () async {
                              final provider =
                                  context.read<ConsortiumProvider>();
                              if (product != null) {
                                try {
                                  await provider.contractProduct(product);
                                  if (context.mounted) {
                                    Navigator.pushNamed(context, AppRoutes.payment);
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                            'Erro ao assinar contrato. Tente novamente.'),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                  }
                                }
                              }
                            }
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        disabledBackgroundColor: Colors.grey.shade300,
                      ),
                      child: provider.isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text(
                              'ASSINAR CONTRATO DIGITALMENTE',
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
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.camera_alt, color: AppTheme.secondaryColor),
            SizedBox(width: 8),
            Text(
              'DOCUMENTAÇÃO',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.secondaryColor,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue.shade100),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blue, size: 20),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Para validar seu contrato, precisamos de fotos legíveis do seu documento e uma selfie.',
                  style: TextStyle(fontSize: 13, color: Colors.blue),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildDocUploadButton('Frente RG/CNH', _docFrontPath, 'front'),
            _buildDocUploadButton('Verso RG/CNH', _docBackPath, 'back'),
            _buildDocUploadButton('Sua Selfie', _selfiePath, 'selfie'),
          ],
        ),
      ],
    );
  }

  Widget _buildDocUploadButton(String label, String? filePath, String type) {
    final hasFile = filePath != null;
    return Column(
      children: [
        InkWell(
          onTap: () => _pickImage(type),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              color: hasFile ? Colors.green.shade50 : Colors.white,
              border: Border.all(
                color: hasFile ? Colors.green : Colors.grey.shade300,
                width: 2,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: !hasFile
                  ? [
                      const BoxShadow(
                        color: Color(0xFFEEEEEE),
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      )
                    ]
                  : null,
              image: hasFile
                  ? DecorationImage(
                      image: kIsWeb
                          ? NetworkImage(filePath) as ImageProvider
                          : FileImage(io.File(filePath)),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: !hasFile
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_a_photo,
                          color: Colors.grey.shade400, size: 28),
                      const SizedBox(height: 4),
                      Text(
                        'Adicionar',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  )
                : Stack(
                    children: [
                      Positioned(
                        right: 4,
                        top: 4,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.edit,
                              color: AppTheme.primaryColor, size: 14),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: hasFile ? Colors.green.shade700 : Colors.grey.shade700,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoBox(String title, IconData icon, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: AppTheme.primaryColor),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.secondaryColor,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClause(String number, String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Center(
                  child: Text(
                    number,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.secondaryColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(left: 40),
            child: Text(
              content,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade800,
                height: 1.6,
              ),
              textAlign: TextAlign.justify,
            ),
          ),
        ],
      ),
    );
  }
}
