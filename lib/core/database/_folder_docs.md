# Database Module Documentation

## File: database_helper.dart

### Class: DatabaseHelper
Singleton pattern for SQLite database management. **Schema Version: 4**.

#### Security:
- All queries parameterized (no SQL injection)
- Foreign keys enforced (`PRAGMA foreign_keys = ON`)
- Financial fields use `INTEGER` (never `double`)

#### Schema (v4):
1. **products** — id, name, category, price (INT), purchase_price (INT), color, size, stock, barcode (legacy)
2. **categories** — id, name (UNIQUE)
3. **suspended_orders** — id, note, created_at
4. **suspended_order_items** — id, order_id FK→suspended_orders ON DELETE CASCADE, product_id, quantity
5. **product_barcodes** (v4) — id, product_id FK→products ON DELETE CASCADE, barcode (UNIQUE)

#### Key Methods:
- `insertProduct()` — Transactional: inserts product + barcodes
- `getProductByBarcode()` — JOIN query on product_barcodes
- `barcodeExists()` — Checks uniqueness in product_barcodes
- `getBarcodesForProduct()`, `addBarcode()`, `updateBarcode()`, `removeBarcode()`
- `saveSuspendedOrder()`, `getSuspendedOrders()`, `getSuspendedOrderCart()`, `deleteSuspendedOrder()`
- `getAllProducts()`, `updateProduct()`, `deleteProduct()`
- `getAllCategories()`, `insertCategory()`

#### Migration History:
- v1: products table
- v2: categories, suspended_orders, suspended_order_items
- v3: purchase_price column added to products
- v4: product_barcodes table + data migration from products.barcode

3. Suspended Orders System (v2):
   - Main order table with notes
   - Detailed items table with foreign keys
   - Cascade deletion support