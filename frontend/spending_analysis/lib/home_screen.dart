import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'transactions_screen.dart';
import 'analysis_screen.dart';

class HomeScreen extends StatefulWidget {
  final String fullName;
  const HomeScreen({super.key, required this.fullName});

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
      _HomeBody(fullName: widget.fullName),
      TransactionsScreen(),
      AnalysisScreen(),
    ];
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
        ],
      ),
    );
  }
}

// ── Home body extracted so IndexedStack can hold it ──────────────────────────
class _HomeBody extends StatelessWidget {
  final String fullName;
  const _HomeBody({required this.fullName});

  String get _firstName => fullName.split(' ').first;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top bar ──────────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Icon(Icons.menu, color: Color(0xFF1A1A2E), size: 24),
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.07),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Icon(Icons.notifications_outlined,
                          color: Color(0xFF1A1A2E), size: 20),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      width: 36,
                      height: 36,
                      decoration: const BoxDecoration(
                        color: Color(0xFF5B2EFF),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          fullName.isNotEmpty
                              ? fullName
                                  .split(' ')
                                  .take(2)
                                  .map((w) => w[0])
                                  .join()
                              : '?',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),

            // ── Greeting ─────────────────────────────────────────────────
            Text('Hi, $_firstName 👋',
                style: const TextStyle(
                    color: Color(0xFF1A1A2E),
                    fontSize: 22,
                    fontWeight: FontWeight.bold)),
            const Text('Here is your spending pulse today',
                style: TextStyle(color: Colors.black54, fontSize: 13)),
            const SizedBox(height: 20),

            // ── Spending card ─────────────────────────────────────────────
            _SpendingCard(),
            const SizedBox(height: 20),

            // ── Quick actions ─────────────────────────────────────────────
            _QuickActions(),
            const SizedBox(height: 28),

            // ── Weekly chart ──────────────────────────────────────────────
            _WeeklyChart(),
            const SizedBox(height: 28),

            // ── Top categories ────────────────────────────────────────────
            _TopCategories(),
          ],
        ),
      ),
    );
  }
}

// ── Spending card ─────────────────────────────────────────────────────────────
class _SpendingCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: const [
                  Icon(Icons.calendar_today_outlined,
                      color: Colors.white70, size: 14),
                  SizedBox(width: 6),
                  Text('October Total Spent',
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('12 days left',
                    style: TextStyle(color: Colors.white, fontSize: 11)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text('KSh 368,500',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5)),
          const SizedBox(height: 4),
          const Text(
              'Total spending across all accounts  •  12 days remaining',
              style: TextStyle(color: Colors.white60, fontSize: 11)),
          const SizedBox(height: 20),
          Row(
            children: const [
              Expanded(child: _StatItem(label: 'Daily Avg', value: 'KSh 12,250')),
              _VertDivider(),
              Expanded(child: _StatItem(label: 'Projected', value: 'KSh 84,500')),
              _VertDivider(),
              Expanded(
                  child: _StatItem(
                      label: 'Cash Flow', value: '+14.2%', isGreen: true)),
            ],
          ),
        ],
      ),
    );
  }
}

class _VertDivider extends StatelessWidget {
  const _VertDivider();
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 36, color: Colors.white24);
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final bool isGreen;

  const _StatItem(
      {required this.label, required this.value, this.isGreen = false});

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
              style: TextStyle(
                  color: isGreen ? const Color(0xFF00E676) : Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

// ── Quick actions ─────────────────────────────────────────────────────────────
class _QuickActions extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _ActionButton(
            icon: Icons.add_circle_outline,
            label: 'Add\nExpense',
            filled: true),
        const SizedBox(width: 12),
        _ActionButton(icon: Icons.insights_outlined, label: 'Insights &\nAnalysis'),
        const SizedBox(width: 12),
        _ActionButton(icon: Icons.upload_outlined, label: 'Export'),
      ],
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
              : Border.all(color: const Color(0xFF5B2EFF).withOpacity(0.4)),
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

