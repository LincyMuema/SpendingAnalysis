import 'package:flutter/material.dart';
import 'api_service.dart';

class AnalysisScreen extends StatefulWidget {
  final int userId;
  const AnalysisScreen({super.key, required this.userId});

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Map<String, dynamic>? _data;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadAnalysis();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAnalysis() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final result = await ApiService.getAnalysis(userId: widget.userId);
      setState(() {
        _data = result;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  String _fmt(double v) {
    if (v >= 1000000) return 'KSh ${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return 'KSh ${(v / 1000).toStringAsFixed(1)}k';
    return 'KSh ${v.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5FA),
      appBar: AppBar(
        title: const Text(
          'AI Analysis',
          style: TextStyle(
              color: Color(0xFF1A1A2E),
              fontWeight: FontWeight.bold,
              fontSize: 20),
        ),
        backgroundColor: const Color(0xFFF5F5FA),
        elevation: 0,
        actions: [
          if (!_isLoading)
            IconButton(
              icon: const Icon(Icons.refresh, color: Color(0xFF5B2EFF)),
              onPressed: _loadAnalysis,
            ),
        ],
        bottom: _data != null
            ? TabBar(
                controller: _tabController,
                labelColor: const Color(0xFF5B2EFF),
                unselectedLabelColor: Colors.black38,
                indicatorColor: const Color(0xFF5B2EFF),
                indicatorWeight: 2,
                labelStyle: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600),
                tabs: const [
                  Tab(text: 'Insights'),
                  Tab(text: 'Habits'),
                  Tab(text: 'Anomalies'),
                  Tab(text: 'Forecast'),
                ],
              )
            : null,
      ),
      body: _isLoading
          ? _buildLoading()
          : _error != null
              ? _buildError()
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _InsightsTab(data: _data!),
                    _ClustersTab(data: _data!, fmt: _fmt),
                    _AnomaliesTab(data: _data!, fmt: _fmt),
                    _ForecastTab(data: _data!, fmt: _fmt),
                  ],
                ),
    );
  }

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: Color(0xFF5B2EFF)),
          const SizedBox(height: 16),
          Text(
            'Running AI analysis…',
            style: TextStyle(color: Colors.black45, fontSize: 14),
          ),
          const SizedBox(height: 6),
          Text(
            'This may take a few seconds',
            style: TextStyle(color: Colors.black26, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    final isInsufficient = _error!.contains('5 are required') ||
        _error!.contains('insufficient') ||
        _error!.contains('valid transaction');
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isInsufficient
                  ? Icons.bar_chart_outlined
                  : Icons.error_outline,
              color: Colors.black26,
              size: 56,
            ),
            const SizedBox(height: 16),
            Text(
              isInsufficient
                  ? 'Not enough data yet'
                  : 'Analysis failed',
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A2E)),
            ),
            const SizedBox(height: 8),
            Text(
              isInsufficient
                  ? 'Add at least 5 transactions to unlock AI analysis of your spending patterns.'
                  : _error!,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(color: Colors.black45, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadAnalysis,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF5B2EFF),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Insights Tab ────────────────────────────────────────────────────────────

class _InsightsTab extends StatefulWidget {
  final Map<String, dynamic> data;
  const _InsightsTab({required this.data});

  @override
  State<_InsightsTab> createState() => _InsightsTabState();
}

class _InsightsTabState extends State<_InsightsTab> {
  static const int _previewCount = 3;
  bool _showAllInsights = false;
  bool _showAllRecs = false;

  Widget _section({
    required List<String> items,
    required bool expanded,
    required VoidCallback onToggle,
    required bool isInsight,
    required Color color,
  }) {
    final visible = expanded ? items : items.take(_previewCount).toList();
    final hidden = items.length - _previewCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...visible.asMap().entries.map(
              (e) => _InsightCard(
                index: e.key + 1,
                text: e.value,
                isInsight: isInsight,
              ),
            ),
        if (hidden > 0)
          Center(
            child: TextButton.icon(
              onPressed: onToggle,
              icon: Icon(
                expanded ? Icons.expand_less : Icons.expand_more,
                color: color,
                size: 20,
              ),
              label: Text(
                expanded ? 'Show less' : 'Show $hidden more',
                style: TextStyle(color: color, fontWeight: FontWeight.w600),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final insights = List<String>.from(data['insights'] ?? []);
    final recs = List<String>.from(data['recommendations'] ?? []);
    final txCount = data['transaction_count'] as int? ?? 0;
    final timestamp = data['analysis_timestamp'] as String? ?? '';

    String timeLabel = '';
    if (timestamp.isNotEmpty) {
      try {
        final dt = DateTime.parse(timestamp);
        timeLabel =
            '${dt.day}/${dt.month}/${dt.year} at ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      } catch (_) {}
    }

    const insightColor = Color(0xFFFF9800);
    const recColor = Color(0xFF5B2EFF);

    return RefreshIndicator(
      color: recColor,
      onRefresh: () async {},
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Chip(
                icon: Icons.receipt_long_outlined,
                label: '$txCount transactions',
              ),
              if (timeLabel.isNotEmpty)
                _Chip(icon: Icons.access_time, label: timeLabel),
            ],
          ),
          const SizedBox(height: 20),

          // What we noticed
          const _SectionHeader(
            icon: Icons.lightbulb_outline,
            label: 'What we noticed',
            color: insightColor,
          ),
          const SizedBox(height: 10),
          _section(
            items: insights,
            expanded: _showAllInsights,
            onToggle: () =>
                setState(() => _showAllInsights = !_showAllInsights),
            isInsight: true,
            color: insightColor,
          ),

          if (recs.isNotEmpty) ...[
            const SizedBox(height: 16),
            const _SectionHeader(
              icon: Icons.tips_and_updates_outlined,
              label: 'What you can do',
              color: recColor,
            ),
            const SizedBox(height: 10),
            _section(
              items: recs,
              expanded: _showAllRecs,
              onToggle: () => setState(() => _showAllRecs = !_showAllRecs),
              isInsight: false,
              color: recColor,
            ),
          ],
        ],
      ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  final int index;
  final String text;
  final bool isInsight;
  const _InsightCard(
      {required this.index, required this.text, required this.isInsight});

  @override
  Widget build(BuildContext context) {
    final color =
        isInsight ? const Color(0xFFFF9800) : const Color(0xFF5B2EFF);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                '$index',
                style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                  color: Color(0xFF1A1A2E), fontSize: 13, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Habits Tab (formerly Clusters) ──────────────────────────────────────────

class _ClustersTab extends StatelessWidget {
  final Map<String, dynamic> data;
  final String Function(double) fmt;
  const _ClustersTab({required this.data, required this.fmt});

  @override
  Widget build(BuildContext context) {
    final clustering =
        Map<String, dynamic>.from(data['spending_clusters'] ?? {});
    final clusters =
        Map<String, dynamic>.from(clustering['clusters'] ?? {});

    if (clusters.isEmpty) {
      return _EmptyState(
          icon: Icons.donut_large_outlined,
          message: 'No spending habits found yet',
          subtext: 'Add more transactions and check back.');
    }

    const clusterColors = [
      Color(0xFF5B2EFF),
      Color(0xFF00BCD4),
      Color(0xFFFF9800),
      Color(0xFF4CAF50),
      Color(0xFFE91E63),
    ];

    final list = clusters.values
        .map((v) => Map<String, dynamic>.from(v as Map))
        .toList();

    double numOf(Map<String, dynamic> c, String k) =>
        (c[k] as num?)?.toDouble() ?? 0;

    final totalAll = list.fold<double>(0, (s, c) => s + numOf(c, 'total_spend_kes'));
    final avgs = list.map((c) => numOf(c, 'avg_amount_kes')).toList();
    final maxAvg = avgs.reduce((a, b) => a > b ? a : b);
    final minAvg = avgs.reduce((a, b) => a < b ? a : b);

    // Order by share of money, biggest first
    list.sort((a, b) =>
        numOf(b, 'total_spend_kes').compareTo(numOf(a, 'total_spend_kes')));

    String habitName(double avg) {
      if (list.length > 1 && avg == maxAvg) return 'Big purchases';
      if (list.length > 1 && avg == minAvg) return 'Small everyday spends';
      return 'Regular spending';
    }

    String whenText(double pctWeekend) {
      if (pctWeekend >= 50) return 'Mostly on weekends';
      if (pctWeekend <= 15) return 'Mostly on weekdays';
      return 'Spread across the week';
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        const _SectionHeader(
          icon: Icons.donut_large_outlined,
          label: 'How you spend',
          color: Color(0xFF5B2EFF),
        ),
        const SizedBox(height: 6),
        const Text(
          'We grouped your payments into habits, so you can see where your money goes.',
          style: TextStyle(color: Colors.black45, fontSize: 12, height: 1.4),
        ),
        const SizedBox(height: 16),
        ...list.asMap().entries.map((entry) {
          final idx = entry.key;
          final c = entry.value;
          final color = clusterColors[idx % clusterColors.length];

          final txCount = c['transaction_count'] as int? ?? 0;
          final avg = numOf(c, 'avg_amount_kes');
          final total = numOf(c, 'total_spend_kes');
          final pctWeekend = numOf(c, 'pct_weekend');
          final topCat = c['top_category'] as String? ?? 'Other';
          final share = totalAll > 0 ? total / totalAll : 0.0;

          return Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2))
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration:
                          BoxDecoration(color: color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        habitName(avg),
                        style: const TextStyle(
                            color: Color(0xFF1A1A2E),
                            fontWeight: FontWeight.bold,
                            fontSize: 15),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        topCat,
                        style: TextStyle(
                            color: color,
                            fontSize: 11,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  '${(share * 100).toStringAsFixed(0)}% of your spending  •  ${fmt(total)}',
                  style: TextStyle(
                      color: color, fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: share.clamp(0.0, 1.0),
                    minHeight: 8,
                    backgroundColor: color.withOpacity(0.1),
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '$txCount payments, usually around ${fmt(avg)} each. ${whenText(pctWeekend)}.',
                  style: const TextStyle(
                      color: Colors.black54, fontSize: 12, height: 1.5),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

// ── Anomalies Tab ────────────────────────────────────────────────────────────

class _AnomaliesTab extends StatefulWidget {
  final Map<String, dynamic> data;
  final String Function(double) fmt;
  const _AnomaliesTab({required this.data, required this.fmt});

  @override
  State<_AnomaliesTab> createState() => _AnomaliesTabState();
}

class _AnomaliesTabState extends State<_AnomaliesTab> {
  late List<Map<String, dynamic>> _anomalies;
  late int _total;
  final Set<int> _busy = {};

  void _readData() {
    final anomaly =
        Map<String, dynamic>.from(widget.data['anomaly_detection'] ?? {});
    _total = anomaly['total_transactions'] as int? ?? 0;
    _anomalies = List<Map<String, dynamic>>.from(
        (anomaly['anomalies'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map)));
  }

  @override
  void initState() {
    super.initState();
    _readData();
  }

  @override
  void didUpdateWidget(covariant _AnomaliesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) _readData();
  }

  Future<void> _dismiss(Map<String, dynamic> a) async {
    final id = a['transaction_id'] as int;
    setState(() => _busy.add(id));
    try {
      await ApiService.dismissAnomaly(transactionId: id);
      if (!mounted) return;
      setState(() {
        _anomalies.removeWhere((x) => x['transaction_id'] == id);
        _busy.remove(id);
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Marked as normal. It will not be flagged again.')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy.remove(id));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', ''))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = widget.fmt;
    final count = _anomalies.length;
    final rate = _total > 0 ? count / _total * 100 : 0.0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        // Summary card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: count == 0
                  ? [
                      const Color(0xFF4CAF50).withOpacity(0.9),
                      const Color(0xFF2E7D32).withOpacity(0.8)
                    ]
                  : [
                      const Color(0xFFFF6B35).withOpacity(0.9),
                      const Color(0xFFE53935).withOpacity(0.8)
                    ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Icon(
                count == 0
                    ? Icons.verified_outlined
                    : Icons.warning_amber_outlined,
                color: Colors.white,
                size: 36,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      count == 0
                          ? 'All Clear'
                          : '$count Unusual Transaction${count > 1 ? 's' : ''}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      count == 0
                          ? 'All $_total transactions look normal'
                          : '${rate.toStringAsFixed(1)}% of your $_total transactions',
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        if (_anomalies.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text(
            'Recognise one of these? Tap "Not unusual" and it will not be flagged again.',
            style: TextStyle(color: Colors.black45, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 12),
          _SectionHeader(
            icon: Icons.search_outlined,
            label: 'Flagged Transactions',
            color: const Color(0xFFE53935),
          ),
          const SizedBox(height: 10),
          ..._anomalies.map((a) {
            final id = a['transaction_id'] as int? ?? -1;
            final amount = (a['amount'] as num?)?.toDouble() ?? 0;
            final date = a['date'] as String? ?? '';
            final category = a['category'] as String? ?? 'Other';
            final source = a['source'] as String? ?? '';
            final score = (a['anomaly_score'] as num?)?.toDouble() ?? 0;
            // Score is negative: more negative = more unusual
            final severity =
                score < -0.1 ? 'High' : score < 0 ? 'Medium' : 'Low';
            final sevColor = score < -0.1
                ? const Color(0xFFE53935)
                : score < 0
                    ? const Color(0xFFFF9800)
                    : const Color(0xFF4CAF50);
            final busy = _busy.contains(id);

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: sevColor.withOpacity(0.25), width: 1),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 6,
                      offset: const Offset(0, 2))
                ],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: sevColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.warning_amber_rounded,
                            color: sevColor, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(category,
                                style: const TextStyle(
                                    color: Color(0xFF1A1A2E),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14)),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Text(date,
                                    style: const TextStyle(
                                        color: Colors.black45, fontSize: 12)),
                                if (source.isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  Text(source,
                                      style: const TextStyle(
                                          color: Colors.black38,
                                          fontSize: 11)),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(fmt(amount),
                              style: const TextStyle(
                                  color: Color(0xFF1A1A2E),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14)),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: sevColor.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(severity,
                                style: TextStyle(
                                    color: sevColor,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: busy || id < 0 ? null : () => _dismiss(a),
                      icon: busy
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.check_circle_outline, size: 16),
                      label: const Text('Not unusual'),
                      style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF4CAF50)),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ],
    );
  }
}

// ── Forecast Tab ─────────────────────────────────────────────────────────────

class _ForecastTab extends StatelessWidget {
  final Map<String, dynamic> data;
  final String Function(double) fmt;
  const _ForecastTab({required this.data, required this.fmt});

  @override
  Widget build(BuildContext context) {
    final prediction =
        Map<String, dynamic>.from(data['spending_prediction'] ?? {});
    final status = prediction['status'] as String? ?? '';
    final predictions =
        List<Map<String, dynamic>>.from(prediction['predictions'] ?? []);
    final avgWeekly =
        (prediction['average_weekly_spend_kes'] as num?)?.toDouble() ?? 0;
    final weeksHistory = prediction['weeks_of_history'] as int? ?? 0;

    if (status != 'ok' || predictions.isEmpty) {
      final msg = prediction['message'] as String? ??
          'Not enough weekly history yet to make a forecast.';
      return _EmptyState(
        icon: Icons.timeline_outlined,
        message: msg,
        subtext:
            'Record transactions across at least 4 weeks to unlock spending forecasts.',
      );
    }

    // Find max for bar scaling
    final maxPred = predictions
        .map((p) => (p['predicted_spend_kes'] as num?)?.toDouble() ?? 0)
        .reduce((a, b) => a > b ? a : b);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        // Summary row
        Row(
          children: [
            Expanded(
              child: _SummaryCard(
                icon: Icons.history,
                label: 'Weeks of History',
                value: '$weeksHistory weeks',
                color: const Color(0xFF5B2EFF),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SummaryCard(
                icon: Icons.show_chart,
                label: 'Avg Weekly Spend',
                value: fmt(avgWeekly),
                color: const Color(0xFF00BCD4),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        _SectionHeader(
          icon: Icons.psychology_outlined,
          label: '4-Week Forecast',
          color: const Color(0xFF5B2EFF),
        ),
        const SizedBox(height: 4),
        const Text(
          'Predicted using Random Forest Regression on your historical weekly data.',
          style: TextStyle(color: Colors.black45, fontSize: 12, height: 1.4),
        ),
        const SizedBox(height: 16),

        // Bar chart area
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2))
            ],
          ),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: predictions.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final p = entry.value;
                  final amount =
                      (p['predicted_spend_kes'] as num?)?.toDouble() ?? 0;
                  final label = p['week_label'] as String? ?? 'Week ${idx + 1}';
                  // "Week of 03 Nov 2026" → "3 Nov"
                  final shortLabel = _shortWeekLabel(label, idx);
                  final barH = maxPred > 0 ? (amount / maxPred) * 120 : 20.0;

                  const barColor = Color(0xFF5B2EFF);

                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        children: [
                          Text(
                            fmt(amount),
                            style: const TextStyle(
                                color: Color(0xFF1A1A2E),
                                fontSize: 10,
                                fontWeight: FontWeight.w600),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 6),
                          Container(
                            height: barH.clamp(16.0, 120.0),
                            decoration: BoxDecoration(
                              color: idx == 0
                                  ? barColor
                                  : barColor.withOpacity(0.45 - idx * 0.05),
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            shortLabel,
                            style: const TextStyle(
                                color: Colors.black38,
                                fontSize: 10),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
              const Divider(height: 1, color: Colors.black12),
              const SizedBox(height: 10),
              Row(
                children: [
                  Container(
                    width: 10, height: 10,
                    decoration: BoxDecoration(
                        color: const Color(0xFF5B2EFF),
                        borderRadius: BorderRadius.circular(2)),
                  ),
                  const SizedBox(width: 6),
                  const Text('Next week',
                      style: TextStyle(fontSize: 11, color: Colors.black45)),
                  const SizedBox(width: 16),
                  Container(
                    width: 10, height: 10,
                    decoration: BoxDecoration(
                        color: const Color(0xFF5B2EFF).withOpacity(0.3),
                        borderRadius: BorderRadius.circular(2)),
                  ),
                  const SizedBox(width: 6),
                  const Text('Weeks 2–4',
                      style: TextStyle(fontSize: 11, color: Colors.black45)),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // Detail list
        _SectionHeader(
          icon: Icons.calendar_today_outlined,
          label: 'Weekly Breakdown',
          color: const Color(0xFF5B2EFF),
        ),
        const SizedBox(height: 10),
        ...predictions.asMap().entries.map((entry) {
          final idx = entry.key;
          final p = entry.value;
          final amount =
              (p['predicted_spend_kes'] as num?)?.toDouble() ?? 0;
          final label = p['week_label'] as String? ?? 'Week ${idx + 1}';
          final diff = avgWeekly > 0
              ? ((amount - avgWeekly) / avgWeekly * 100)
              : 0.0;
          final isHigh = diff > 10;
          final isLow = diff < -10;

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: idx == 0
                  ? Border.all(
                      color: const Color(0xFF5B2EFF).withOpacity(0.4),
                      width: 1.5)
                  : null,
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 2))
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFF5B2EFF)
                        .withOpacity(idx == 0 ? 0.15 : 0.07),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(
                      'W${idx + 1}',
                      style: TextStyle(
                          color: const Color(0xFF5B2EFF),
                          fontSize: 12,
                          fontWeight: idx == 0
                              ? FontWeight.bold
                              : FontWeight.w500),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                            color: Color(0xFF1A1A2E),
                            fontWeight: FontWeight.w600,
                            fontSize: 13),
                      ),
                      if (avgWeekly > 0) ...[
                        const SizedBox(height: 3),
                        Text(
                          isHigh
                              ? '${diff.abs().toStringAsFixed(0)}% above your avg'
                              : isLow
                                  ? '${diff.abs().toStringAsFixed(0)}% below your avg'
                                  : 'In line with your avg',
                          style: TextStyle(
                            color: isHigh
                                ? const Color(0xFFE53935)
                                : isLow
                                    ? const Color(0xFF4CAF50)
                                    : Colors.black38,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Text(
                  fmt(amount),
                  style: const TextStyle(
                      color: Color(0xFF1A1A2E),
                      fontWeight: FontWeight.bold,
                      fontSize: 15),
                ),
              ],
            ),
          );
        }),

        const SizedBox(height: 12),
        const Text(
          '* Forecasts are estimates based on historical patterns and may not reflect future events.',
          style: TextStyle(color: Colors.black26, fontSize: 11, height: 1.4),
        ),
      ],
    );
  }

  String _shortWeekLabel(String label, int idx) {
    // "Week of 03 Nov 2026" → "3 Nov"
    try {
      final parts = label.replaceAll('Week of ', '').split(' ');
      if (parts.length >= 2) {
        return '${int.parse(parts[0])} ${parts[1]}';
      }
    } catch (_) {}
    return 'Wk ${idx + 1}';
  }
}

// ── Shared helper widgets ────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _SectionHeader(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
              color: color, fontWeight: FontWeight.bold, fontSize: 14),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Chip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.black38),
          const SizedBox(width: 5),
          Text(label,
              style: const TextStyle(color: Colors.black54, fontSize: 12)),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatTile(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style:
                    const TextStyle(color: Colors.black38, fontSize: 11)),
            const SizedBox(height: 4),
            Text(value,
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _SummaryCard(
      {required this.icon,
      required this.label,
      required this.value,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(label,
              style:
                  const TextStyle(color: Colors.black45, fontSize: 11)),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 15)),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? subtext;
  const _EmptyState({required this.icon, required this.message, this.subtext});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.black26, size: 56),
            const SizedBox(height: 16),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 15,
                    color: Colors.black45,
                    height: 1.5)),
            if (subtext != null) ...[
              const SizedBox(height: 8),
              Text(subtext!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 12,
                      color: Colors.black26,
                      height: 1.4)),
            ],
          ],
        ),
      ),
    );
  }
}