import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'transactions_screen.dart';
import 'analysis_screen.dart';
import 'api_service.dart';
import 'app_events.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  final String fullName;
  final int userId;
  final String? email;
  const HomeScreen(
      {super.key, required this.fullName, required this.userId, this.email});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      _HomeBody(
        fullName: widget.fullName,
        userId: widget.userId,
        onOpenProfile: () => setState(() => _selectedIndex = 3),
      ),
      TransactionsScreen(userId: widget.userId, ownName: widget.fullName),
      AnalysisScreen(userId: widget.userId),
      ProfileScreen(
          fullName: widget.fullName,
          userId: widget.userId,
          email: widget.email),
    ];
    AppEvents.openAnalysisTab.addListener(_goToAnalysis);
  }

  @override
  void dispose() {
    AppEvents.openAnalysisTab.removeListener(_goToAnalysis);
    super.dispose();
  }

  // The Home insight card opens the Analysis tab
  void _goToAnalysis() {
    if (AppEvents.openAnalysisTab.value != null && mounted) {
      setState(() => _selectedIndex = 2);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5FA),
      body: IndexedStack(
        index: _selectedIndex,
        children: _screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: const Color(0xFFF5F5FA),
        selectedItemColor: const Color(0xFF5B2EFF),
        unselectedItemColor: Colors.black38,
        // 4 tabs: "fixed" keeps the background and colours above
        // (with 4+ items Flutter otherwise switches to "shifting" style)
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.receipt_long_outlined),
            activeIcon: Icon(Icons.receipt_long),
            label: 'Transactions',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.insights_outlined),
            activeIcon: Icon(Icons.insights),
            label: 'Analysis',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

// ── Home body ─────────────────────────────────────────────────────────────────
class _HomeBody extends StatefulWidget {
  final String fullName;
  final int userId;
  final VoidCallback onOpenProfile;
  const _HomeBody({
    required this.fullName,
    required this.userId,
    required this.onOpenProfile,
  });

  @override
  State<_HomeBody> createState() => _HomeBodyState();
}

