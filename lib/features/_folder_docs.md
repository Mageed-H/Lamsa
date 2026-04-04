# Features Module Documentation

This directory contains the main feature modules of the application:

## Modules
- `pos/` — Point of Sale (cashier): barcode scanning, cart, payment, invoice printing, suspended orders, discount, reprint last invoice
- `products/` — Product management: CRUD, multi-barcode, category management, barcode label printing (separate printer)
- `sales/` — Sales tracking: filtered reports (today/week/month/range/all), PDF export to Desktop, invoice detail view, partial & full returns with stock restoration, capital display
- `settings/` — Developer settings (hidden): store info, print settings, paper dimensions, two printers (receipt + barcode), PIN codes, database backup/import

Each feature follows Clean Architecture with its own data/presentation layers.