import 'package:flutter/material.dart';

typedef PaginatedLoader<T> = Future<List<T>> Function(int page, int pageSize);
typedef ItemBuilder<T> = Widget Function(BuildContext context, T item, int index);

class PaginatedListView<T> extends StatefulWidget {
  final PaginatedLoader<T> loader;
  final ItemBuilder<T> itemBuilder;
  final int pageSize;
  final Widget? emptyWidget;
  final Widget? errorWidget;
  final EdgeInsetsGeometry? padding;
  final bool shrinkWrap;
  final ScrollPhysics? physics;
  final bool addAutomaticKeepAlives;
  final bool addRepaintBoundaries;
  final bool addSemanticIndexes;
  final double? cacheExtent;

  const PaginatedListView({
    Key? key,
    required this.loader,
    required this.itemBuilder,
    this.pageSize = 20,
    this.emptyWidget,
    this.errorWidget,
    this.padding,
    this.shrinkWrap = false,
    this.physics,
    this.addAutomaticKeepAlives = true,
    this.addRepaintBoundaries = true,
    this.addSemanticIndexes = true,
    this.cacheExtent,
  }) : super(key: key);

  @override
  State<PaginatedListView<T>> createState() => _PaginatedListViewState<T>();
}

class _PaginatedListViewState<T> extends State<PaginatedListView<T>> {
  final List<T> _items = [];
  int _currentPage = 0;
  bool _isLoading = false;
  bool _hasMore = true;
  Object? _error;

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadMore();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_isLoading &&
        _hasMore &&
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadMore({bool refresh = false}) async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      _error = null;
      if (refresh) {
        _currentPage = 0;
        _items.clear();
        _hasMore = true;
      }
    });

    try {
      final newItems = await widget.loader(_currentPage, widget.pageSize);
      if (!mounted) return;

      setState(() {
        if (refresh || _currentPage == 0) {
          _items.clear();
        }
        _items.addAll(newItems);
        _hasMore = newItems.length >= widget.pageSize;
        _currentPage++;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _isLoading = false;
      });
    }
  }

  Future<void> _refresh() async {
    await _loadMore(refresh: true);
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty && _isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_items.isEmpty && _error != null) {
      return widget.errorWidget ??
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    'فشل التحميل: $_error',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh),
                    label: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            ),
          );
    }

    if (_items.isEmpty) {
      return widget.emptyWidget ??
          const Center(
            child: Text(
              'لا توجد بيانات',
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
          );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        controller: _scrollController,
        padding: widget.padding,
        shrinkWrap: widget.shrinkWrap,
        physics: widget.physics,
        addAutomaticKeepAlives: widget.addAutomaticKeepAlives,
        addRepaintBoundaries: widget.addRepaintBoundaries,
        addSemanticIndexes: widget.addSemanticIndexes,
        cacheExtent: widget.cacheExtent,
        itemCount: _items.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _items.length) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ),
            );
          }
          return widget.itemBuilder(context, _items[index], index);
        },
      ),
    );
  }
}