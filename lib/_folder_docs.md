# Lamsa Local POS System Architecture

## Overview
A Flutter-based Point of Sale (POS) system designed for a clothing store, implementing Clean Architecture principles with a Scanner-First approach for efficient inventory management.

## Core Architecture
- **Clean Architecture**: Separation of concerns into data, domain, and presentation layers
- **Local-First**: SQLite database (version 9) for reliable offline-first operations
- **Scanner-First**: Optimized for USB barcode scanner input with continuous listening
- **Flutter Framework**: Cross-platform UI with material design (RTL Arabic)

## Key Features
- Barcode-driven inventory management (multi-barcode per product)
- Real-time product scanning and cart management
- Local database with integer-based financial calculations (no doubles)
- Suspended orders with discount preservation
- Dynamic category management
- Discount system (fixed amount or percentage)
- PDF sales report export (saved to Desktop)
- Invoice receipt printing (configurable paper/font sizes)
- Barcode label printing (configurable dimensions)
- Two separate printers: one for receipts, one for barcodes
- Partial & full invoice returns with stock restoration
- Last invoice reprint
- PIN protection for Products and Sales pages
- Database backup to hidden D:\ folder + import/restore
- Developer settings page (hidden via Ctrl+Alt+Shift + devmh)

## Main Components
- `core/` — Database, theme, shared widgets
- `features/pos/` — Cashier/POS page
- `features/products/` — Product CRUD + barcode printing
- `features/sales/` — Sales reports, invoices, partial returns
- `features/settings/` — Developer settings (printers, PINs, backup)

## main.dart
Application entry point. Initializes Flutter bindings, pre-loads SQLite (FFI for desktop), enforces RTL text direction for Arabic, and applies `AppTheme`.