# Database Module Documentation

## File: database_helper.dart

### Class: DatabaseHelper
Singleton pattern implementation for SQLite database management.

#### Key Components:
- Line 5-8: Singleton instance setup and private constructor
- Line 11-16: Database getter with lazy initialization
- Line 18-28: Database initialization with version management
- Line 31-33: Foreign key configuration
- Line 35-50: Initial database creation (v1)
  - Products table with indexed barcode field
- Line 52-57: Database upgrade handling
- Line 60-95: Version 2 schema updates
  - Categories table creation
  - Suspended orders system
  - Order items with foreign key constraints
- Line 97+: Database cleanup and closing

### Database Schema
1. Products Table (v1):
   - Primary fields: id, name, category, price
   - Optional fields: color, size, barcode
   - Performance: Indexed barcode field

2. Categories Table (v2):
   - Simple structure: id, name
   - Unique constraint on name

3. Suspended Orders System (v2):
   - Main order table with notes
   - Detailed items table with foreign keys
   - Cascade deletion support