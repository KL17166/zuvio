import 'dart:io' as io show File;
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:katari/providers/consortium_provider.dart';
import 'package:katari/core/theme/app_theme.dart';
import 'package:katari/core/constants/routes.dart';
import 'package:katari/features/camera/screens/custom_camera_screen.dart';

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  int _currentStep = 0;
  final _formKey = GlobalKey<FormState>();
  bool _isLoadingCEP = false;
  bool _isPickingImage = false;

  // Controllers
  final _nameController = TextEditingController();
  final _cpfController = TextEditingController();
  final _birthDateController = TextEditingController();
  final _phoneController = TextEditingController();

  final _cepController = TextEditingController();
  final _streetController = TextEditingController();
  final _numberController = TextEditingController();
  final _districtController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();

  // FocusNodes for field navigation
  final _nameFocus = FocusNode();
  final _cpfFocus = FocusNode();
  final _birthDateFocus = FocusNode();
  final _phoneFocus = FocusNode();

  final _cepFocus = FocusNode();
  final _streetFocus = FocusNode();
  final _numberFocus = FocusNode();
  final _districtFocus = FocusNode();
  final _cityFocus = FocusNode();
  final _stateFocus = FocusNode();

  // Formatters
  final _cpfFormatter = MaskTextInputFormatter(
    mask: '###.###.###-##',
    filter: {"#": RegExp(r'[0-9]')},
  );
  final _dateFormatter = MaskTextInputFormatter(
    mask: '##/##/####',
    filter: {"#": RegExp(r'[0-9]')},
  );
  final _phoneFormatter = MaskTextInputFormatter(
    mask: '(##) #####-####',
    filter: {"#": RegExp(r'[0-9]')},
  );
  final _cepFormatter = MaskTextInputFormatter(
    mask: '#####-###',
    filter: {"#": RegExp(r'[0-9]')},
  );

  // Images

  XFile? _docFront;
  XFile? _docBack;
  XFile? _selfie;

  @override
  void initState() {
    super.initState();
    // Listener para buscar CEP automaticamente
    _cepController.addListener(_onCEPChanged);

    // Preencher dados do usuário (Read-Only)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<ConsortiumProvider>();
      setState(() {
        _nameController.text = provider.name;
        _cpfController.text = provider.cpf;

        // Formatar data (ISO -> DD/MM/AAAA)
        try {
          if (provider.birthDate.isNotEmpty) {
            final date = DateTime.parse(provider.birthDate);
            _birthDateController.text =
                '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
          }
        } catch (_) {
          _birthDateController.text = provider.birthDate;
        }

        _phoneController.text = provider.phone;

        // Preencher endereço também (Editável)
        _cepController.text = provider.cep;
        _streetController.text = provider.street;
        _numberController.text = provider.number;
        _districtController.text = provider.district;
        _cityController.text = provider.city;
        _stateController.text = provider.state;
      });
    });
  }

  @override
  void dispose() {
    _cepController.removeListener(_onCEPChanged);
    _nameController.dispose();
    _cpfController.dispose();
    _birthDateController.dispose();
    _phoneController.dispose();
    _cepController.dispose();
    _streetController.dispose();
    _numberController.dispose();
    _districtController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _nameFocus.dispose();
    _cpfFocus.dispose();
    _birthDateFocus.dispose();
    _phoneFocus.dispose();
    _cepFocus.dispose();
    _streetFocus.dispose();
    _numberFocus.dispose();
    _districtFocus.dispose();
    _cityFocus.dispose();
    _stateFocus.dispose();
    super.dispose();
  }

  // ========== NOVAS VALIDAÇÕES ==========

  /// Valida CPF segundo algoritmo oficial
  bool _isValidCPF(String cpf) {
    cpf = cpf.replaceAll(RegExp(r'[^\d]'), '');

    if (cpf.length != 11) return false;

    // Verifica se todos os dígitos são iguais (ex: 111.111.111-11)
    if (RegExp(r'^(\d)\1{10}$').hasMatch(cpf)) return false;

    // Calcula primeiro dígito verificador
    int sum = 0;
    for (int i = 0; i < 9; i++) {
      sum += int.parse(cpf[i]) * (10 - i);
    }
    int firstDigit = (sum * 10) % 11;
    if (firstDigit == 10) firstDigit = 0;
    if (firstDigit != int.parse(cpf[9])) return false;

    // Calcula segundo dígito verificador
    sum = 0;
    for (int i = 0; i < 10; i++) {
      sum += int.parse(cpf[i]) * (11 - i);
    }
    int secondDigit = (sum * 10) % 11;
    if (secondDigit == 10) secondDigit = 0;
    if (secondDigit != int.parse(cpf[10])) return false;

    return true;
  }

  /// Valida data de nascimento (não pode ser futura, idade mínima 18 anos)
  bool _isValidBirthDate(String date) {
    try {
      final parts = date.split('/');
      if (parts.length != 3) return false;

      final day = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      final year = int.parse(parts[2]);

      final birthDate = DateTime(year, month, day);
      final now = DateTime.now();

      // Não pode ser futura
      if (birthDate.isAfter(now)) return false;

      // Calcula idade
      int age = now.year - birthDate.year;
      if (now.month < birthDate.month ||
          (now.month == birthDate.month && now.day < birthDate.day)) {
        age--;
      }

      // Mínimo 18 anos
      if (age < 18) return false;

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Busca endereço na API ViaCEP
  void _onCEPChanged() {
    final cep = _cepController.text.replaceAll(RegExp(r'[^\d]'), '');
    if (cep.length == 8 && !_isLoadingCEP) {
      _fetchAddressFromCEP(cep);
    }
  }

  Future<void> _fetchAddressFromCEP(String cep) async {
    setState(() => _isLoadingCEP = true);

    try {
      final response = await http.get(
        Uri.parse('https://viacep.com.br/ws/$cep/json/'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['erro'] == null) {
          setState(() {
            _streetController.text = data['logradouro'] ?? '';
            _districtController.text = data['bairro'] ?? '';
            _cityController.text = data['localidade'] ?? '';
            _stateController.text = data['uf'] ?? '';
          });

          // Foca no campo de número
          Future.delayed(const Duration(milliseconds: 100), () {
            _numberFocus.requestFocus();
          });

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.white),
                    SizedBox(width: 12),
                    Text('Endereço encontrado!'),
                  ],
                ),
                backgroundColor: Colors.green.shade600,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                duration: const Duration(seconds: 2),
              ),
            );
          }
        } else {
          _showError('CEP não encontrado');
        }
      }
    } catch (e) {
      _showError('Erro ao buscar CEP. Verifique sua conexão.');
    } finally {
      setState(() => _isLoadingCEP = false);
    }
  }

  // ========== FIM DAS NOVAS VALIDAÇÕES ==========

  Future<void> _pickImage(String type) async {
    if (_isPickingImage) return;
    setState(() => _isPickingImage = true);

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
        final image = XFile(selectedImagePath);
        setState(() {
          if (type == 'front') _docFront = image;
          if (type == 'back') _docBack = image;
          if (type == 'selfie') _selfie = image;
        });

        if (mounted) {
          context.read<ConsortiumProvider>().updateDocuments(
                front: type == 'front' ? image.path : null,
                back: type == 'back' ? image.path : null,
                selfie: type == 'selfie' ? image.path : null,
              );
        }
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
    } finally {
      if (mounted) {
        setState(() => _isPickingImage = false);
      }
    }
  }

  bool _validateCurrentStep() {
    if (_currentStep == 0) {
      // Validar nome
      if (_nameController.text.trim().isEmpty) {
        _showError('Nome completo é obrigatório');
        return false;
      }

      // Validar CPF
      if (!_isValidCPF(_cpfController.text)) {
        _showError('CPF inválido');
        return false;
      }

      // Validar data de nascimento
      if (!_isValidBirthDate(_birthDateController.text)) {
        _showError('Data de nascimento inválida ou idade menor que 18 anos');
        return false;
      }

      // Validar telefone
      if (_phoneController.text.replaceAll(RegExp(r'[^\d]'), '').length < 11) {
        _showError('Telefone inválido');
        return false;
      }

      return true;
    } else if (_currentStep == 1) {
      if (_cepController.text.length != 9) {
        _showError('CEP inválido');
        return false;
      }
      if (_streetController.text.isEmpty) {
        _showError('Rua é obrigatória');
        return false;
      }
      if (_numberController.text.isEmpty) {
        _showError('Número é obrigatório');
        return false;
      }
      if (_districtController.text.isEmpty) {
        _showError('Bairro é obrigatório');
        return false;
      }
      if (_cityController.text.isEmpty) {
        _showError('Cidade é obrigatória');
        return false;
      }
      if (_stateController.text.isEmpty) {
        _showError('Estado é obrigatório');
        return false;
      }
      return true;
    } else if (_currentStep == 2) {
      return _docFront != null && _docBack != null && _selfie != null;
    }
    return false;
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _continue() {
    if (!_validateCurrentStep()) {
      return;
    }

    if (_currentStep < 2) {
      setState(() => _currentStep += 1);
    } else {
      context.read<ConsortiumProvider>().updateUserData(
            name: _nameController.text,
            cpf: _cpfController.text,
            birthDate: _birthDateController.text,
            phone: _phoneController.text,
          );
      context.read<ConsortiumProvider>().updateAddressData(
            cep: _cepController.text,
            street: _streetController.text,
            number: _numberController.text,
            district: _districtController.text,
            city: _cityController.text,
            state: _stateController.text,
          );
      context.read<ConsortiumProvider>().updateDocuments(
            front: _docFront?.path,
            back: _docBack?.path,
            selfie: _selfie?.path,
          );
      Navigator.pushNamed(context, AppRoutes.contract);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Contratação'),
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.secondaryColor,
        elevation: 0,
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Indicador de progresso
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Row(
              children: [
                _buildStepIndicator(0, 'Pessoal', Icons.person_outline),
                _buildStepLine(0),
                _buildStepIndicator(1, 'Endereço', Icons.location_on_outlined),
                _buildStepLine(1),
                _buildStepIndicator(2, 'Documentos', Icons.camera_alt_outlined),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final bottomInset = MediaQuery.of(context).viewInsets.bottom;
                return SingleChildScrollView(
                  padding: EdgeInsets.only(
                    left: 24,
                    right: 24,
                    top: 24,
                    bottom: bottomInset > 0 ? bottomInset + 24 : 24,
                  ),
                  child: Form(
                    key: _formKey,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: _currentStep == 0
                          ? _buildPersonalDataStep()
                          : _currentStep == 1
                              ? _buildAddressStep()
                              : _buildDocumentsStep(),
                    ),
                  ),
                );
              },
            ),
          ),
          // Botões
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  if (_currentStep > 0)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => setState(() => _currentStep -= 1),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          side: const BorderSide(color: AppTheme.primaryColor),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'VOLTAR',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  if (_currentStep > 0) const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _continue,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        _currentStep < 2 ? 'CONTINUAR' : 'FINALIZAR',
                        style: const TextStyle(
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
        ],
      ),
    );
  }

  Widget _buildStepIndicator(int step, String label, IconData icon) {
    final isActive = _currentStep >= step;
    return Expanded(
      child: Column(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: isActive ? AppTheme.primaryColor : Colors.grey.shade200,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: isActive ? Colors.white : Colors.grey.shade400,
              size: 24,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              color: isActive ? AppTheme.primaryColor : Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepLine(int step) {
    final isCompleted = _currentStep > step;
    return Expanded(
      child: Container(
        height: 2,
        margin: const EdgeInsets.only(bottom: 35),
        color: isCompleted ? AppTheme.primaryColor : Colors.grey.shade300,
      ),
    );
  }

  Widget _buildPersonalDataStep() {
    return Container(
      key: const ValueKey('personal'),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Dados Pessoais',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppTheme.secondaryColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Preencha seus dados para continuar',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 24),
          _buildTextField(
            controller: _nameController,
            label: 'Nome Completo',
            hint: 'Digite seu nome completo',
            icon: Icons.person_outline,
            focusNode: _nameFocus,
            nextFocus: _cpfFocus,
            keyboardType: TextInputType.name,
            enabled: false,
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _cpfController,
            label: 'CPF',
            hint: '000.000.000-00',
            icon: Icons.badge_outlined,
            inputFormatters: [_cpfFormatter],
            keyboardType: TextInputType.number,
            focusNode: _cpfFocus,
            nextFocus: _birthDateFocus,
            enabled: false,
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _birthDateController,
            label: 'Data de Nascimento',
            hint: 'DD/MM/AAAA',
            icon: Icons.calendar_today_outlined,
            inputFormatters: [_dateFormatter],
            keyboardType: TextInputType.number,
            focusNode: _birthDateFocus,
            nextFocus: _phoneFocus,
            enabled: false, // Bloqueia edição pois vem do perfil
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _phoneController,
            label: 'Telefone',
            hint: '(00) 00000-0000',
            icon: Icons.phone_outlined,
            inputFormatters: [_phoneFormatter],
            keyboardType: TextInputType.phone,
            focusNode: _phoneFocus,
            textInputAction: TextInputAction.done,
          ),
        ],
      ),
    );
  }

  Widget _buildAddressStep() {
    return Container(
      key: const ValueKey('address'),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Endereço',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppTheme.secondaryColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Informe seu endereço completo',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _buildTextField(
                  controller: _cepController,
                  label: 'CEP',
                  hint: '00000-000',
                  icon: Icons.location_searching,
                  inputFormatters: [_cepFormatter],
                  keyboardType: TextInputType.number,
                  focusNode: _cepFocus,
                  nextFocus: _streetFocus,
                ),
              ),
              if (_isLoadingCEP)
                const Padding(
                  padding: EdgeInsets.only(left: 12, top: 8),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _streetController,
            label: 'Rua/Avenida',
            hint: 'Nome da rua',
            icon: Icons.streetview,
            focusNode: _streetFocus,
            nextFocus: _numberFocus,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: _buildTextField(
                  controller: _numberController,
                  label: 'Número',
                  hint: '123',
                  icon: Icons.numbers,
                  keyboardType: TextInputType.number,
                  focusNode: _numberFocus,
                  nextFocus: _districtFocus,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: _buildTextField(
                  controller: _districtController,
                  label: 'Bairro',
                  hint: 'Nome do bairro',
                  icon: Icons.location_city,
                  focusNode: _districtFocus,
                  nextFocus: _cityFocus,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: _buildTextField(
                  controller: _cityController,
                  label: 'Cidade',
                  hint: 'Nome da cidade',
                  icon: Icons.location_city_outlined,
                  focusNode: _cityFocus,
                  nextFocus: _stateFocus,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: _buildTextField(
                  controller: _stateController,
                  label: 'Estado',
                  hint: 'UF',
                  icon: Icons.map_outlined,
                  focusNode: _stateFocus,
                  textInputAction: TextInputAction.done,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentsStep() {
    return Container(
      key: const ValueKey('documents'),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Documentos',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppTheme.secondaryColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tire fotos dos seus documentos',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 24),
          _buildImagePicker(
              'Frente do RG/CNH', 'front', _docFront, Icons.credit_card),
          const SizedBox(height: 16),
          _buildImagePicker(
              'Verso do RG/CNH', 'back', _docBack, Icons.credit_card),
          const SizedBox(height: 16),
          _buildImagePicker(
              'Selfie com Documento', 'selfie', _selfie, Icons.face),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    List<TextInputFormatter>? inputFormatters,
    TextInputType? keyboardType,
    FocusNode? focusNode,
    FocusNode? nextFocus,
    TextInputAction? textInputAction,
    bool enabled = true,
  }) {
    return TextField(
      controller: controller,
      inputFormatters: inputFormatters,
      keyboardType: keyboardType,
      focusNode: focusNode,
      enabled: enabled,
      textInputAction: textInputAction ??
          (nextFocus != null ? TextInputAction.next : TextInputAction.done),
      onSubmitted: (_) {
        if (nextFocus != null) {
          nextFocus.requestFocus();
        }
      },
      style: TextStyle(
        fontSize: 16,
        color: enabled ? Colors.black87 : Colors.grey.shade600,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        prefixIcon:
            Icon(icon, color: enabled ? AppTheme.primaryColor : Colors.grey),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
        ),
        filled: true,
        fillColor: enabled ? Colors.grey.shade50 : Colors.grey.shade100,
      ),
    );
  }

  Widget _buildImagePicker(
      String label, String type, XFile? file, IconData icon) {
    final hasImage = file != null;

    return InkWell(
      onTap: () => _pickImage(type),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: const BoxConstraints(minHeight: 110),
        decoration: BoxDecoration(
          color: hasImage
              ? AppTheme.primaryColor.withValues(alpha: 0.05)
              : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasImage ? AppTheme.primaryColor : Colors.grey.shade300,
            width: hasImage ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 80,
              height: 80,
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: hasImage ? null : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(8),
                image: hasImage
                    ? DecorationImage(
                        image: kIsWeb
                            ? NetworkImage(file.path) as ImageProvider
                            : FileImage(io.File(file.path)),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: hasImage
                  ? null
                  : Icon(icon, color: Colors.grey.shade400, size: 32),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: hasImage
                            ? AppTheme.primaryColor
                            : Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hasImage ? 'Toque para alterar' : 'Toque para tirar foto',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    if (hasImage) ...[
                      const SizedBox(height: 8),
                      const Row(
                        children: [
                          Icon(
                            Icons.check_circle,
                            color: AppTheme.primaryColor,
                            size: 16,
                          ),
                          SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              'Imagem capturada',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.primaryColor,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Icon(
                hasImage ? Icons.edit : Icons.camera_alt,
                color: hasImage ? AppTheme.primaryColor : Colors.grey.shade400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
