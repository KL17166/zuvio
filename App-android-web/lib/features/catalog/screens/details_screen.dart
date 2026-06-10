import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:katari/features/consortium/providers/consortium_provider.dart';
import 'package:katari/features/consortium/models/consortium_plan.dart';
import 'package:katari/core/theme/app_theme.dart';
import 'package:katari/core/constants/routes.dart';

class DetailsScreen extends StatefulWidget {
  const DetailsScreen({super.key});

  @override
  State<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends State<DetailsScreen>
    with TickerProviderStateMixin {
  final PageController _imageController = PageController();
  final ScrollController _scrollController = ScrollController();
  int _currentImageIndex = 0;
  bool _showFab = false;
  late AnimationController _fabController;
  late AnimationController _planController;

  @override
  void initState() {
    super.initState();

    // FAB Animation Controller
    _fabController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    // Plan Selection Animation Controller
    _planController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    // Scroll listener for FAB
    _scrollController.addListener(() {
      if (_scrollController.offset > 400 && !_showFab) {
        setState(() => _showFab = true);
        _fabController.forward();
      } else if (_scrollController.offset <= 400 && _showFab) {
        setState(() => _showFab = false);
        _fabController.reverse();
      }
    });

    // Auto-select the plan that best matches the product's monthly price
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<ConsortiumProvider>();
      final product = provider.selectedProduct;

      if (product != null && provider.selectedPlan == null) {
        ConsortiumPlan? bestMatch;
        double smallestDifference = double.infinity;

        // moto.plans comes sorted or not, we iterate all
        for (final plan in product.plans) {
          final calculatedPayment = plan.monthlyInstallment;
          final difference = (calculatedPayment - product.monthlyPrice).abs();

          if (difference < smallestDifference) {
            smallestDifference = difference;
            bestMatch = plan;
          }
        }

        if (bestMatch != null) {
          provider.selectPlan(bestMatch);
          _planController.forward();
        }
      }
    });
  }

  @override
  void dispose() {
    _imageController.dispose();
    _scrollController.dispose();
    _fabController.dispose();
    _planController.dispose();
    super.dispose();
  }

  void _scrollToTop() {
    HapticFeedback.mediumImpact();
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ConsortiumProvider>(
      builder: (context, provider, child) {
        final product = provider.selectedProduct;
        if (product == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Detalhes')),
            body: const Center(child: Text('Nenhum produto selecionado')),
          );
        }

        return Scaffold(
          backgroundColor: Colors.white,
          body: Stack(
            children: [
              CustomScrollView(
                controller: _scrollController,
                physics: const BouncingScrollPhysics(),
                slivers: [
                  // App Bar with Image Gallery
                  _buildImageGalleryAppBar(product),

                  // Product Name and Category
                  SliverToBoxAdapter(
                    child: _buildHeaderInfo(product),
                  ),

                  // Price and Plan Selection
                  SliverToBoxAdapter(
                    child: _buildPriceSection(product, provider),
                  ),

                  // Plan Selection - Attractive Tabs
                  SliverToBoxAdapter(
                    child: _buildPlanSelection(product, provider),
                  ),

                  // Selected Plan Info
                  if (provider.selectedPlan != null)
                    SliverToBoxAdapter(
                      child:
                          _buildSelectedPlanInfo(product, provider.selectedPlan!),
                    ),

                  // Key Features
                  SliverToBoxAdapter(
                    child: _buildKeyFeatures(product),
                  ),

                  // Detailed Specifications
                  SliverToBoxAdapter(
                    child: _buildDetailedSpecs(product),
                  ),

                  // Benefits Section
                  SliverToBoxAdapter(
                    child: _buildBenefitsSection(),
                  ),

                  // Bottom Spacing
                  const SliverToBoxAdapter(
                    child: SizedBox(height: 100),
                  ),
                ],
              ),

              // Floating Action Button - Scroll to Top
              if (_showFab)
                Positioned(
                  right: 16,
                  bottom: 100,
                  child: ScaleTransition(
                    scale: CurvedAnimation(
                      parent: _fabController,
                      curve: Curves.easeOutBack,
                    ),
                    child: FloatingActionButton(
                      mini: true,
                      backgroundColor: AppTheme.primaryColor,
                      onPressed: _scrollToTop,
                      child: const Icon(Icons.arrow_upward,
                          color: Colors.white, size: 20),
                    ),
                  ),
                ),

              // Fixed Back Button
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                left: 14,
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.arrow_back,
                        color: Colors.white, size: 22),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      Navigator.pop(context);
                    },
                  ),
                ),
              ),

              // Fixed Bottom Button
              if (provider.selectedPlan != null)
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: MediaQuery.of(context).padding.bottom + 16,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppTheme.primaryColor, Color(0xFFFF8F00)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primaryColor.withValues(alpha: 0.4),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          HapticFeedback.mediumImpact();
                          Navigator.pushNamed(context, AppRoutes.checkout);
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Continuar',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(width: 8),
                              Icon(Icons.arrow_forward,
                                  size: 20, color: Colors.white),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildImageGalleryAppBar(product) {
    final images = product.imageUrls;

    return SliverAppBar(
      expandedHeight: 350,
      automaticallyImplyLeading: false,
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            // Image Gallery with Loading State
            PageView.builder(
              controller: _imageController,
              physics: const BouncingScrollPhysics(),
              onPageChanged: (index) {
                setState(() => _currentImageIndex = index);
                HapticFeedback.selectionClick();
              },
              itemCount: images.length,
              itemBuilder: (context, index) {
                return Hero(
                  tag: 'product_${product.id}_$index',
                  child: Image.network(
                    images[index],
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Container(
                        color: Colors.grey.shade200,
                        child: Center(
                          child: CircularProgressIndicator(
                            value: loadingProgress.expectedTotalBytes != null
                                ? loadingProgress.cumulativeBytesLoaded /
                                    loadingProgress.expectedTotalBytes!
                                : null,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color: Colors.grey.shade200,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.inventory_2,
                                size: 100, color: Colors.grey.shade400),
                            const SizedBox(height: 16),
                            Text(
                              'Imagem não disponível',
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                );
              },
            ),

            // Gradient overlay (ignores touches to allow swiping)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Container(
                  height: 120,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.7),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Swipe indicator (left/right arrows)
            if (images.length > 1) ...[
              Positioned(
                left: 16,
                top: 0,
                bottom: 0,
                child: Center(
                  child: GestureDetector(
                    onTap: _currentImageIndex > 0
                        ? () {
                            HapticFeedback.selectionClick();
                            _imageController.previousPage(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                            );
                          }
                        : null,
                    child: AnimatedOpacity(
                      opacity: _currentImageIndex > 0 ? 1.0 : 0.3,
                      duration: const Duration(milliseconds: 300),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.chevron_left,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 16,
                top: 0,
                bottom: 0,
                child: Center(
                  child: GestureDetector(
                    onTap: _currentImageIndex < images.length - 1
                        ? () {
                            HapticFeedback.selectionClick();
                            _imageController.nextPage(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                            );
                          }
                        : null,
                    child: AnimatedOpacity(
                      opacity:
                          _currentImageIndex < images.length - 1 ? 1.0 : 0.3,
                      duration: const Duration(milliseconds: 300),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.8),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.chevron_right,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],

            // Page indicators
            Positioned(
              bottom: 20,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  images.length,
                  (index) => AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: _currentImageIndex == index ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _currentImageIndex == index
                          ? AppTheme.primaryColor
                          : Colors.white.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: _currentImageIndex == index
                          ? [
                              BoxShadow(
                                color: AppTheme.primaryColor
                                    .withValues(alpha: 0.4),
                                blurRadius: 8,
                                spreadRadius: 1,
                              )
                            ]
                          : null,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderInfo(product) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            product.name,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: AppTheme.secondaryColor,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryColor.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  product.categoryDisplayName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (product.isFeatured)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.amber,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.amber.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.star, size: 14, color: Colors.white),
                      SizedBox(width: 4),
                      Text(
                        'DESTAQUE',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPriceSection(product, ConsortiumProvider provider) {
    return Container(
      padding: const EdgeInsets.all(20),
      color: Colors.grey.shade50,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Valor do Consórcio',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$')
                .format(product.price),
            style: const TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.bold,
              color: AppTheme.secondaryColor,
            ),
          ),
          const SizedBox(height: 8),
          if (provider.selectedPlan != null)
            AnimatedOpacity(
              opacity: 1.0,
              duration: const Duration(milliseconds: 300),
              child: Text(
                'ou ${provider.selectedPlan!.durationMonths}x de ${NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(provider.selectedPlan!.monthlyInstallment)}',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPlanSelection(product, ConsortiumProvider provider) {
    // Sort plans by duration if needed, but usually backend sends sorted.
    // Ensure we use product.plans
    final plans = product.plans;

    return Container(
      padding: const EdgeInsets.all(20),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Escolha o prazo ideal para você',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppTheme.secondaryColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Selecione a quantidade de meses que melhor se adequa ao seu orçamento',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 20),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.4,
            children: plans.map<Widget>((plan) {
              final isSelected = provider.selectedPlan == plan;
              final monthlyPayment = plan.monthlyInstallment;

              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    provider.selectPlan(plan);
                    _planController.forward(from: 0);
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: isSelected
                          ? const LinearGradient(
                              colors: [
                                AppTheme.primaryColor,
                                Color(0xFFFF8F00)
                              ],
                            )
                          : null,
                      color: isSelected ? null : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? AppTheme.primaryColor
                            : Colors.grey.shade300,
                        width: isSelected ? 2 : 1,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: AppTheme.primaryColor
                                    .withValues(alpha: 0.3),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              )
                            ]
                          : null,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            Text(
                              '${plan.durationMonths} meses',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: isSelected
                                    ? Colors.white
                                    : AppTheme.secondaryColor,
                              ),
                            ),
                            if (isSelected) ...[
                              const SizedBox(width: 8),
                              ScaleTransition(
                                scale: CurvedAnimation(
                                  parent: _planController,
                                  curve: Curves.elasticOut,
                                ),
                                child: const Icon(
                                  Icons.check_circle,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$')
                              .format(monthlyPayment),
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: isSelected
                                ? Colors.white
                                : AppTheme.primaryColor,
                          ),
                        ),
                        Text(
                          'por mês',
                          style: TextStyle(
                            fontSize: 13.63,
                            color: isSelected
                                ? Colors.white.withValues(alpha: 0.9)
                                : Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedPlanInfo(product, ConsortiumPlan plan) {
    final monthlyPayment = plan.monthlyInstallment;
    final totalAmount = monthlyPayment * plan.durationMonths;

    return FadeTransition(
      opacity: CurvedAnimation(
        parent: _planController,
        curve: Curves.easeIn,
      ),
      child: Container(
        margin: const EdgeInsets.all(20),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.primaryColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppTheme.primaryColor.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Column(
          children: [
            const Row(
              children: [
                Icon(Icons.info_outline, color: AppTheme.primaryColor),
                SizedBox(width: 8),
                Text(
                  'Resumo do Plano Escolhido',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.secondaryColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildInfoRow('Prazo', '${plan.durationMonths} meses'),
            const SizedBox(height: 8),
            _buildInfoRow(
              'Parcela mensal',
              NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$')
                  .format(monthlyPayment),
            ),
            const SizedBox(height: 8),
            _buildInfoRow(
              'Total a pagar',
              NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$')
                  .format(totalAmount),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade700,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: AppTheme.secondaryColor,
          ),
        ),
      ],
    );
  }

  Widget _buildKeyFeatures(product) {
    // Generate features from specs
    final List<String> features = [];
    final specs = product.specs;

    if (specs['engineType'] != null && specs['engineType'].toString().isNotEmpty) {
      features.add('Motor ${specs['engineType']}');
    }
    if (specs['power'] != null && specs['power'].toString().isNotEmpty) {
      features.add('Potência de ${specs['power']}');
    }
    if (specs['displacement'] != null && specs['displacement'].toString().isNotEmpty) {
      features.add('Cilindrada de ${specs['displacement']}');
    }
    if (specs['transmission'] != null && specs['transmission'].toString().isNotEmpty) {
      features.add('Transmissão ${specs['transmission']}');
    }
    if (specs['consumption'] != null && specs['consumption'].toString().isNotEmpty) {
      features.add('Consumo médio de ${specs['consumption']}');
    }

    if (features.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(20),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Destaques',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppTheme.secondaryColor,
            ),
          ),
          const SizedBox(height: 16),
          ...features.take(5).map((feature) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 2),
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check,
                        color: AppTheme.primaryColor,
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        feature,
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.grey.shade800,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildDetailedSpecs(product) {
    final specs = product.specs;
    
    // Define the display labels and keys we want to show specifically for motorcycles
    // For other types, we might just show everything in specs
    final Map<String, String> displaySpecs = {};

    // Specific mapping for known keys to friendly names
    final knownKeys = {
      'engineType': 'Motor',
      'displacement': 'Cilindrada',
      'power': 'Potência',
      'torque': 'Torque',
      'transmission': 'Transmissão',
      'frontBrake': 'Freio Dianteiro',
      'rearBrake': 'Freio Traseiro',
      'weight': 'Peso',
      'fuelCapacity': 'Capacidade do Tanque',
      'consumption': 'Consumo Médio',
    };

    // First add known keys if they exist
    knownKeys.forEach((key, label) {
      if (specs.containsKey(key) && specs[key] != null && specs[key].toString().isNotEmpty) {
        displaySpecs[label] = specs[key].toString();
      }
    });

    // If it's a generic product, maybe add other specs too?
    // For now, let's stick to what was there, but safely.
    if (displaySpecs.isEmpty) {
        // Fallback: show all specs if no known keys matched
        specs.forEach((key, value) {
            if (value != null && value.toString().isNotEmpty) {
                 displaySpecs[key] = value.toString();
            }
        });
    }

    if (displaySpecs.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.grey.shade200,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Especificações Técnicas',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppTheme.secondaryColor,
            ),
          ),
          const SizedBox(height: 16),
          ...displaySpecs.entries.map((entry) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.key,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      entry.value,
                      style: const TextStyle(
                        fontSize: 15,
                        color: AppTheme.secondaryColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildBenefitsSection() {
    final benefits = [
      {
        'icon': Icons.verified_user,
        'title': 'Seguro Incluso',
        'description': 'Proteção completa durante todo o consórcio',
        'color': Colors.blue,
      },
      {
        'icon': Icons.support_agent,
        'title': 'Suporte 24/7',
        'description': 'Atendimento sempre que você precisar',
        'color': Colors.green,
      },
      {
        'icon': Icons.trending_up,
        'title': 'Sem Juros',
        'description': 'Apenas taxa administrativa fixa',
        'color': Colors.orange,
      },
      {
        'icon': Icons.card_giftcard,
        'title': 'Benefícios Exclusivos',
        'description': 'Descontos em manutenção e acessórios',
        'color': Colors.purple,
      },
    ];

    return Container(
      padding: const EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: 0,
      ),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Vantagens do Consórcio',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppTheme.secondaryColor,
            ),
          ),
          const SizedBox(height: 16),
          ...benefits.map((benefit) => Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: (benefit['color'] as Color).withValues(alpha: 0.2),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color:
                            (benefit['color'] as Color).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        benefit['icon'] as IconData,
                        color: benefit['color'] as Color,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            benefit['title'] as String,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.secondaryColor,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            benefit['description'] as String,
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
              )),
        ],
      ),
    );
  }
}
