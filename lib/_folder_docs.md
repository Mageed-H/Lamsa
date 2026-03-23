# Lamsa Local Cashier App - Clean Architecture Structure

## Folder Structure Overview

### `/core`
Contains shared, reusable code and utilities used across the entire application.

- **`/database`** - Database management and helper utilities
- **`/theme`** - App theming, colors, typography, and styling

### `/features`
Contains feature-specific code organized by feature domain.

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
