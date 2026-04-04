# Core Module Documentation

This directory contains core functionality and utilities used across the application.

## Directory Structure
- `database/` — `DatabaseHelper` singleton: SQLite v9, all CRUD, backup/restore, partial returns, multi-barcode, settings key-value store
- `theme/` — `AppTheme`: color constants + `ThemeData` (Cairo font, RTL)
- `widgets/` — Reusable UI components:
  - `main_layout.dart` — `MainLayout`: BottomNavigationBar + IndexedStack, PIN gate for Products/Sales tabs, dev shortcut (Ctrl+Alt+Shift+devmh)
  - `custom_button.dart` — Reusable styled button
  - `custom_text_field.dart` — Reusable styled text field