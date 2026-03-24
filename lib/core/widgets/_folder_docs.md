# Core Widgets Documentation

## Files Overview

### custom_button.dart
- `CustomButton` — Reusable button with icon, label, `Flexible` wrapping to prevent overflow. Uses `mainAxisSize: MainAxisSize.min`.

### custom_text_field.dart
- `CustomTextField` — Standardized text input field with styling, validation, optional `focusNode` and `onSubmitted` support for scanner integration.

### main_layout.dart
- `MainLayout` — The primary application shell. Implements `BottomNavigationBar` for routing with `IndexedStack` to preserve child page state (e.g., keeping POS cart active while browsing inventory).