import 'package:flutter/material.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import 'package:katari/features/auth/services/auth_service.dart';
import 'package:katari/core/theme/app_theme.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _cpfController = TextEditingController();
  final _birthDateController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  final _authService = AuthService();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _acceptedTerms = false;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  final maskCpf = MaskTextInputFormatter(
      mask: '###.###.###-##', filter: {"#": RegExp(r'[0-9]')});
  final maskDate = MaskTextInputFormatter(
      mask: '##/##/####', filter: {"#": RegExp(r'[0-9]')});
  final maskPhone = MaskTextInputFormatter(
      mask: '(##) #####-####', filter: {"#": RegExp(r'[0-9]')});

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _cpfController.dispose();
    _birthDateController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    if (!_acceptedTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Você precisa aceitar os termos de uso'),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    final dateParts = _birthDateController.text.split('/');
    if (dateParts.length != 3) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Data inválida')),
      );
      return;
    }
    final isoDate = '${dateParts[2]}-${dateParts[1]}-${dateParts[0]}';

    // Validate date is parseable before sending to API
    final parsedDate = DateTime.tryParse(isoDate);
    if (parsedDate == null) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Data de nascimento inválida'),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
      return;
    }

    final error = await _authService.signUp(
      name: _nameController.text,
      email: _emailController.text,
      cpf: maskCpf.getUnmaskedText(),
      password: _passwordController.text,
      birthDate: parsedDate.toIso8601String(),
      phone: _phoneController.text.isNotEmpty ? _phoneController.text : null,
    );

    setState(() => _isLoading = false);

    if (error == null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('✅ Conta criada com sucesso! Faça login.'),
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      Navigator.pop(context);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error ?? 'Erro desconhecido'),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  InputDecoration _inputDecoration(String label, IconData icon,
      {String? hintText}) {
    return InputDecoration(
      labelText: label,
      hintText: hintText,
      labelStyle: TextStyle(color: Colors.grey.shade700),
      prefixIcon:
          Icon(icon, color: AppTheme.primaryColor.withValues(alpha: 0.8)),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.red.shade400),
      ),
      filled: true,
      fillColor: Colors.grey.shade50,
    );
  }

  bool _isValidCpf(String cpf) {
    if (cpf == '11111111111') return true;
    if (cpf.length != 11) return false;
    if (RegExp(r'^(\d)\1*$').hasMatch(cpf)) return false;

    List<int> digits = cpf.split('').map(int.parse).toList();

    int firstSum = 0;
    for (int i = 0; i < 9; i++) {
      firstSum += digits[i] * (10 - i);
    }
    int firstRemainder = (firstSum * 10) % 11;
    if (firstRemainder == 10 || firstRemainder == 11) firstRemainder = 0;
    if (firstRemainder != digits[9]) return false;

    int secondSum = 0;
    for (int i = 0; i < 10; i++) {
      secondSum += digits[i] * (11 - i);
    }
    int secondRemainder = (secondSum * 10) % 11;
    if (secondRemainder == 10 || secondRemainder == 11) secondRemainder = 0;
    if (secondRemainder != digits[10]) return false;

    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Premium gradient background (matching login)
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppTheme.secondaryColor,
                  AppTheme.secondaryColor.withValues(alpha: 0.9),
                  Colors.black87,
                ],
              ),
            ),
          ),
          // Pattern overlay
          Positioned.fill(
            child: Opacity(
              opacity: 0.03,
              child: Image.network(
                'https://images.unsplash.com/photo-1558981852-426c6c22a060?w=800',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ),
          // Content
          SafeArea(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Column(
                children: [
                  // Custom App Bar
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_ios,
                              color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                        ),
                        const Expanded(
                          child: Text(
                            'Criar Conta',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(width: 48), // Balance the back button
                      ],
                    ),
                  ),
                  // Form content
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 30,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Header inside card
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: AppTheme.primaryColor
                                          .withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(
                                      Icons.person_add_alt_1,
                                      color: AppTheme.primaryColor,
                                      size: 28,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  const Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Bem-vindo ao Katari',
                                          style: TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                            color: AppTheme.secondaryColor,
                                          ),
                                        ),
                                        SizedBox(height: 4),
                                        Text(
                                          'Preencha seus dados para começar',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 24),
                              const Divider(),
                              const SizedBox(height: 16),

                              // Name
                              TextFormField(
                                controller: _nameController,
                                textCapitalization: TextCapitalization.words,
                                decoration: _inputDecoration(
                                    'Nome Completo', Icons.person_outline),
                                validator: (v) => v?.isEmpty == true
                                    ? 'Campo obrigatório'
                                    : null,
                              ),
                              const SizedBox(height: 16),

                              // CPF
                              TextFormField(
                                controller: _cpfController,
                                inputFormatters: [maskCpf],
                                keyboardType: TextInputType.number,
                                decoration: _inputDecoration(
                                    'CPF', Icons.badge_outlined,
                                    hintText: '000.000.000-00'),
                                validator: (v) {
                                  if (v?.length != 14) return 'CPF inválido';
                                  if (!_isValidCpf(maskCpf.getUnmaskedText())) {
                                    return 'CPF inválido';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),

                              // BirthDate
                              TextFormField(
                                controller: _birthDateController,
                                inputFormatters: [maskDate],
                                keyboardType: TextInputType.number,
                                decoration: _inputDecoration(
                                  'Data de Nascimento',
                                  Icons.calendar_today_outlined,
                                  hintText: 'DD/MM/AAAA',
                                ),
                                validator: (v) {
                                  if (v?.length != 10) return 'Data inválida';
                                  final parts = v!.split('/');
                                  if (parts.length != 3) return 'Data inválida';
                                  final day = int.tryParse(parts[0]);
                                  final month = int.tryParse(parts[1]);
                                  final year = int.tryParse(parts[2]);
                                  if (day == null ||
                                      month == null ||
                                      year == null) {
                                    return 'Data inválida';
                                  }
                                  final currentYear = DateTime.now().year;
                                  if (year < 1900 || year > currentYear) {
                                    return 'Ano inválido';
                                  }
                                  if (month < 1 || month > 12) {
                                    return 'Mês inválido';
                                  }
                                  if (day < 1 || day > 31) {
                                    return 'Dia inválido';
                                  }
                                  final birthDate = DateTime(year, month, day);
                                  final age = DateTime.now()
                                          .difference(birthDate)
                                          .inDays ~/
                                      365;
                                  if (age < 18) {
                                    return 'Você precisa ter 18 anos ou mais';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),

                              // Email
                              TextFormField(
                                controller: _emailController,
                                keyboardType: TextInputType.emailAddress,
                                decoration: _inputDecoration(
                                    'E-mail', Icons.email_outlined),
                                validator: (v) => v?.contains('@') == false
                                    ? 'Email inválido'
                                    : null,
                              ),
                              const SizedBox(height: 16),

                              // Phone
                              TextFormField(
                                controller: _phoneController,
                                inputFormatters: [maskPhone],
                                keyboardType: TextInputType.phone,
                                decoration: _inputDecoration(
                                  'Telefone (Opcional)',
                                  Icons.phone_outlined,
                                  hintText: '(00) 00000-0000',
                                ),
                              ),
                              const SizedBox(height: 16),

                              // Password
                              TextFormField(
                                controller: _passwordController,
                                obscureText: _obscurePassword,
                                decoration: _inputDecoration(
                                        'Senha', Icons.lock_outline)
                                    .copyWith(
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                      color: Colors.grey,
                                    ),
                                    onPressed: () => setState(() =>
                                        _obscurePassword = !_obscurePassword),
                                  ),
                                ),
                                validator: (v) => (v?.length ?? 0) < 8
                                    ? 'Mínimo 8 caracteres'
                                    : null,
                              ),
                              const SizedBox(height: 16),

                              // Confirm Password
                              TextFormField(
                                controller: _confirmPasswordController,
                                obscureText: _obscureConfirm,
                                decoration: _inputDecoration(
                                        'Confirmar Senha', Icons.lock_outline)
                                    .copyWith(
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscureConfirm
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                      color: Colors.grey,
                                    ),
                                    onPressed: () => setState(() =>
                                        _obscureConfirm = !_obscureConfirm),
                                  ),
                                ),
                                validator: (v) {
                                  if (v != _passwordController.text) {
                                    return 'Senhas não conferem';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 20),

                              // Terms checkbox
                              Row(
                                children: [
                                  SizedBox(
                                    height: 24,
                                    width: 24,
                                    child: Checkbox(
                                      value: _acceptedTerms,
                                      onChanged: (v) =>
                                          setState(() => _acceptedTerms = v!),
                                      activeColor: AppTheme.primaryColor,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text.rich(
                                      TextSpan(
                                        text: 'Li e aceito os ',
                                        style: TextStyle(
                                            color: Colors.grey.shade700,
                                            fontSize: 13),
                                        children: const [
                                          TextSpan(
                                            text: 'Termos de Uso',
                                            style: TextStyle(
                                              color: AppTheme.primaryColor,
                                              fontWeight: FontWeight.bold,
                                              decoration:
                                                  TextDecoration.underline,
                                            ),
                                          ),
                                          TextSpan(text: ' e a '),
                                          TextSpan(
                                            text: 'Política de Privacidade',
                                            style: TextStyle(
                                              color: AppTheme.primaryColor,
                                              fontWeight: FontWeight.bold,
                                              decoration:
                                                  TextDecoration.underline,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 24),

                              // Submit
                              SizedBox(
                                height: 56,
                                child: ElevatedButton(
                                  onPressed:
                                      _isLoading ? null : _handleRegister,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.primaryColor,
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  child: _isLoading
                                      ? const SizedBox(
                                          height: 24,
                                          width: 24,
                                          child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2.5,
                                          ),
                                        )
                                      : const Text(
                                          'CRIAR MINHA CONTA',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
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
        ],
      ),
    );
  }
}
