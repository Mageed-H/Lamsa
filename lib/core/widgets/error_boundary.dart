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

  @override
  State<ErrorBoundary> createState() => _ErrorBoundaryState();
}

class _ErrorBoundaryState extends State<ErrorBoundary> {
  Object? _error;
  StackTrace? _stack;

  @override
  void initState() {
    super.initState();
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
      color: Colors.white,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              Text(
                'تعذر تحميل ${pageName ?? "هذه الصفحة"}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                error.toString(),
                style: const TextStyle(color: Colors.grey, fontSize: 12),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton.icon(
                    onPressed: () {
                      ErrorLogger.instance.log('User copied error details', level: LogLevel.info);
                      // نسخ للclipboard
                    },
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('نسخ التفاصيل'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}