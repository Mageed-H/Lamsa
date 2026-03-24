# Database Module Documentation

## File: database_helper.dart

### Class: DatabaseHelper
Singleton pattern for SQLite database management. **Schema Version: 5**.

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
6. **sales** (v5) — id, total_amount (INT), total_profit (INT), items_count (INT), created_at (TEXT), indexed on created_at
7. **sale_items** (v5) — id, sale_id FK→sales ON DELETE CASCADE, product_id, product_name (TEXT snapshot), quantity, unit_price, purchase_price

#### Key Methods:
- `insertProduct()` — Transactional: inserts product + barcodes
- `getProductByBarcode()` — JOIN query on product_barcodes
- `barcodeExists()` — Checks uniqueness in product_barcodes
- `getBarcodesForProduct()`, `addBarcode()`, `updateBarcode()`, `removeBarcode()`
- `saveSuspendedOrder()`, `getSuspendedOrders()`, `getSuspendedOrderCart()`, `deleteSuspendedOrder()`
- `completeSale()` — Transactional: inserts sale + sale_items + deducts stock
- `getAllSales()`, `getTodaySales()`, `getSaleItems()`, `getSalesSummary()`
- `getAllProducts()`, `updateProduct()`, `deleteProduct()`
- `getAllCategories()`, `insertCategory()`

#### Migration History:
- v1: products table
- v2: categories, suspended_orders, suspended_order_items
- v3: purchase_price column added to products
- v4: product_barcodes table + data migration from products.barcode
- v5: sales + sale_items tables for completed transactions

3. Suspended Orders System (v2):
   - Main order table with notes
   - Detailed items table with foreign keys
   - Cascade deletion support