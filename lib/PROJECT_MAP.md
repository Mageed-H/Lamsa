# خارطة المشروع — أحلى الحلوين (Lamsa)
## نظام نقاط بيع — محل كوزمتيك (مكياج، عطور، عناية بالبشرة)

> آخر تحديث: 2026-08-25 — DB v13 | 18 اختبار آلي ✅ | dart analyze نظيف ✅

---

## هيكل المجلدات

```
Lamsa/
├── docs/
│   └── ENCRYPTION.md                   # تعليمات تفعيل تشفير SQLCipher
├── test/                               # 18 اختبار آلي
│   ├── core/
│   │   ├── security/db_encryption_test.dart   # ترويسة SQLite + PRAGMA (5)
│   │   ├── services/pin_hash_test.dart        # الهاش والتحقق (7)
│   │   ├── services/error_logger_test.dart    # مستويات السجل (3)
│   │   └── widgets/error_boundary_test.dart   # كسر/تعافي/استعادة (3)
│   └── ...
├── Inno_setup (سطح المكتب)             # سكريبت مثبت Windows
│   ├── Ahla_Halawin_Setup.iss
│   └── build_installer.bat / quick_build.bat
│
lib/
├── main.dart                          # نقطة البداية + نسخ تلقائي يومي
├── PROJECT_MAP.md                     # هذا الملف
│
├── core/                              # اللبنة الأساسية
│   ├── database/
│   │   └── database_helper.dart       # SQLite v13 — جداول + دوال + تشفير + تحقق نسخ + تصحيح جرد
│   ├── security/
│   │   └── db_encryption.dart         # SQLCipher — مفتاح مخفي + ترحيل تلقائي + كشف نوع الملف
│   ├── services/
│   │   ├── error_logger.dart          # JSON logs — 5 مستويات + rotation يومي (30 يوم)
│   │   └── pin_hash.dart              # SHA-256 لرموز PIN
│   ├── theme/
│   │   └── app_theme.dart             # ثيم وردي
│   └── widgets/
│       ├── main_layout.dart           # 4 تبويبات + PIN + صفحة مطور مخفية + ErrorBoundary
│       ├── error_boundary.dart        # حدود أخطاء — captureError + شاشة تعافي
│       ├── paginated_list_view.dart   # widget عرض تدريجي عام
│       ├── custom_text_field.dart     # حقل إدخال مخصص
│       └── custom_button.dart         # زر مخصص
│
└── features/
    ├── pos/                           # الكاشير
    │   └── presentation/pages/pos_page.dart          # شاشة مقسمة + خصم صنف + طباعة Isolate
    │
    ├── products/                      # المخزن
    │   ├── data/models/product_model.dart
    │   └── presentation/
    │       ├── pages/products_page.dart              # CRUD + باركود متعدد + تصحيح جرد بسجل
    │       └── widgets/barcode_printer_widget.dart   # طباعة باركود
    │
    ├── sales/                         # المبيعات
    │   └── presentation/
    │       ├── pages/sales_page.dart                 # فلاتر زمنية + مرتجعات + عرض تدريجي
    │       └── widgets/weekly_sales_chart.dart       # 📊 رسم بياني 7 أيام (إيراد/ربح)
    │
    ├── debts/                         # ديون الزبائن
    │   └── presentation/pages/debts_page.dart        # تبويبان + PDF/CSV + عرض تدريجي
    │
    ├── shop_debts/                    # ديون المحل
    │   └── presentation/pages/shop_debts_page.dart   # CRUD + سجل + PDF/CSV
    │
    ├── expenses/                      # المصروفات
    │   └── presentation/pages/expenses_page.dart     # 9 تصنيفات + PDF + عرض تدريجي
    │
    ├── z_report/                      # تقرير نهاية اليوم
    │   └── presentation/pages/z_report_page.dart     # Z-Report + PDF
    │
    └── settings/                      # إعدادات المطور
        └── presentation/pages/dev_settings_page.dart # كل الإعدادات + التقارير
```

---

## قاعدة البيانات (SQLite — v13)

| الجدول | الوصف |
|--------|-------|
| `products` | المنتجات (اسم، تصنيف، لون، مقاس، سعر بيع، سعر شراء، مخزون، باركود) |
| `product_barcodes` | باركودات متعددة لكل منتج |
| `categories` | التصنيفات |
| `suspended_orders` / `_items` | الفواتير المعلقة مع الخصم |
| `sales` | فواتير المبيعات (إجمالي، أرباح، قطع، خصم) |
| `sale_items` | بنود كل فاتورة |
| `settings` | إعدادات key-value (يشمل log_level و last_auto_backup) |
| `debts` / `debt_payments` | ديون الزبائن + سجل السداد |
| `shop_debts` / `shop_debt_payments` | ديون المحل + سجل السداد |
| `expenses` | المصروفات |
| `stock_adjustments` | **v13** — سجل تصحيح الجرد (منتج، قديم←جديد، فرق، سبب، تاريخ) |

