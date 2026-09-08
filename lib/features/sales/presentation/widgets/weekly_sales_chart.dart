import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:cashier_system/core/database/database_helper.dart';
import 'package:cashier_system/core/theme/app_theme.dart';

/// رسم بياني أعمدة — مبيعات وأرباح آخر [days] يوم
class WeeklySalesChart extends StatefulWidget {
  final int days;

  const WeeklySalesChart({Key? key, this.days = 7}) : super(key: key);

  @override
  State<WeeklySalesChart> createState() => _WeeklySalesChartState();
}

class _WeeklySalesChartState extends State<WeeklySalesChart> {
  List<Map<String, dynamic>> _data = [];
  bool _isLoading = true;
  bool _showProfit = false; // false = الإيراد، true = الربح

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await DatabaseHelper.instance.getDailySalesChart(days: widget.days);
    if (mounted) {
      setState(() {
        _data = data;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.bar_chart, color: AppTheme.primaryColor, size: 24),
                const SizedBox(width: 8),
                Text(
                  _showProfit ? 'أرباح آخر ${widget.days} أيام' : 'مبيعات آخر ${widget.days} أيام',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                ),
                const Spacer(),
                // تبديل بين الإيراد والربح
                ToggleButtons(
                  isSelected: [_showProfit == false, _showProfit == true],
                  onPressed: (i) => setState(() => _showProfit = i == 1),
                  borderRadius: BorderRadius.circular(8),
                  selectedColor: Colors.white,
                  fillColor: AppTheme.primaryColor,
                  color: AppTheme.textSecondary,
                  constraints: const BoxConstraints(minHeight: 30, minWidth: 50),
                  children: const [
                    Text('إيراد', style: TextStyle(fontSize: 12)),
                    Text('ربح', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_data.isEmpty)
              const Center(child: Text('لا توجد بيانات', style: TextStyle(color: AppTheme.textSecondary)))
            else
              SizedBox(
                height: 200,
                child: BarChart(
                  BarChartData(
                    alignment: BarChartAlignment.spaceAround,
                    maxY: _maxValue * 1.2,
                    barTouchData: BarTouchData(
                      touchTooltipData: BarTouchTooltipData(
                        getTooltipItem: (group, groupIndex, rod, rodIndex) {
                          final day = _data[group.x.toInt()];
                          final v = _showProfit ? day['profit'] : day['revenue'];
                          return BarTooltipItem(
                            '${day['label']}\n$v د.ع',
                            const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                          );
                        },
                      ),
                    ),
                    titlesData: FlTitlesData(
                      leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (v, meta) => Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              _data[v.toInt()]['label'] as String,
                              style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
                            ),
                          ),
                        ),
                      ),
                    ),
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      horizontalInterval: _maxValue / 4,
                      getDrawingHorizontalLine: (v) => FlLine(color: Colors.grey.shade200, strokeWidth: 1),
                    ),
                    borderData: FlBorderData(show: false),
                    barGroups: _data.asMap().entries.map((entry) {
                      final i = entry.key;
                      final d = entry.value;
                      final value = (_showProfit ? d['profit'] : d['revenue']) as int;
                      final isToday = i == _data.length - 1;
                      return BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: value.toDouble(),
                            width: 18,
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                            color: value == 0
                                ? Colors.grey.shade300
                                : isToday
                                    ? (_showProfit ? AppTheme.successColor : AppTheme.primaryColor)
                                    : (_showProfit
                                        ? AppTheme.successColor.withValues(alpha: 0.5)
                                        : AppTheme.primaryColor.withValues(alpha: 0.5)),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
            // إجمالي الفترة
            const SizedBox(height: 8),
            Center(
              child: Text(
                'الإجمالي: $_totalValue د.ع',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: _showProfit ? AppTheme.successColor : AppTheme.primaryColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double get _maxValue {
    var max = 0;
    for (final d in _data) {
      final v = (_showProfit ? d['profit'] : d['revenue']) as int;
      if (v > max) max = v;
    }
    return max <= 0 ? 100 : max.toDouble();
  }

  int get _totalValue {
    var sum = 0;
    for (final d in _data) {
      sum += (_showProfit ? d['profit'] : d['revenue']) as int;
    }
    return sum;
  }
}
