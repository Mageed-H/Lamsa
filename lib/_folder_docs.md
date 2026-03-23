# Lamsa Local Cashier App - Clean Architecture Structure

## Folder Structure Overview

### `/core`
Contains shared, reusable code and utilities used across the entire application.

- **`/database`** - Database management and helper utilities
- **`/theme`** - App theming, colors, typography, and styling
## Features (`lib/features/`)
### Products Data (`lib/features/products/data/models/`)
* **`product_model.dart`**: Defines the `ProductModel` entity. Includes strict Null-Safety (`?? ''`), financial precision mapping (`int` for price), SQLite boolean mapping (`1/0` to `true/false`), and standard `toMap`, `fromMap`, and `copyWith` methods.

- **`/products`** - Product management feature
  - **`/data`** - Data access layer
    - **`/models`** - Data models (usually map to API/database)
  - **`/presentation`** - UI layer (UI, widgets, pages)
    - **`/pages`** - Full-screen pages/views
    - **`/widgets`** - Reusable UI components

## Architecture Pattern

This project follows Clean Architecture with the following layers:

1. **Data Layer** (`/data`) - Repositories, models, and data sources
2. **Domain Layer** (planned) - Use cases and business logic
3. **Presentation Layer** (`/presentation`) - UI components, pages, and state management

## File Descriptions

- `database_helper.dart` - Database initialization and query helpers
- `app_theme.dart` - Theme configuration (colors, text styles, etc.)
- `product_model.dart` - Product data model
- `products_page.dart` - Products list/management page
- `barcode_printer_widget.dart` - Barcode printing widget component
* **`database_helper.dart` (Migration V2)**: Bumped version to 2. Added safe migration (`_upgradeDB`) to create dynamic `categories` table and `suspended_orders` / `suspended_order_items` tables with Foreign Key cascades. Added initial CRUD for categories.

## Core UI & Theme (`lib/core/`)
* **`theme/app_theme.dart`**: Centralized design system defining primary, secondary, and semantic colors. No hardcoded hex colors are allowed in the UI.
* **`widgets/custom_text_field.dart`**: Reusable robust text input field with built-in validation support, icon support, and styling tied to `AppTheme`.
* **`widgets/custom_button.dart`**: Reusable premium primary button, ensuring consistent interactive elements across the application.