**فهارس:** الباركود، تواريخ المبيعات/الديون/المصروفات، المنتج في تصحيحات الجرد

**الأمان:** تشفير SQLCipher اختياري (`sqlcipher.dll`) + مفتاح 256-bit مخفي + ترحيل تلقائي

---

## التنقل

```
الكاشير ← → المخزن ← → المبيعات ← → الديون
```
- **صفحة المطور**: `Ctrl+Alt+Shift` ثم `devmh`
- **PIN**: للمنتجات/المبيعات/الديون (SHA-256)

---

## الميزات التفصيلية

### A. الكاشير (POS)
- شاشة مقسمة: سلة يسار + كروت منتجات يمين + فلتر تصنيفات
- باركود: حقل لوحة مفاتيح + كاميرا موبايل
- تعديل سعر (حد أدنى = سعر الشراء) + **خصم لكل صنف** + خصم فاتورة (مبلغ/نسبة)
- حماية مخزون + تنبيه مخزون منخفض (شارة + حوار + snackbar)
- تعليق/استئناف فواتير + حوار دفع بالفكة + طباعة ثيرمال على Isolate + QR + إعادة طباعة

### B. المخزن
- CRUD كامل + باركودات متعددة + توليد تلقائي + قيمة رأس المال
- **تصحيح الجرد**: حوار بأسباب جاهزة (عدّ صندوق/تلف/انتهاء صلاحية/سرقة) + سجل التعديلات + حماية من السالب

### C. تقارير المبيعات
- 6 فلاتر زمنية + بطاقات ملخص + تفاصيل فاتورة + **مرتجعات كاملة وجزئية**
- **📊 رسم بياني أعمدة آخر 7 أيام** مع تبديل إيراد ↔ ربح (fl_chart)
- عرض تدريجي (50 فاتورة) + تصدير PDF

### D. الديون (زبائن + محل)
- CRUD + سجل سداد + دفع سريع + تفاصيل + فلاتر حالة
- تصدير PDF + CSV + عرض تدريجي (30 عنصر)

### E. المصروفات
- 9 تصنيفات + تجميع يومي + PDF + عرض تدريجي (7 أيام)

### F. Z-Report
- صافي كاش + مبيعات/قطع/ربح + ديون مسددة اليوم + أفضل 5 منتجات + PDF

### G. النسخ الاحتياطي والأمان
- **تلقائي يومي** عند أول تشغيل (آخر 7 نسخ `auto_`)
- **تحقق كل نسخة**: integrity_check + جداول أساسية + بصمة SHA-256 بجانبها
- **رفض استيراد النسخ التالفة/المعدلة**
- مجلد مخفي D:\.lamsa_backup + WAL checkpoint

### H. الجودة والموثوقية
- **ErrorBoundary** حول كل تبويب — `captureError()` + شاشة تعافي أنيقة
- **ErrorLogger**: JSON structured + 5 مستويات (DEBUG→CRITICAL) + rotation 30 يوم + إعداد المستوى من الواجهة
- **18 اختبار آلي** (PinHash, DbEncryption, LogLevel, ErrorBoundary)
- إشعارات منفصلة لكل صفحة + Offstage

### I. إعدادات المطور
- بيانات المحل، التصنيفات، عتبة المخزون، كل إعدادات الطباعة (فاتورة+باركود+طابعتان مستقلتان)، QR، PINs، نسخ احتياطي، مستوى السجل، رابط Z-Report

---

## أدوات البناء والتوزيع

| الأداة | المسار |
|--------|--------|
| مثبت Windows (Inno Setup 7) | `Desktop\Inno_setup\Ahla_Halawin_Setup.iss` |
| المخرج النهائي | `Desktop\final_files\Ahla_Alhalawin_Setup_v1.0.0.exe` |
| بناء كامل | `build_installer.bat` — flutter clean → build → ISCC |
| تشفير DB | ضع `sqlcipher.dll` بجانب exe — راجع `docs/ENCRYPTION.md` |

---

## ما لم يُنفذ بعد (اختياري)

- صور المنتجات
- اختصارات لوحة مفاتيح للكاشير
- وضع داكن
- تصدير Excel (xlsx)
- تعدد المستخدمين بصلاحيات
- إدارة زبائن مستقلة (CRM)
