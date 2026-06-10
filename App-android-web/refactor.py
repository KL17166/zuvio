import os
import shutil
import re

base_dir = r"c:\Users\kl\Documents\Consorcio\App-android-web\lib"

# 1. Create directories
dirs_to_create = [
    "core/network",
    "core/services",
    "shared/widgets",
    "features/auth/services",
    "features/auth/providers",
    "features/auth/widgets",
    "features/catalog/models",
    "features/catalog/providers",
    "features/catalog/widgets",
    "features/consortium/models",
    "features/consortium/providers",
    "features/checkout/providers"
]

for d in dirs_to_create:
    os.makedirs(os.path.join(base_dir, d), exist_ok=True)

# 2. File moves
moves = {
    "data/services/api_service.dart": "core/network/api_service.dart",
    "data/services/storage_service.dart": "core/services/storage_service.dart",
    "device/device_service.dart": "core/services/device_service.dart",
    "device/biometric_service.dart": "core/services/biometric_service.dart",
    "data/services/auth_service.dart": "features/auth/services/auth_service.dart",
    "providers/auth_provider.dart": "features/auth/providers/auth_provider.dart",
    "shared/widgets/auth_guard.dart": "features/auth/widgets/auth_guard.dart",
    "data/models/product.dart": "features/catalog/models/product.dart",
    "data/models/product_category.dart": "features/catalog/models/product_category.dart",
    "providers/product_provider.dart": "features/catalog/providers/product_provider.dart",
    "shared/widgets/product_grid_item.dart": "features/catalog/widgets/product_grid_item.dart",
    "shared/widgets/product_list_item.dart": "features/catalog/widgets/product_list_item.dart",
    "shared/widgets/category_filter_chip.dart": "features/catalog/widgets/category_filter_chip.dart",
    "data/models/consortium_plan.dart": "features/consortium/models/consortium_plan.dart",
    "data/models/active_contract.dart": "features/consortium/models/active_contract.dart",
    "providers/consortium_provider.dart": "features/consortium/providers/consortium_provider.dart",
    "providers/contract_provider.dart": "features/consortium/providers/contract_provider.dart",
    "providers/payment_provider.dart": "features/checkout/providers/payment_provider.dart",
}

for src, dst in moves.items():
    src_path = os.path.join(base_dir, src)
    dst_path = os.path.join(base_dir, dst)
    if os.path.exists(src_path):
        shutil.move(src_path, dst_path)

# Move all files from lib/widgets/ to lib/shared/widgets/
widgets_dir = os.path.join(base_dir, "widgets")
if os.path.exists(widgets_dir):
    for f in os.listdir(widgets_dir):
        src_path = os.path.join(widgets_dir, f)
        if os.path.isfile(src_path):
            shutil.move(src_path, os.path.join(base_dir, "shared/widgets", f))

# 3. Update imports in all dart files
import_mappings = {
    "api_service.dart": "package:katari/core/network/api_service.dart",
    "storage_service.dart": "package:katari/core/services/storage_service.dart",
    "device_service.dart": "package:katari/core/services/device_service.dart",
    "biometric_service.dart": "package:katari/core/services/biometric_service.dart",
    "auth_service.dart": "package:katari/features/auth/services/auth_service.dart",
    "auth_provider.dart": "package:katari/features/auth/providers/auth_provider.dart",
    "auth_guard.dart": "package:katari/features/auth/widgets/auth_guard.dart",
    "product.dart": "package:katari/features/catalog/models/product.dart",
    "product_category.dart": "package:katari/features/catalog/models/product_category.dart",
    "product_provider.dart": "package:katari/features/catalog/providers/product_provider.dart",
    "product_grid_item.dart": "package:katari/features/catalog/widgets/product_grid_item.dart",
    "product_list_item.dart": "package:katari/features/catalog/widgets/product_list_item.dart",
    "category_filter_chip.dart": "package:katari/features/catalog/widgets/category_filter_chip.dart",
    "consortium_plan.dart": "package:katari/features/consortium/models/consortium_plan.dart",
    "active_contract.dart": "package:katari/features/consortium/models/active_contract.dart",
    "consortium_provider.dart": "package:katari/features/consortium/providers/consortium_provider.dart",
    "contract_provider.dart": "package:katari/features/consortium/providers/contract_provider.dart",
    "payment_provider.dart": "package:katari/features/checkout/providers/payment_provider.dart",
    "app_button.dart": "package:katari/shared/widgets/app_button.dart",
    "app_card.dart": "package:katari/shared/widgets/app_card.dart",
    "app_empty_state.dart": "package:katari/shared/widgets/app_empty_state.dart",
    "app_error_state.dart": "package:katari/shared/widgets/app_error_state.dart",
    "app_loading.dart": "package:katari/shared/widgets/app_loading.dart",
    "app_text_field.dart": "package:katari/shared/widgets/app_text_field.dart",
}

def update_imports(file_path):
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()

    original_content = content
    for filename, new_import in import_mappings.items():
        pattern = r"import\s+'[^']*?" + re.escape(filename) + r"'\s*;"
        replacement = f"import '{new_import}';"
        content = re.sub(pattern, replacement, content)

    if content != original_content:
        with open(file_path, 'w', encoding='utf-8') as f:
            f.write(content)

for root, _, files in os.walk(base_dir):
    for f in files:
        if f.endswith('.dart'):
            update_imports(os.path.join(root, f))

# 4. Remove empty directories safely
dirs_to_remove = [
    "data/models", "data/services", "data", 
    "providers", "device", "widgets"
]
for d in dirs_to_remove:
    path = os.path.join(base_dir, d)
    if os.path.exists(path):
        try:
            os.rmdir(path)
        except OSError:
            pass

print("Refactoring completed successfully.")