// ── Weekly chart ──────────────────────────────────────────────────────────────
class _WeeklyChart extends StatelessWidget {
  final List<double> bars = const [5.4, 7.1, 4.9, 8.0, 11.4, 18.3, 14.2];
  final List<String> days = const ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Weekly Pattern',
                style: TextStyle(
                    color: Color(0xFF1A1A2E),
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.green.withOpacity(0.4)),
              ),
              child: const Text('8% below last month',
                  style: TextStyle(color: Colors.green, fontSize: 11)),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Weekend spike callout
        Row(
          children: const [
            Icon(Icons.trending_up, color: Color(0xFF5B2EFF), size: 14),
            SizedBox(width: 4),
            Text('Weekend spike: +42% on dining',
                style: TextStyle(color: Colors.black54, fontSize: 11)),
            SizedBox(width: 8),
            Text('Sat & Sun',
                style: TextStyle(
                    color: Color(0xFF5B2EFF),
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 16),

        // Bar chart with value labels on top
        SizedBox(
          height: 180,
          child: BarChart(
            BarChartData(
              barTouchData: BarTouchData(enabled: false),
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (val, meta) => Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        days[val.toInt()],
                        style: const TextStyle(
                            color: Colors.black45, fontSize: 12),
                      ),
                    ),
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
                          '${v}k',
                          style: TextStyle(
                            color: val.toInt() >= 5
                                ? const Color(0xFF1A1A2E)
                                : Colors.black45,
                            fontSize: 10,
                            fontWeight: val.toInt() >= 5
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
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
                      toY: e.value,
                      color: isWeekend
                          ? const Color(0xFF5B2EFF)
                          : const Color(0xFF5B2EFF).withOpacity(0.3),
                      width: 30,
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(6)),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ),

        // Legend
        const SizedBox(height: 8),
        Row(
          children: [
            _LegendDot(color: const Color(0xFF5B2EFF).withOpacity(0.3)),
            const SizedBox(width: 6),
            const Text('Weekday base',
                style: TextStyle(color: Colors.black54, fontSize: 11)),
            const SizedBox(width: 16),
            _LegendDot(color: const Color(0xFF5B2EFF)),
            const SizedBox(width: 6),
            const Text('Weekend peaks',
                style: TextStyle(color: Colors.black54, fontSize: 11)),
            const Spacer(),
            const Icon(Icons.check_circle, color: Colors.green, size: 14),
            const SizedBox(width: 4),
            const Text('On track',
                style: TextStyle(color: Colors.green, fontSize: 11)),
          ],
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  const _LegendDot({required this.color});

  @override
  Widget build(BuildContext context) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

// ── Top categories ────────────────────────────────────────────────────────────
class _TopCategories extends StatelessWidget {
  final List<Map<String, dynamic>> categories = const [
    {
      'name': 'Dining & Food',
      'amount': 'KSh 140,200',
      'pct': '38%',
      'icon': Icons.restaurant_outlined
    },
    {
      'name': 'Shopping',
      'amount': 'KSh 88,400',
      'pct': '24%',
      'icon': Icons.shopping_bag_outlined
    },
    {
      'name': 'Utilities',
      'amount': 'KSh 73,700',
      'pct': '20%',
      'icon': Icons.bolt_outlined
    },
    {
      'name': 'Subscriptions',
      'amount': 'KSh 66,300',
      'pct': '18%',
      'icon': Icons.subscriptions_outlined
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Top Spending Categories',
                style: TextStyle(
                    color: Color(0xFF1A1A2E),
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
            TextButton(
              onPressed: () {},
              child: const Text('View All',
                  style: TextStyle(color: Color(0xFF5B2EFF), fontSize: 13)),
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
          children: categories
              .map((c) => _CategoryTile(
                    name: c['name'],
                    amount: c['amount'],
                    pct: c['pct'],
                    icon: c['icon'],
                  ))
              .toList(),
        ),
      ],
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
            width: 36,
            height: 36,
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
                        color: Color(0xFF5B2EFF), fontSize: 10, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}