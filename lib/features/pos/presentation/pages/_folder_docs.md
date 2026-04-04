# POS Pages Documentation

## File: pos_page.dart

### PosPage Widget (StatefulWidget)
Main POS interface with continuous barcode scanning capability.

#### Key Components:
- Line 13-15: Controllers and focus management
- Line 17: Cart management (current invoice)
- Line 20-27: Automatic focus initialization
- Line 35-57: Barcode scanning handler
  - Product lookup
  - Cart updates
  - Error handling
- Line 60-63: Focus maintenance
- Line 66-73: Precise financial calculations
- Line 76+: UI layout with:
  - Persistent barcode input
  - Real-time cart display
  - Total amount calculation