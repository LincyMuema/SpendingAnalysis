import 'package:flutter/material.dart';
import 'api_service.dart';
import 'app_events.dart';

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
    _tabController = TabController(length: 5, vsync: this);
    _loadAnalysis();
    // The Home insight card can ask for a specific tab
    AppEvents.openAnalysisTab.addListener(_onOpenTab);
  }

  @override
  void dispose() {
    AppEvents.openAnalysisTab.removeListener(_onOpenTab);
    _tabController.dispose();
    super.dispose();
  }

  void _onOpenTab() {
    final tab = AppEvents.openAnalysisTab.value;
    if (tab != null && tab >= 0 && tab < 5) _tabController.animateTo(tab);
  }

  void _openTabByName(String? name) {
    final tab = AnalysisTabs.fromName(name);
    if (tab != null) _tabController.animateTo(tab);
  }

  Future<void> _loadAnalysis() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      // Insights describe the last 3 months; Habits can switch period itself
      final result = await ApiService.getAnalysis(userId: widget.userId, days: 90);
      if (!mounted) return;
      setState(() {
        _data = result;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
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
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelStyle: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600),
                tabs: const [
                  Tab(text: 'Insights'),
                  Tab(text: 'Habits'),
                  Tab(text: 'Recurring'),
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
                    _InsightsTab(data: _data!, onOpenTab: _openTabByName),
                    _ClustersTab(data: _data!, fmt: _fmt),
                    _RecurringTab(data: _data!, fmt: _fmt),
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
// One ranked list: each card says what we noticed and what to do about it,
// most important first. Tapping a card opens the tab with the details.

class _InsightsTab extends StatefulWidget {
  final Map<String, dynamic> data;
  final void Function(String? tab) onOpenTab;
  const _InsightsTab({required this.data, required this.onOpenTab});

  @override
  State<_InsightsTab> createState() => _InsightsTabState();
}

class _InsightsTabState extends State<_InsightsTab> {
  static const int _previewCount = 5;
  bool _showAll = false;

  static const _styles = {
    'alert': (Icons.warning_amber_rounded, Color(0xFFFF9800)),
    'forecast': (Icons.trending_up_rounded, Color(0xFF5B2EFF)),
    'subscription': (Icons.autorenew_rounded, Color(0xFFE91E63)),
    'category': (Icons.pie_chart_outline, Color(0xFF00BCD4)),
    'habit': (Icons.donut_large_outlined, Color(0xFF4CAF50)),
    'info': (Icons.info_outline, Color(0xFF9E9E9E)),
  };

  @override
  Widget build(BuildContext context) {
    final cards = List<Map<String, dynamic>>.from(
        (widget.data['insight_cards'] as List? ?? [])
            .map((c) => Map<String, dynamic>.from(c as Map)));

    // Older backend: fall back to the plain list of insights
    if (cards.isEmpty) {
      for (final text in List<String>.from(widget.data['insights'] ?? [])) {
        cards.add({'type': 'info', 'title': text, 'detail': '', 'action': null, 'tab': null});
      }
    }
    if (cards.isEmpty) {
      return _EmptyState(
          icon: Icons.lightbulb_outline,
          message: 'No insights yet',
          subtext: 'Add more transactions and check back.');
    }

    final visible = _showAll ? cards : cards.take(_previewCount).toList();
    final hidden = cards.length - _previewCount;
    final period = Map<String, dynamic>.from(widget.data['period'] ?? {});
    final txCount = widget.data['transaction_count'] as int? ?? 0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Text(
          period['start'] != null
              ? 'Last 3 months: $txCount transactions, ${period['start']} to ${period['end']}. Most important first.'
              : 'Most important first.',
          style: const TextStyle(color: Colors.black45, fontSize: 12),
        ),
        const SizedBox(height: 12),
        ...visible.map((c) {
          final style = _styles[c['type']] ?? _styles['info']!;
          final icon = style.$1;
          final color = style.$2;
          final tab = c['tab'] as String?;
          final action = c['action'] as String?;
          final detail = (c['detail'] as String?) ?? '';

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: tab == null ? null : () => widget.onOpenTab(tab),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border(left: BorderSide(color: color, width: 4)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(icon, color: color, size: 19),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(c['title'] as String? ?? '',
                                style: const TextStyle(
                                    color: Color(0xFF1A1A2E),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                    height: 1.3)),
                            if (detail.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(detail,
                                  style: const TextStyle(
                                      color: Colors.black54, fontSize: 12.5, height: 1.4)),
                            ],
                            if (action != null && action.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.tips_and_updates_outlined, size: 14, color: color),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(action,
                                        style: TextStyle(
                                            color: color,
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w600,
                                            height: 1.4)),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (tab != null)
                        const Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: Icon(Icons.chevron_right, color: Colors.black26),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
        if (hidden > 0)
          Center(
            child: TextButton.icon(
              onPressed: () => setState(() => _showAll = !_showAll),
              icon: Icon(_showAll ? Icons.expand_less : Icons.expand_more,
                  color: const Color(0xFF5B2EFF), size: 20),
              label: Text(_showAll ? 'Show less' : 'Show $hidden more',
                  style: const TextStyle(
                      color: Color(0xFF5B2EFF), fontWeight: FontWeight.w600)),
            ),
          ),
      ],
    );
  }
}

// ── Recurring Tab ────────────────────────────────────────────────────────────
// Regular payments to the same payee (subscriptions, rent, bills), found by
// rules in the backend: same payee, similar amount, regular gap.

class _RecurringTab extends StatelessWidget {
  final Map<String, dynamic> data;
  final String Function(double) fmt;
  const _RecurringTab({required this.data, required this.fmt});

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                          'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  String _date(String? iso) {
    final d = DateTime.tryParse(iso ?? '');
    return d == null ? '' : '${d.day} ${_months[d.month - 1]}';
  }

  Widget _badge(String text, Color color) => Container(
        margin: const EdgeInsets.only(right: 6, top: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text,
            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      );

  @override
  Widget build(BuildContext context) {
    final rec = Map<String, dynamic>.from(data['recurring_payments'] ?? {});
    final items = List<Map<String, dynamic>>.from(
        (rec['payments'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)));

    if (items.isEmpty) {
      return _EmptyState(
          icon: Icons.autorenew_rounded,
          message: 'No regular payments found yet',
          subtext:
              'Payments to the same place for a similar amount every week or month will appear here. '
              'At least two payments are needed.');
    }

    double num_(Map<String, dynamic> m, String k) => (m[k] as num?)?.toDouble() ?? 0;
    const pink = Color(0xFFE91E63);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        // Summary
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: pink,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Regular payments',
                  style: TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 4),
              Text('${fmt(num_(rec, 'monthly_total_kes'))} a month',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                  '${rec['active_count'] ?? items.length} active  •  ${fmt(num_(rec, 'yearly_total_kes'))} a year',
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Found from your history: the same payee, a similar amount, at a regular interval. '
          'Cancel any you no longer use.',
          style: TextStyle(color: Colors.black45, fontSize: 12, height: 1.4),
        ),
        const SizedBox(height: 14),

        ...items.map((r) {
          final status = r['status'] as String? ?? 'active';
          final change = r['price_change'] as Map?;
          final stopped = status == 'may_have_stopped';

          return Opacity(
            opacity: stopped ? 0.6 : 1,
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
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
                      Expanded(
                        child: Text(r['name'] as String? ?? '',
                            style: const TextStyle(
                                color: Color(0xFF1A1A2E),
                                fontWeight: FontWeight.bold,
                                fontSize: 15)),
                      ),
                      Text(fmt(num_(r, 'usual_amount_kes')),
                          style: const TextStyle(
                              color: Color(0xFF1A1A2E),
                              fontWeight: FontWeight.bold,
                              fontSize: 15)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${r['frequency']}  •  ${r['category']}  •  ${fmt(num_(r, 'yearly_cost_kes'))} a year',
                    style: const TextStyle(color: Colors.black54, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    stopped
                        ? 'Last paid ${_date(r['last_date'] as String?)}. No payment since, so it may have stopped.'
                        : 'Last paid ${_date(r['last_date'] as String?)}  •  next expected around ${_date(r['next_expected_date'] as String?)}',
                    style: const TextStyle(color: Colors.black45, fontSize: 12),
                  ),
                  Wrap(
                    children: [
                      if (status == 'due_soon') _badge('Due soon', const Color(0xFFFF9800)),
                      if (r['is_new'] == true) _badge('New', const Color(0xFF5B2EFF)),
                      if (change != null)
                        _badge(
                            'Price ${(change['to'] as num) > (change['from'] as num) ? 'up' : 'down'}: '
                            '${fmt((change['from'] as num).toDouble())} → ${fmt((change['to'] as num).toDouble())}',
                            (change['to'] as num) > (change['from'] as num)
                                ? const Color(0xFFE53935)
                                : const Color(0xFF4CAF50)),
                      if (stopped) _badge('May have stopped', Colors.black45),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}

// ── Habits Tab (formerly Clusters) ──────────────────────────────────────────

class _ClustersTab extends StatefulWidget {
  final Map<String, dynamic> data;
  final String Function(double) fmt;
  const _ClustersTab({required this.data, required this.fmt});

  @override
  State<_ClustersTab> createState() => _ClustersTabState();
}

class _ClustersTabState extends State<_ClustersTab> {
  // The backend sends habits for each period, so switching is instant
  static const _periods = {30: '1 month', 90: '3 months', 180: '6 months', 365: '1 year'};
  int _days = 90;

  Map<String, dynamic> get data => widget.data;
  String Function(double) get fmt => widget.fmt;

  Widget _periodChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _periods.entries.map((p) {
        final selected = _days == p.key;
        return ChoiceChip(
          label: Text(p.value),
          selected: selected,
          showCheckmark: false,
          selectedColor: const Color(0xFF5B2EFF),
          backgroundColor: Colors.white,
          labelStyle: TextStyle(
            color: selected ? Colors.white : Colors.black54,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
          side: BorderSide(color: selected ? const Color(0xFF5B2EFF) : Colors.black12),
          onSelected: (_) => setState(() => _days = p.key),
        );
      }).toList(),
    );
  }

  static const _colors = [
    Color(0xFF5B2EFF),
    Color(0xFF00BCD4),
    Color(0xFFFF9800),
    Color(0xFF4CAF50),
    Color(0xFFE91E63),
  ];

  static IconData _iconFor(String name) {
    final n = name.toLowerCase();
    if (n.contains('big')) return Icons.shopping_bag_outlined;
    if (n.contains('bill')) return Icons.receipt_long_outlined;
    if (n.contains('weekend')) return Icons.weekend_outlined;
    if (n.contains('first-time')) return Icons.fiber_new_outlined;
    if (n.contains('small')) return Icons.local_cafe_outlined;
    return Icons.payments_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final clustering = Map<String, dynamic>.from(data['spending_clusters'] ?? {});
    final byPeriod = Map<String, dynamic>.from(clustering['by_period'] ?? {});
    final periodData = byPeriod['$_days'] != null
        ? Map<String, dynamic>.from(byPeriod['$_days'] as Map)
        : null;
    // Older backend without periods: use the single set of clusters
    final clusters = Map<String, dynamic>.from(
        (periodData?['clusters'] ?? clustering['clusters'] ?? {}) as Map);

    if (clusters.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          if (byPeriod.isNotEmpty) _periodChips(),
          const SizedBox(height: 40),
          _EmptyState(
              icon: Icons.donut_large_outlined,
              message: 'No spending habits in this period',
              subtext: 'Choose a longer period or add more transactions.'),
        ],
      );
    }

    double numOf(Map<String, dynamic> c, String k) => (c[k] as num?)?.toDouble() ?? 0;

    final list = clusters.values.map((v) => Map<String, dynamic>.from(v as Map)).toList()
      // Biggest share of money first
      ..sort((a, b) => numOf(b, 'total_spend_kes').compareTo(numOf(a, 'total_spend_kes')));

    final totalAll = list.fold<double>(0, (s, c) => s + numOf(c, 'total_spend_kes'));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        const _SectionHeader(
          icon: Icons.donut_large_outlined,
          label: 'Your spending habits',
          color: Color(0xFF5B2EFF),
        ),
        const SizedBox(height: 6),
        const Text(
          'Payments that look alike (similar amount, timing and type) are grouped into habits. '
          'Biggest share of your money first.',
          style: TextStyle(color: Colors.black45, fontSize: 12, height: 1.4),
        ),
        if (byPeriod.isNotEmpty) ...[
          const SizedBox(height: 12),
          _periodChips(),
        ],
        if (periodData != null) ...[
          const SizedBox(height: 10),
          Text(
            '${periodData['transaction_count']} payments, '
            '${fmt((periodData['total_spend_kes'] as num).toDouble())} in total',
            style: const TextStyle(
                color: Color(0xFF1A1A2E), fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
        const SizedBox(height: 16),
        ...list.asMap().entries.map((entry) {
          final color = _colors[entry.key % _colors.length];
          final c = entry.value;

          final name = c['habit_name'] as String? ?? 'Spending habit';
          final count = c['transaction_count'] as int? ?? 0;
          final total = numOf(c, 'total_spend_kes');
          final share = c['share_of_spend_pct'] != null
              ? numOf(c, 'share_of_spend_pct') / 100
              : (totalAll > 0 ? total / totalAll : 0.0);
          final low = numOf(c, 'typical_low_kes');
          final high = numOf(c, 'typical_high_kes');
          final avg = numOf(c, 'avg_amount_kes');
          final day = c['busiest_day'] as String?;
          final time = c['typical_time'] as String?;
          final source = c['main_source'] as String?;
          final cats = List<Map<String, dynamic>>.from(
              (c['top_categories'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)) ??
                  [
                    {'name': c['top_category'] ?? 'Other', 'pct': 100}
                  ]);
          final merchants = List<String>.from(c['top_merchants'] ?? const []);

          // "65 payments, usually KSh 800–1.8k, most often on Saturday, mostly by card."
          final parts = <String>[
            '$count payment${count == 1 ? '' : 's'}',
            (low > 0 && high > 0 && high > low)
                ? 'usually ${fmt(low)}–${fmt(high)}'
                : 'about ${fmt(avg)} each',
            if (day != null) 'most often on ${day}s',
            if (time != null) time,
            if (source != null) 'mostly by $source',
          ];
          final summary = '${parts.join(', ')}.';

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
                // Name and share of money
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(_iconFor(name), color: color, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(name,
                          style: const TextStyle(
                              color: Color(0xFF1A1A2E),
                              fontWeight: FontWeight.bold,
                              fontSize: 15)),
                    ),
                    Text('${(share * 100).toStringAsFixed(0)}%',
                        style: TextStyle(
                            color: color, fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: share.clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor: color.withOpacity(0.1),
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
                const SizedBox(height: 6),
                Text('${fmt(total)} of your spending',
                    style: const TextStyle(color: Colors.black45, fontSize: 11)),
                const SizedBox(height: 12),

                // What, when, how
                Text(summary,
                    style: const TextStyle(
                        color: Color(0xFF1A1A2E), fontSize: 13, height: 1.45)),
                const SizedBox(height: 10),

                // Category mix
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: cats
                      .map((cat) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text('${cat['name']} ${cat['pct']}%',
                                style: TextStyle(
                                    color: color,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600)),
                          ))
                      .toList(),
                ),

                // Example places
                if (merchants.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.storefront_outlined, size: 14, color: Colors.black38),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(merchants.join(', '),
                            style: const TextStyle(color: Colors.black54, fontSize: 12)),
                      ),
                    ],
                  ),
                ],
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
      AppEvents.notifyTransactionsChanged(); // lets the Home card update
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
            final time = a['time'] as String?;
            final category = a['category'] as String? ?? 'Other';
            final payee = a['counterparty'] as String?;
            final reasons = List<String>.from(a['reasons'] ?? const []);
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
                            Text(
                                payee != null && payee.isNotEmpty
                                    ? '$payee · $category'
                                    : category,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Color(0xFF1A1A2E),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14)),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Text(time != null ? '$date, $time' : date,
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
                  // Why it was flagged, in plain words
                  if (reasons.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    ...reasons.map((r) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.info_outline,
                                  size: 14, color: sevColor),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(r,
                                    style: const TextStyle(
                                        color: Colors.black54,
                                        fontSize: 12,
                                        height: 1.3)),
                              ),
                            ],
                          ),
                        )),
                  ],
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

  static const _purple = Color(0xFF5B2EFF);
  static const _orange = Color(0xFFFF9800);
  static const _pink = Color(0xFFE91E63);
  static const _red = Color(0xFFE53935);
  static const _green = Color(0xFF4CAF50);
  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                          'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  double _num(dynamic v) => (v as num?)?.toDouble() ?? 0;
  String _day(DateTime d) => '${d.day} ${_months[d.month - 1]}';

  /// The coming 4 weeks. The model forecasts the total for the 4 weeks;
  /// regular payments (rent, subscriptions...) are placed in the week they are
  /// due, and the rest of the forecast (everyday spending) is spread evenly.
  List<_ComingWeek> _comingWeeks(DateTime start, double total) {
    final weeks = List.generate(4, (i) {
      final s = start.add(Duration(days: 7 * i));
      return _ComingWeek(start: s, end: s.add(const Duration(days: 6)));
    });
    final windowEnd = weeks.last.end;

    final rec = Map<String, dynamic>.from(data['recurring_payments'] ?? {});
    for (final raw in (rec['payments'] as List? ?? [])) {
      final r = Map<String, dynamic>.from(raw as Map);
      if (r['status'] == 'may_have_stopped') continue;
      final next = DateTime.tryParse(r['next_expected_date'] as String? ?? '');
      if (next == null) continue;
      DateTime due = next;
      final amount = _num(r['usual_amount_kes']);
      final name = r['name'] as String? ?? '';
      final freq = (r['frequency'] as String? ?? '').toLowerCase();
      // Every expected payment that falls inside the 4 weeks
      while (!due.isAfter(windowEnd)) {
        if (!due.isBefore(start)) {
          for (final w in weeks) {
            if (!due.isAfter(w.end)) {
              w.regular.add((name: name, amount: amount, due: due));
              break;
            }
          }
        }
        if (freq.startsWith('weekly')) {
          due = due.add(const Duration(days: 7));
        } else if (freq.contains('2 weeks')) {
          due = due.add(const Duration(days: 14));
        } else {
          due = DateTime(due.year, due.month + 1, due.day);
        }
      }
    }

    final regularTotal = weeks.fold<double>(0, (s, w) => s + w.regularTotal);
    final everyday = ((total - regularTotal) / 4).clamp(0.0, double.infinity);
    for (final w in weeks) {
      w.everyday = everyday;
    }
    return weeks;
  }

  Widget _card({required Widget child, Color? borderColor}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: borderColor != null ? Border.all(color: borderColor, width: 1.5) : null,
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    final prediction =
        Map<String, dynamic>.from(data['spending_prediction'] ?? {});
    final status = prediction['status'] as String? ?? '';
    final forecast = Map<String, dynamic>.from(prediction['forecast'] ?? {});
    final avgWeekly = _num(prediction['average_weekly_spend_kes']);
    final start = DateTime.tryParse(forecast['start_date'] as String? ?? '');

    if (status != 'ok' || forecast.isEmpty || start == null) {
      final msg = prediction['message'] as String? ??
          'Not enough weekly history yet to make a forecast.';
      return _EmptyState(
        icon: Icons.timeline_outlined,
        message: msg,
        subtext:
            'Record transactions across at least 4 weeks to unlock spending forecasts.',
      );
    }

    final total = _num(forecast['total_kes']);
    final perWeek = _num(forecast['weekly_avg_kes']);
    final low = _num(forecast['low_kes']) * 4;
    final high = _num(forecast['high_kes']) * 4;
    final change = _num(forecast['change_vs_usual_pct']);
    final usualTotal = avgWeekly * 4;

    final weeks = _comingWeeks(start, total);
    final bills = [for (final w in weeks) ...w.regular]
      ..sort((a, b) => a.due.compareTo(b.due));
    final billsTotal = bills.fold<double>(0, (s, b) => s + b.amount);

    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    String weekLabel(_ComingWeek w) =>
        !todayDate.isBefore(w.start) && !todayDate.isAfter(w.end)
            ? 'This week'
            : _day(w.start);

    // How this compares with a usual 4 weeks, in plain words
    final (String compareText, Color compareColor, IconData compareIcon) = change >= 5
        ? ('${change.toStringAsFixed(0)}% more than your usual ${fmt(usualTotal)}',
            change > 10 ? _red : Colors.black54, Icons.trending_up_rounded)
        : change <= -5
            ? ('${change.abs().toStringAsFixed(0)}% less than your usual ${fmt(usualTotal)}',
                change < -10 ? _green : Colors.black54, Icons.trending_down_rounded)
            : ('About the same as your usual ${fmt(usualTotal)}',
                Colors.black54, Icons.trending_flat_rounded);

    // Bars: scale so both the tallest week and the average line fit
    final maxBar = weeks.map((w) => w.total).reduce((a, b) => a > b ? a : b);
    final scaleMax = maxBar > avgWeekly ? maxBar : avgWeekly;
    const barArea = 110.0;
    final avgLineY = scaleMax > 0 ? (avgWeekly / scaleMax) * barArea : 0.0;
    double h(double v) => scaleMax > 0 ? v / scaleMax * barArea : 0.0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        // ── 1. The answer: what the next 4 weeks will probably cost ──────────
        _card(
          borderColor: _purple.withOpacity(0.35),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.psychology_outlined, color: _purple, size: 18),
                  const SizedBox(width: 6),
                  Text('Next 4 weeks  •  ${_day(weeks.first.start)} – ${_day(weeks.last.end)}',
                      style: const TextStyle(
                          color: Colors.black54, fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 10),
              Text('About ${fmt(total)}',
                  style: const TextStyle(
                      color: Color(0xFF1A1A2E), fontSize: 26, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text('roughly ${fmt(perWeek)} a week',
                  style: const TextStyle(color: Colors.black54, fontSize: 13)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: compareColor.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(compareIcon, size: 16, color: compareColor),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(compareText,
                          style: TextStyle(
                              color: compareColor, fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
              if (low > 0 && high > 0) ...[
                const SizedBox(height: 10),
                Text('Most likely between ${fmt(low)} and ${fmt(high)}',
                    style: const TextStyle(color: Colors.black45, fontSize: 12)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),

        // ── 2. Week by week ─────────────────────────────────────────────────
        _SectionHeader(
          icon: Icons.bar_chart_rounded,
          label: 'Week by Week',
          color: _purple,
        ),
        const SizedBox(height: 10),
        _card(
          child: Column(
            children: [
              SizedBox(
                height: barArea + 22,
                child: Stack(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: weeks.map((w) {
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Text(fmt(w.total),
                                    style: const TextStyle(
                                        color: Color(0xFF1A1A2E),
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600),
                                    textAlign: TextAlign.center),
                                const SizedBox(height: 6),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (w.regularTotal > 0)
                                        Container(height: h(w.regularTotal), color: _pink),
                                      Container(
                                          height: h(w.everyday).clamp(4.0, barArea),
                                          color: _purple.withOpacity(0.75)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    if (avgWeekly > 0)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: avgLineY - 1,
                        child: const _DashedLine(color: _orange),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: weeks
                    .map((w) => Expanded(
                          child: Text(weekLabel(w),
                              style: const TextStyle(color: Colors.black45, fontSize: 10),
                              textAlign: TextAlign.center),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 14),
              const Divider(height: 1, color: Colors.black12),
              const SizedBox(height: 10),
              Wrap(
                spacing: 14,
                runSpacing: 6,
                children: [
                  _legend(Container(
                      width: 10, height: 10,
                      decoration: BoxDecoration(
                          color: _purple.withOpacity(0.75),
                          borderRadius: BorderRadius.circular(2))),
                      'Everyday spending'),
                  if (bills.isNotEmpty)
                    _legend(Container(
                        width: 10, height: 10,
                        decoration: BoxDecoration(
                            color: _pink, borderRadius: BorderRadius.circular(2))),
                        'Bills due'),
                  if (avgWeekly > 0)
                    _legend(const SizedBox(width: 16, child: _DashedLine(color: _orange)),
                        'Your usual week (${fmt(avgWeekly)})'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // ── 3. Bills coming up ──────────────────────────────────────────────
        if (bills.isNotEmpty) ...[
          _SectionHeader(
            icon: Icons.event_outlined,
            label: 'Bills Coming Up',
            color: _pink,
          ),
          const SizedBox(height: 4),
          Text(
            '${fmt(billsTotal)} of the forecast is regular payments you have made before.',
            style: const TextStyle(color: Colors.black45, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 10),
          _card(
            child: Column(
              children: bills.asMap().entries.map((e) {
                final b = e.value;
                final daysAway = b.due.difference(todayDate).inDays;
                final when = daysAway < 0
                    ? 'Was due ${_day(b.due)}'
                    : daysAway == 0
                        ? 'Due today'
                        : daysAway == 1
                            ? 'Due tomorrow'
                            : 'Due ${_weekdays[b.due.weekday - 1]} ${_day(b.due)}';
                return Column(
                  children: [
                    if (e.key > 0) const Divider(height: 18, color: Colors.black12),
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: _pink.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.autorenew_rounded, color: _pink, size: 18),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(b.name,
                                  style: const TextStyle(
                                      color: Color(0xFF1A1A2E),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13)),
                              const SizedBox(height: 2),
                              Text(when,
                                  style: TextStyle(
                                      color: daysAway <= 3 ? _orange : Colors.black45,
                                      fontSize: 11,
                                      fontWeight: daysAway <= 3
                                          ? FontWeight.w600
                                          : FontWeight.normal)),
                            ],
                          ),
                        ),
                        Text(fmt(b.amount),
                            style: const TextStyle(
                                color: Color(0xFF1A1A2E),
                                fontWeight: FontWeight.bold,
                                fontSize: 14)),
                      ],
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 20),
        ],

        // ── 4. What to do with it ───────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _purple.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.tips_and_updates_outlined, size: 18, color: _purple),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  change > 10
                      ? 'The coming weeks look more expensive than usual. Set aside ${fmt(total)} '
                          'and check whether any large expenses can wait.'
                      : bills.isNotEmpty
                          ? 'Set aside ${fmt(billsTotal)} for the bills above, and keep everyday '
                              'spending to about ${fmt(weeks.first.everyday)} a week.'
                          : 'Aim to keep spending to about ${fmt(perWeek)} a week to stay on track.',
                  style: const TextStyle(color: Color(0xFF1A1A2E), fontSize: 12.5, height: 1.45),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          '* The 4-week total is predicted with Random Forest Regression from your spending history. '
          'Bills are placed in the week they are due and everyday spending is spread evenly. '
          'Forecasts are estimates and may not include unplanned expenses.',
          style: TextStyle(color: Colors.black26, fontSize: 11, height: 1.4),
        ),
      ],
    );
  }

  Widget _legend(Widget swatch, String text) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          swatch,
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(fontSize: 11, color: Colors.black45)),
        ],
      );
}

/// One of the coming weeks in the forecast.
class _ComingWeek {
  final DateTime start;
  final DateTime end;
  double everyday = 0;
  final List<({String name, double amount, DateTime due})> regular = [];
  _ComingWeek({required this.start, required this.end});

  double get regularTotal => regular.fold<double>(0, (s, r) => s + r.amount);
  double get total => everyday + regularTotal;
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

/// A thin horizontal dashed line (used for the average on the forecast chart).
class _DashedLine extends StatelessWidget {
  final Color color;
  const _DashedLine({required this.color});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const dash = 6.0, gap = 4.0;
        final count = (constraints.maxWidth / (dash + gap)).floor().clamp(1, 1000);
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(
            count,
            (_) => SizedBox(
              width: dash,
              height: 2,
              child: DecoratedBox(decoration: BoxDecoration(color: color)),
            ),
          ),
        );
      },
    );
  }
}