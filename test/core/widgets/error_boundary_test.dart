import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lamsa/core/widgets/error_boundary.dart';

void main() {
  testWidgets('ErrorBoundary يعرض الابن بشكل طبيعي عند عدم وجود خطأ', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ErrorBoundary(
          pageName: 'اختبار',
          child: Text('المحتوى الطبيعي'),
        ),
      ),
    );

    expect(find.text('المحتوى الطبيعي'), findsOneWidget);
  });

  testWidgets('captureError يعرض شاشة التعافي بدل الابن', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ErrorBoundary(
          pageName: 'صفحة الاختبار',
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => ErrorBoundary.maybeOf(context)!
                  .captureError(StateError('خطأ تجريبي')),
              child: const Text('كسر'),
            ),
          ),
        ),
      ),
    );

    // قبل الخطأ: المحتوى ظاهر
    expect(find.text('كسر'), findsOneWidget);

    // نطلق الخطأ
    await tester.tap(find.text('كسر'));
    await tester.pumpAndSettle();

    // شاشة التعافي ظهرت مع اسم الصفحة
    expect(find.text('تعذر تحميل صفحة الاختبار'), findsOneWidget);
    expect(find.text('إعادة المحاولة'), findsOneWidget);
    // والمحتوى اختفى
    expect(find.text('كسر'), findsNothing);
  });

  testWidgets('زر إعادة المحاولة يستعيد المحتوى', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ErrorBoundary(
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => ErrorBoundary.maybeOf(context)!
                  .captureError(Exception('x')),
              child: const Text('كسر'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('كسر'));
    await tester.pumpAndSettle();
    expect(find.text('تعذر تحميل هذه الصفحة'), findsOneWidget);

    // إعادة المحاولة → يعود الابن
    await tester.tap(find.text('إعادة المحاولة'));
    await tester.pumpAndSettle();
    expect(find.text('كسر'), findsOneWidget);
    expect(find.text('تعذر تحميل هذه الصفحة'), findsNothing);
  });
}
