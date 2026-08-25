import 'package:flutter/material.dart';
import 'package:lamsa/core/services/error_logger.dart';

class ErrorBoundary extends StatefulWidget {
  final Widget child;
  final String? pageName;
  final Widget Function(BuildContext, Object, StackTrace?)? fallbackBuilder;
  final void Function(Object, StackTrace?)? onError;

  const ErrorBoundary({
    Key? key,
    required this.child,
    this.pageName,
    this.fallbackBuilder,
    this.onError,
  }) : super(key: key);

  /// الوصول لحالة الحدود من أي widget ابن
  ///
  /// الاستخدام: `ErrorBoundary.maybeOf(context)?.captureError(e, st)`
  static ErrorBoundaryState? maybeOf(BuildContext context) =>
      context.findAncestorStateOfType<ErrorBoundaryState>();

  @override
  State<ErrorBoundary> createState() => ErrorBoundaryState();
}

class ErrorBoundaryState extends State<ErrorBoundary> {
  Object? _error;
  StackTrace? _stack;

  /// التقاط خطأ وعرض شاشة التعافي بدل كسر التطبيق
  void captureError(Object error, [StackTrace? stack]) {
    if (!mounted) return;
    setState(() {
      _error = error;
      _stack = stack;
    });
    ErrorLogger.instance.logError(error, stack, context: widget.pageName);
    widget.onError?.call(error, stack);
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      if (widget.fallbackBuilder != null) {
        return widget.fallbackBuilder!(context, _error!, _stack);
      }
      return _DefaultErrorFallback(
        error: _error!,
        stack: _stack,
        pageName: widget.pageName,
        onRetry: () => setState(() {
          _error = null;
          _stack = null;
        }),
      );
    }
    return widget.child;
  }
}

class _DefaultErrorFallback extends StatelessWidget {
  final Object error;
  final StackTrace? stack;
  final String? pageName;
  final VoidCallback onRetry;

  const _DefaultErrorFallback({
    required this.error,
    this.stack,
    this.pageName,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.grey.shade50,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.red.shade600,
                    size: 40,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'حدث خطأ',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade900,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'تعذر تحميل ${pageName ?? "هذه الصفحة"}',
                  style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: SelectableText(
                    error.toString(),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.start,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          ErrorLogger.instance.info('نسخ المستخدم لتفاصيل الخطأ');
                        },
                        icon: const Icon(Icons.content_copy_rounded, size: 18),
                        label: const Text('نسخ التفاصيل'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          side: BorderSide(color: Colors.grey.shade300),
                          foregroundColor: Colors.grey.shade700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: onRetry,
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('إعادة المحاولة'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          backgroundColor: const Color(0xFFE91E63),
                          foregroundColor: Colors.white,
                          elevation: 0,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
