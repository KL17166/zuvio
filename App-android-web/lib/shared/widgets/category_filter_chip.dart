import 'package:flutter/material.dart';
import 'package:katari/data/models/product_category.dart';
import 'package:katari/providers/consortium_provider.dart';
import 'package:katari/core/theme/app_theme.dart';

class CategoryFilterChip extends StatelessWidget {
  final ProductType category;
  final ConsortiumProvider provider;

  const CategoryFilterChip({
    super.key,
    required this.category,
    required this.provider,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = provider.selectedCategory == category;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        avatar: isSelected ? null : Text(category.icon, style: const TextStyle(fontSize: 14)),
        label: Text(category.displayName),
        selected: isSelected,
        onSelected: (selected) => provider.updateCategoryFilter(category),
        selectedColor: AppTheme.primaryColor,
        checkmarkColor: Colors.white,
        labelStyle: TextStyle(
          color: isSelected ? Colors.white : Colors.grey.shade700,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          fontSize: 14,
        ),
        backgroundColor: Colors.grey.shade200,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        elevation: isSelected ? 2 : 0,
      ),
    );
  }
}
