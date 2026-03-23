# Lamsa Local POS System Architecture

## Overview
A Flutter-based Point of Sale (POS) system designed for a clothing store, implementing Clean Architecture principles with a Scanner-First approach for efficient inventory management.

## Core Architecture
- **Clean Architecture**: Separation of concerns into data, domain, and presentation layers
- **Local-First**: SQLite database for reliable offline-first operations
- **Scanner-First**: Optimized for barcode scanner input with continuous listening
- **Flutter Framework**: Cross-platform UI with material design

## Key Features
- Barcode-driven inventory management
- Real-time product scanning and cart management
- Local database with precise financial calculations
- Suspended orders system for managing multiple transactions
- Dynamic category management
- Custom theming and reusable widgets

## Main Components
- Core utilities and database management
- Product management feature
- POS (Point of Sale) feature
- Custom widgets and theme management

## main.dart
 Application entry point. Initializes Flutter bindings, pre-loads the SQLite database instance, enforces RTL text direction for Arabic support, and applies `AppTheme`.