class _HomeBodyState extends State<_HomeBody> {
  List<Map<String, dynamic>> _transactions = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _loadHighlight();
    // Refresh automatically after SMS sync, manual add or category edit
    AppEvents.transactionsChanged.addListener(_refresh);
    // Update the greeting when the name is changed in Profile
    AppEvents.fullName.addListener(_onNameChanged);
  }

  @override
  void dispose() {
    AppEvents.transactionsChanged.removeListener(_refresh);
    AppEvents.fullName.removeListener(_onNameChanged);
    super.dispose();
  }

  void _onNameChanged() {
    if (mounted) setState(() {});
  }

  String get _name => AppEvents.fullName.value ?? widget.fullName;

  void _refresh() {
    _load(silent: true);
    _loadHighlight();
  }

  // ── Highlight card (one item from the analysis) ───────────────────────────
  // Loaded separately so Home never waits for the models to run.
  Map<String, dynamic>? _analysis;
  bool _analysisLoading = true;

  Future<void> _loadHighlight() async {
    try {
      final a = await ApiService.getAnalysis(userId: widget.userId);
      if (!mounted) return;
      setState(() {
        _analysis = a;
        _analysisLoading = false;
      });
    } catch (_) {
      // e.g. fewer than 5 transactions: just hide the card
      if (!mounted) return;
      setState(() {
        _analysis = null;
        _analysisLoading = false;
      });
    }
  }

  static const _shortMonths = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                               'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  String _shortDate(String iso) {
    final d = DateTime.tryParse(iso);
    return d == null ? iso : '${d.day} ${_shortMonths[d.month - 1]}';
  }

  /// Picks the most useful single item: an unusual transaction first,
  /// then the forecast, then the top insight.
  Widget _highlightCard() {
    if (_analysisLoading) {
      return _HighlightCard(
        icon: Icons.auto_awesome,
        color: const Color(0xFF5B2EFF),
        title: 'Analysing your spending…',
        subtitle: 'This can take a moment the first time.',
        loading: true,
        onTap: null,
      );
    }
    final a = _analysis;
    if (a == null) return const SizedBox.shrink();

    final anomalies = List<Map<String, dynamic>>.from(
        (a['anomaly_detection'] ?? {})['anomalies'] ?? []);
    if (anomalies.isNotEmpty) {
      final top = anomalies.first;
      final n = anomalies.length;
      return _HighlightCard(
        icon: Icons.warning_amber_rounded,
        color: const Color(0xFFFF9800),
        title: n == 1
            ? '1 transaction looks unusual'
            : '$n transactions look unusual',
        subtitle:
            '${_fmt((top['amount'] as num).toDouble())} on ${top['category']}, ${_shortDate(top['date'] as String)}. Tap to review.',
        onTap: () => AppEvents.openAnalysis(AnalysisTabs.anomalies),
      );
    }

    final prediction = Map<String, dynamic>.from(a['spending_prediction'] ?? {});
    final forecast = Map<String, dynamic>.from(prediction['forecast'] ?? {});
    if (prediction['status'] == 'ok' && forecast.isNotEmpty) {
      final next = (forecast['weekly_avg_kes'] as num).toDouble();
      final avg = (prediction['average_weekly_spend_kes'] as num?)?.toDouble() ?? 0;
      final diff = (forecast['change_vs_usual_pct'] as num?)?.toDouble() ?? 0.0;
      final compare = diff > 10
          ? '${diff.toStringAsFixed(0)}% above your usual ${_fmt(avg)}'
          : diff < -10
              ? '${diff.abs().toStringAsFixed(0)}% below your usual ${_fmt(avg)}'
              : 'In line with your usual ${_fmt(avg)} a week';
      return _HighlightCard(
        icon: Icons.trending_up_rounded,
        color: const Color(0xFF5B2EFF),
        title: 'Next 4 weeks: about ${_fmt(next)} a week',
        subtitle: '$compare. Tap for the forecast.',
        onTap: () => AppEvents.openAnalysis(AnalysisTabs.forecast),
      );
    }

    final insights = List<String>.from(a['insights'] ?? []);
    if (insights.isEmpty) return const SizedBox.shrink();
    return _HighlightCard(
      icon: Icons.lightbulb_outline,
      color: const Color(0xFF00BCD4),
      title: 'Insight',
      subtitle: insights.first,
      onTap: () => AppEvents.openAnalysis(AnalysisTabs.insights),
    );
  }

  Future<void> _load({bool silent = false}) async {
    if (!mounted) return;
    if (!silent) setState(() { _isLoading = true; _error = null; });
    try {
      final txs = await ApiService.getTransactions(userId: widget.userId);
      if (!mounted) return;
      setState(() { _transactions = txs; _isLoading = false; });
    } catch (err) {
      if (!mounted) return;
      setState(() { _error = err.toString(); _isLoading = false; });
    }
  }

  String get _firstName => _name.trim().split(' ').first;

  String get _initials {
    final parts = _name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    final letters = parts.take(2).map((p) => p[0]).join().toUpperCase();
    return letters.isEmpty ? '?' : letters;
  }

  // ── Month being viewed (defaults to the current month) ─────────────────────
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _month.year == now.year && _month.month == now.month;
  }

  // Earliest month that has a transaction
  DateTime get _earliestMonth {
    DateTime? first;
    for (final t in _transactions) {
      final d = DateTime.tryParse((t['date'] as String).split(' ')[0]);
      if (d != null && (first == null || d.isBefore(first))) first = d;
    }
    first ??= DateTime.now();
    return DateTime(first.year, first.month);
  }

  bool get _canGoBack => _month.isAfter(_earliestMonth);

  void _changeMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
  }

  int get _daysInMonth => DateTime(_month.year, _month.month + 1, 0).day;

  // ── Computed stats (selected month only) ──────────────────────────────────
  List<Map<String, dynamic>> get _monthTx {
    final prefix =
        '${_month.year}-${_month.month.toString().padLeft(2, '0')}';
    return _transactions
        .where((t) => (t['date'] as String).startsWith(prefix))
        .toList();
  }

  double get _totalSpent =>
      _monthTx.fold(0.0, (sum, t) => sum + (t['amount'] as num).toDouble());

  // Average per calendar day: days so far (this month) or all days (past month)
  double get _dailyAvg {
    final days = _isCurrentMonth ? DateTime.now().day : _daysInMonth;
    return days > 0 ? _totalSpent / days : 0;
  }

  int get _daysRemaining =>
      _isCurrentMonth ? _daysInMonth - DateTime.now().day : 0;

  // Projection only makes sense for the month in progress
  double get _projected => _isCurrentMonth
      ? _totalSpent + (_dailyAvg * _daysRemaining)
      : _totalSpent;

  String get _monthLabel {
    const months = [
      'January','February','March','April','May','June',
      'July','August','September','October','November','December'
    ];
    final name = months[_month.month - 1];
    return _month.year == DateTime.now().year ? name : '$name ${_month.year}';
  }

  String _fmt(double v) {
    if (v >= 1000000) return 'KSh ${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return 'KSh ${(v / 1000).toStringAsFixed(1)}k';
    return 'KSh ${v.toStringAsFixed(0)}';
  }

  // e.g. "26 Oct – 1 Nov"
  String get _weekRangeLabel {
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    final sunday = monday.add(const Duration(days: 6));
    return '${monday.day} ${m[monday.month - 1]} – ${sunday.day} ${m[sunday.month - 1]}';
  }

  double get _weekTotal => _weeklyBars.fold(0.0, (a, b) => a + b) * 1000;

  // Weekly bars: spending per day Mon–Sun of current week (in KSh thousands)
  List<double> get _weeklyBars {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final week = List.generate(7, (i) {
      final day = monday.add(Duration(days: i));
      return '${day.year}-${day.month.toString().padLeft(2,'0')}-${day.day.toString().padLeft(2,'0')}';
    });
    return week.map((d) {
      final dayTotal = _transactions
          .where((t) => (t['date'] as String).startsWith(d))
          .fold(0.0, (s, t) => s + (t['amount'] as num).toDouble());
      return dayTotal / 1000;
    }).toList();
  }

  List<Map<String, dynamic>> get _topCategories =>
      _allCategories.take(4).toList();

  // All categories this month: group, sum, sort
  List<Map<String, dynamic>> get _allCategories {
    final Map<String, double> totals = {};
    for (final t in _monthTx) {
      final cat = (t['category_name'] as String?) ?? 'Other';
      totals[cat] = (totals[cat] ?? 0) + (t['amount'] as num).toDouble();
    }
    final sorted = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.map((e) => {
      'name': e.key,
      'amount': e.value,
      'pct': _totalSpent > 0
          ? '${(e.value / _totalSpent * 100).toStringAsFixed(0)}%'
          : '0%',
    }).toList();
  }

  void _showAllCategories() {
    final all = _allCategories;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text('$_monthLabel spending by category',
                style: const TextStyle(
                    color: Color(0xFF1A1A2E),
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Total ${_fmt(_totalSpent)}',
                style: const TextStyle(color: Colors.black54, fontSize: 13)),
            const SizedBox(height: 16),
            if (all.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text('No spending recorded in this month',
                      style: TextStyle(color: Colors.black45)),
                ),
              ),
            ...all.map((c) {
              final share = _totalSpent > 0
                  ? (c['amount'] as double) / _totalSpent
                  : 0.0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: const Color(0xFF5B2EFF).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(_iconForCategory(c['name']),
                          color: const Color(0xFF5B2EFF), size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(c['name'],
                                    style: const TextStyle(
                                        color: Color(0xFF1A1A2E),
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13)),
                              ),
                              Text('${_fmt(c['amount'])}  •  ${c['pct']}',
                                  style: const TextStyle(
                                      color: Colors.black54, fontSize: 12)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: share.clamp(0.0, 1.0),
                              minHeight: 6,
                              backgroundColor:
                                  const Color(0xFF5B2EFF).withOpacity(0.08),
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                  Color(0xFF5B2EFF)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  IconData _iconForCategory(String name) {
    switch (name.toLowerCase()) {
      case 'food & dining': return Icons.restaurant_outlined;
      case 'dining & food': return Icons.restaurant_outlined;
      case 'transport': return Icons.directions_bus_outlined;
      case 'shopping': return Icons.shopping_bag_outlined;
      case 'bills & utilities': return Icons.bolt_outlined;
      case 'entertainment': return Icons.movie_outlined;
      case 'healthcare': return Icons.local_hospital_outlined;
      case 'education': return Icons.school_outlined;
      case 'travel': return Icons.flight_outlined;
      case 'investments': return Icons.show_chart;
      default: return Icons.receipt_long_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SafeArea(
        child: Center(
          child: CircularProgressIndicator(color: Color(0xFF5B2EFF)),
        ),
      );
    }

    final bars = _weeklyBars;
    final maxBar = bars.reduce((a, b) => a > b ? a : b);
    final cats = _topCategories;

    return SafeArea(
      child: RefreshIndicator(
        color: const Color(0xFF5B2EFF),
        onRefresh: () => _load(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Greeting and avatar (tap the avatar to open Profile) ─────
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Hi, $_firstName 👋',
                            style: const TextStyle(
                                color: Color(0xFF1A1A2E),
                                fontSize: 22,
                                fontWeight: FontWeight.bold)),
                        const Text('Here is your spending pulse today',
                            style: TextStyle(color: Colors.black54, fontSize: 13)),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: widget.onOpenProfile,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                        color: Color(0xFF5B2EFF),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          _initials,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Spending card ──────────────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF5B2EFF), Color(0xFF3A1DB5)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _MonthArrow(
                          icon: Icons.chevron_left,
                          enabled: _canGoBack,
                          onTap: () => _changeMonth(-1),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text('$_monthLabel Total Spent',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 13)),
                        ),
                        if (_isCurrentMonth)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white24,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text('$_daysRemaining days left',
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 11)),
                          )
                        else
                          GestureDetector(
                            onTap: () => setState(() => _month = DateTime(
                                DateTime.now().year, DateTime.now().month)),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white24,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Text('Back to now',
                                  style: TextStyle(
                                      color: Colors.white, fontSize: 11)),
                            ),
                          ),
                        const SizedBox(width: 4),
                        _MonthArrow(
                          icon: Icons.chevron_right,
                          enabled: !_isCurrentMonth,
                          onTap: () => _changeMonth(1),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _fmt(_totalSpent),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 34,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.5),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _isCurrentMonth
                          ? '${_monthTx.length} transaction${_monthTx.length == 1 ? '' : 's'}  •  $_daysRemaining days remaining'
                          : '${_monthTx.length} transaction${_monthTx.length == 1 ? '' : 's'}  •  full month',
                      style: const TextStyle(
                          color: Colors.white60, fontSize: 11),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: _StatItem(
                              label: 'Daily Avg',
                              value: _fmt(_dailyAvg)),
                        ),
                        Container(
                            width: 1, height: 36, color: Colors.white24),
                        Expanded(
                          child: _StatItem(
                              label: _isCurrentMonth ? 'Projected' : 'Month total',
                              value: _fmt(_projected)),
                        ),
                        Container(
                            width: 1, height: 36, color: Colors.white24),
                        Expanded(
                          child: _StatItem(
                              label: 'Transactions',
                              value: '${_monthTx.length}'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── Highlight from the analysis ────────────────────────────
              _highlightCard(),

              const SizedBox(height: 24),

              // ── Weekly chart ───────────────────────────────────────────
              const Text('This Week',
                  style: TextStyle(
                      color: Color(0xFF1A1A2E),
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
              const SizedBox(height: 2),
              Text('$_weekRangeLabel  •  ${_fmt(_weekTotal)} spent',
                  style: const TextStyle(color: Colors.black45, fontSize: 12)),
              const SizedBox(height: 16),
              SizedBox(
                height: 180,
                child: BarChart(
                  BarChartData(
                    barTouchData: BarTouchData(enabled: false),
                    titlesData: FlTitlesData(
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (val, meta) {
                            const days = ['M','T','W','T','F','S','S'];
                            return Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(days[val.toInt()],
                                  style: const TextStyle(
                                      color: Colors.black45, fontSize: 12)),
                            );
                          },
                        ),
                      ),
                      topTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (val, meta) {
                            final v = bars[val.toInt()];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                v > 0 ? '${v.toStringAsFixed(1)}k' : '',
                                style: const TextStyle(
                                    color: Colors.black45,
                                    fontSize: 10),
                              ),
                            );
                          },
                        ),
                      ),
                      leftTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                    ),
                    gridData: const FlGridData(show: false),
                    borderData: FlBorderData(show: false),
                    barGroups: bars.asMap().entries.map((e) {
                      final isWeekend = e.key >= 5;
                      return BarChartGroupData(
                        x: e.key,
                        barRods: [
                          BarChartRodData(
                            toY: e.value > 0 ? e.value : 0.1,
                            color: isWeekend
                                ? const Color(0xFF5B2EFF)
                                : const Color(0xFF5B2EFF).withOpacity(0.35),
                            width: 30,
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(6)),
                          ),
                        ],
                      );
                    }).toList(),
                    maxY: maxBar > 0 ? maxBar * 1.3 : 5,
                  ),
                ),
              ),
              const SizedBox(height: 28),

              // ── Top categories ─────────────────────────────────────────
              if (cats.isNotEmpty) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Top Spending Categories',
                        style: TextStyle(
                            color: Color(0xFF1A1A2E),
                            fontWeight: FontWeight.bold,
                            fontSize: 16)),
                    TextButton(
                      onPressed: _showAllCategories,
                      child: const Text('View All',
                          style: TextStyle(
                              color: Color(0xFF5B2EFF), fontSize: 13)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 2.0,
                  children: cats.map((c) => _CategoryTile(
                        name: c['name'],
                        amount: _fmt(c['amount']),
                        pct: c['pct'],
                        icon: _iconForCategory(c['name']),
                      )).toList(),
                ),
              ] else ...[
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Column(
                      children: [
                        const Icon(Icons.receipt_long_outlined,
                            color: Colors.black26, size: 40),
                        const SizedBox(height: 10),
                        Text('No spending recorded in $_monthLabel',
                            style: const TextStyle(color: Colors.black45)),
                        const SizedBox(height: 4),
                        const Text(
                            'Add transactions in the Transactions tab',
                            style: TextStyle(
                                color: Colors.black26, fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Shared small widgets ──────────────────────────────────────────────────────

class _MonthArrow extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  const _MonthArrow(
      {required this.icon, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: enabled ? onTap : null,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(enabled ? 0.18 : 0.06),
          shape: BoxShape.circle,
        ),
        child: Icon(icon,
            color: enabled ? Colors.white : Colors.white30, size: 20),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  const _StatItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.white60, fontSize: 11)),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool filled;
  const _ActionButton(
      {required this.icon, required this.label, this.filled = false});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: filled
              ? const Color(0xFF5B2EFF)
              : const Color(0xFF5B2EFF).withOpacity(0.15),
          borderRadius: BorderRadius.circular(14),
          border: filled
              ? null
              : Border.all(
                  color: const Color(0xFF5B2EFF).withOpacity(0.4)),
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(height: 6),
            Text(label,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  final String name;
  final String amount;
  final String pct;
  final IconData icon;
  const _CategoryTile(
      {required this.name,
      required this.amount,
      required this.pct,
      required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFF5B2EFF).withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: const Color(0xFF5B2EFF), size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(name,
                    style: const TextStyle(
                        color: Color(0xFF1A1A2E),
                        fontSize: 11,
                        fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(amount,
                    style: const TextStyle(
                        color: Colors.black54, fontSize: 10)),
                Text(pct,
                    style: const TextStyle(
                        color: Color(0xFF5B2EFF),
                        fontSize: 10,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The single highlight shown on Home (unusual transaction, forecast or insight).
class _HighlightCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final bool loading;
  final VoidCallback? onTap;
  const _HighlightCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.loading = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.35)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: loading
                    ? Padding(
                        padding: const EdgeInsets.all(11),
                        child: CircularProgressIndicator(strokeWidth: 2, color: color),
                      )
                    : Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            color: Color(0xFF1A1A2E),
                            fontWeight: FontWeight.w600,
                            fontSize: 14)),
                    const SizedBox(height: 3),
                    Text(subtitle,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.black54, fontSize: 12, height: 1.4)),
                  ],
                ),
              ),
              if (onTap != null)
                const Icon(Icons.chevron_right, color: Colors.black26),
            ],
          ),
        ),
      ),
    );
  }
}