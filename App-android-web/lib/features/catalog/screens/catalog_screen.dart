import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:katari/providers/consortium_provider.dart';
import 'package:katari/data/models/product_category.dart';
import 'package:katari/core/theme/app_theme.dart';
import 'package:katari/shared/widgets/product_list_item.dart';
import 'package:katari/shared/widgets/product_grid_item.dart';
import 'package:katari/shared/widgets/category_filter_chip.dart';

class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key});

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  bool _isGridView = false;
  late AnimationController _fabAnimationController;

  @override
  void initState() {
    super.initState();
    _fabAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<ConsortiumProvider>();

      // Initialize search controller with existing query
      _searchController.text = provider.searchQuery;

      // Fetch products if not already loaded
      if (provider.products.isEmpty) {
        provider.fetchProducts();
      }

      _fabAnimationController.forward();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _fabAnimationController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    context.read<ConsortiumProvider>().updateSearchQuery(query);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: CustomScrollView(
        slivers: [
          // App Bar moderna
          SliverAppBar(
            expandedHeight: 200,
            floating: false,
            pinned: true,
            backgroundColor: AppTheme.secondaryColor,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: FlexibleSpaceBar(
              title: const Text(
                'Catálogo',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  shadows: [
                    Shadow(
                      color: Colors.black26,
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    'https://images.unsplash.com/photo-1558981852-426c6c22a060?w=1200',
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Container(color: AppTheme.secondaryColor);
                    },
                    errorBuilder: (context, error, stackTrace) {
                      return Container(color: AppTheme.secondaryColor);
                    },
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          AppTheme.secondaryColor.withValues(alpha: 0.7),
                          AppTheme.secondaryColor,
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              IconButton(
                icon: Icon(_isGridView ? Icons.view_list : Icons.grid_view),
                onPressed: () => setState(() => _isGridView = !_isGridView),
                tooltip: _isGridView ? 'Ver como lista' : 'Ver como grade',
              ),
              const SizedBox(width: 8),
            ],
          ),

          // Barra de busca e filtros
          SliverToBoxAdapter(
            child: Consumer<ConsortiumProvider>(
              builder: (context, provider, child) {
                return Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // Campo de busca
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: TextField(
                          controller: _searchController,
                          onChanged: _onSearchChanged,
                          decoration: InputDecoration(
                            hintText: 'Buscar produtos...',
                            hintStyle: TextStyle(color: Colors.grey.shade500),
                            prefixIcon: const Icon(
                              Icons.search,
                              color: AppTheme.primaryColor,
                            ),
                            suffixIcon: provider.searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 20),
                                    onPressed: () {
                                      _searchController.clear();
                                      provider.clearSearch();
                                    },
                                    tooltip: 'Limpar busca',
                                  )
                                : null,
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Filtros de categoria
                      SizedBox(
                        height: 42,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: ProductType.values.map((category) {
                            return CategoryFilterChip(
                              category: category,
                              provider: provider,
                            );
                          }).toList(),
                        ),
                      ),

                      // Subcategory Filters
                      if (provider.selectedCategory != ProductType.todos &&
                          provider.selectedCategory.subCategories.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: SizedBox(
                            height: 36,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              children: [
                                // "Todos" subcategory chip
                                Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: FilterChip(
                                    label: const Text('Todos'),
                                    selected:
                                        provider.selectedSubCategory == null,
                                    onSelected: (_) =>
                                        provider.updateSubCategoryFilter(null),
                                    selectedColor:
                                        AppTheme.primaryColor.withValues(alpha: 0.7),
                                    checkmarkColor: Colors.white,
                                    labelStyle: TextStyle(
                                      color:
                                          provider.selectedSubCategory == null
                                              ? Colors.white
                                              : Colors.grey.shade700,
                                      fontWeight:
                                          provider.selectedSubCategory == null
                                              ? FontWeight.bold
                                              : FontWeight.w500,
                                      fontSize: 12,
                                    ),
                                    backgroundColor: Colors.grey.shade100,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                                // Subcategory chips
                                ...provider.selectedCategory.subCategories
                                    .map((sub) {
                                  final isSelected =
                                      provider.selectedSubCategory == sub.key;
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: FilterChip(
                                      avatar: isSelected
                                          ? null
                                          : Text(sub.icon,
                                              style: const TextStyle(
                                                  fontSize: 12)),
                                      label: Text(sub.displayName),
                                      selected: isSelected,
                                      onSelected: (_) =>
                                          provider.updateSubCategoryFilter(
                                              isSelected ? null : sub.key),
                                      selectedColor: AppTheme.primaryColor
                                          .withValues(alpha: 0.7),
                                      checkmarkColor: Colors.white,
                                      labelStyle: TextStyle(
                                        color: isSelected
                                            ? Colors.white
                                            : Colors.grey.shade700,
                                        fontWeight: isSelected
                                            ? FontWeight.bold
                                            : FontWeight.w500,
                                        fontSize: 12,
                                      ),
                                      backgroundColor: Colors.grey.shade100,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  );
                                }),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),

          // Results count
          Consumer<ConsortiumProvider>(
            builder: (context, provider, child) {
              final count = provider.filteredProducts.length;
              return SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '$count ${count == 1 ? "produto encontrado" : "produtos encontrados"}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      if (provider.searchQuery.isNotEmpty ||
                          provider.selectedCategory != ProductType.todos)
                        TextButton.icon(
                          onPressed: () {
                            _searchController.clear();
                            provider.clearFilters();
                          },
                          icon: const Icon(Icons.clear_all, size: 18),
                          label: const Text('Limpar filtros'),
                          style: TextButton.styleFrom(
                            foregroundColor: AppTheme.primaryColor,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),

          // Lista/Grid de motos
          Consumer<ConsortiumProvider>(
            builder: (context, provider, child) {
              if (provider.isLoading) {
                return const SliverFillRemaining(
                  child: Center(
                    child: CircularProgressIndicator(
                      color: AppTheme.primaryColor,
                    ),
                  ),
                );
              }

              final products = provider.filteredProducts;

              if (products.isEmpty) {
                return SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.search_off,
                          size: 80,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Nenhum produto encontrado',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tente ajustar os filtros ou buscar por outro termo',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: () {
                            _searchController.clear();
                            provider.clearFilters();
                          },
                          icon: const Icon(Icons.refresh),
                          label: const Text('Limpar Filtros'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return _isGridView
                  ? SliverPadding(
                      padding: const EdgeInsets.all(16),
                      sliver: SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 0.58,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final product = products[index];
                            return ProductGridItem(
                              product: product,
                              provider: provider,
                            );
                          },
                          childCount: products.length,
                        ),
                      ),
                    )
                  : SliverPadding(
                      padding: const EdgeInsets.all(16),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final product = products[index];
                            return ProductListItem(
                              product: product,
                              provider: provider,
                              index: index,
                            );
                          },
                          childCount: products.length,
                        ),
                      ),
                    );
            },
          ),

          const SliverToBoxAdapter(
            child: SizedBox(height: 20),
          ),
        ],
      ),
    );
  }
}
