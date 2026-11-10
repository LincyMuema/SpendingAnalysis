import 'package:flutter/material.dart';
import 'api_service.dart';
import 'sms_sync_service.dart';
import 'app_events.dart';

const List<String> kCategories = [
  'Food & Dining',
  'Transport',
  'Shopping',
  'Bills & Utilities',
  'Education',
  'Entertainment',
  'Travel',
  'Other',
];

const List<String> kSources = ['MPESA', 'CARD', 'CASH', 'WALLET'];

// Special dropdown value that opens the "New category" dialog
const String _kNewCategory = '__new_category__';

const List<String> _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];

class TransactionsScreen extends StatefulWidget {
  final int userId;
  /// Your full name, so transfers to yourself are not counted as spending.
  final String? ownName;
  const TransactionsScreen({super.key, required this.userId, this.ownName});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  List<Map<String, dynamic>> _transactions = [];
  bool _isLoading = true;
  String? _error;
  bool _isSyncing = false;

  // ── Categories (standard + the user's own) ────────────────────────────────
  final Map<String, int> _customCategoryIds = {}; // name -> category_id

  List<String> get _categories => [
        ...kCategories,
        ..._customCategoryIds.keys.where((c) => !kCategories.contains(c)),
      ];

  Future<void> _loadCategories() async {
    try {
      final cats = await ApiService.getCategories();
      if (!mounted) return;
      setState(() {
        _customCategoryIds
          ..clear()
          ..addEntries(cats
              .where((c) => c['is_custom'] == true)
              .map((c) => MapEntry(c['name'] as String, c['category_id'] as int)));
      });
    } catch (_) {
      // Keep the standard categories if this fails
    }
  }

  /// Asks for a new category name and creates it. Returns the name, or null.
  Future<String?> _createCategoryDialog(BuildContext ctx) async {
    final nameCtrl = TextEditingController();
    String? error;
    bool saving = false;

    return showDialog<String>(
      context: ctx,
      builder: (dCtx) => StatefulBuilder(
        builder: (dCtx, setDialog) {
          Future<void> create() async {
            final name = nameCtrl.text.trim();
            if (name.isEmpty) {
              setDialog(() => error = 'Enter a name, e.g. Church or Chama');
              return;
            }
            setDialog(() {
              saving = true;
              error = null;
            });
            try {
              final cat = await ApiService.createCategory(name: name);
              if (mounted) {
                setState(() => _customCategoryIds[cat['name'] as String] =
                    cat['category_id'] as int);
              }
              if (dCtx.mounted) Navigator.pop(dCtx, cat['name'] as String);
            } catch (e) {
              setDialog(() {
                saving = false;
                error = e.toString().replaceAll('Exception: ', '');
              });
            }
          }

          return AlertDialog(
            backgroundColor: Colors.white,
            title: const Text('New category'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  maxLength: 30,
                  textCapitalization: TextCapitalization.words,
                  decoration: _inputStyle('Category name'),
                  onSubmitted: (_) => saving ? null : create(),
                ),
                if (error != null)
                  Text(error!,
                      style: const TextStyle(color: Color(0xFFE53935), fontSize: 13)),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dCtx),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: saving ? null : create,
                child: const Text('Create'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Deletes one of the user's own categories; its transactions move to Other.
  Future<bool> _confirmDeleteCategory(BuildContext ctx, String name) async {
    final id = _customCategoryIds[name];
    if (id == null) return false;
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text('Delete "$name"?'),
        content: const Text(
            'Transactions in this category will move to Other. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(dCtx, true),
            child: const Text('Delete', style: TextStyle(color: Color(0xFFE53935))),
          ),
        ],
      ),
    );
    if (ok != true) return false;
    try {
      final msg = await ApiService.deleteCategory(categoryId: id);
      if (mounted) setState(() => _customCategoryIds.remove(name));
      await _loadTransactions(silent: true);
      AppEvents.notifyTransactionsChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
        );
      }
      return false;
    }
  }

  // ── Filters ────────────────────────────────────────────────────────────────
  Set<String> _fCategories = {};
  Set<String> _fSources = {};
  DateTimeRange? _fDates;
  double? _fMin;
  double? _fMax;

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _loadTransactions().then((_) => _autoSync());
  }

  /// Runs every time the app opens, once the user has allowed SMS access.
  Future<void> _autoSync() async {
    if (!await SmsSyncService.hasPermission()) return;
    await _syncSms(silent: true);
  }

  Future<void> _loadTransactions({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }
    try {
      final txs = await ApiService.getTransactions(userId: widget.userId);
      if (!mounted) return;
      setState(() {
        _transactions = txs;
        _isLoading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  // ── SMS sync ───────────────────────────────────────────────────────────────
  Future<void> _syncSms({bool silent = false}) async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);
    final result = await SmsSyncService.sync(
      userId: widget.userId,
      ownName: widget.ownName,
      sinceDays: 365,
    );
    if (!mounted) return;
    setState(() => _isSyncing = false);

    if (result.permissionDenied) {
      if (silent) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.summary),
          action: result.permanentlyDenied
              ? SnackBarAction(
                  label: 'Settings',
                  onPressed: SmsSyncService.openSettings,
                )
              : null,
        ),
      );
      return;
    }

    if (result.imported > 0) {
      await _loadTransactions(silent: true);
      AppEvents.notifyTransactionsChanged();
    }
    if (!mounted) return;
    // Automatic syncs only speak up when something new was found
    if (!silent || result.imported > 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(result.summary)));
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  String _fmtDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

  String _apiDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Accepts "1500", "1,500", "KSh 1,500", "1500.50". Returns null if invalid.
  double? _parseAmount(String text) {
    final cleaned = text
        .replaceAll(RegExp(r'ksh', caseSensitive: false), '')
        .replaceAll(',', '')
        .replaceAll(' ', '')
        .trim();
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }

  int get _activeFilterCount =>
      (_fCategories.isNotEmpty ? 1 : 0) +
      (_fSources.isNotEmpty ? 1 : 0) +
      (_fDates != null ? 1 : 0) +
      ((_fMin != null || _fMax != null) ? 1 : 0);

  void _clearFilters() {
    setState(() {
      _fCategories = {};
      _fSources = {};
      _fDates = null;
      _fMin = null;
      _fMax = null;
    });
  }

  List<Map<String, dynamic>> get _filtered {
    return _transactions.where((tx) {
      final cat = (tx['category_name'] as String?) ?? 'Other';
      if (_fCategories.isNotEmpty && !_fCategories.contains(cat)) return false;

      final src = (tx['source'] as String?) ?? 'OTHER';
      if (_fSources.isNotEmpty && !_fSources.contains(src)) return false;

      final amt = (tx['amount'] as num).toDouble();
      if (_fMin != null && amt < _fMin!) return false;
      if (_fMax != null && amt > _fMax!) return false;

      if (_fDates != null) {
        final d = DateTime.tryParse((tx['date'] as String).split(' ')[0]);
        if (d == null) return false;
        final start = DateTime(
            _fDates!.start.year, _fDates!.start.month, _fDates!.start.day);
        final end =
            DateTime(_fDates!.end.year, _fDates!.end.month, _fDates!.end.day);
        if (d.isBefore(start) || d.isAfter(end)) return false;
      }
      return true;
    }).toList();
  }

  IconData _iconForCategory(String? category) {
    switch ((category ?? '').toLowerCase()) {
      case 'food & dining':
      case 'dining & food':
      case 'food':
        return Icons.restaurant_outlined;
      case 'transport':
        return Icons.directions_bus_outlined;
      case 'shopping':
        return Icons.shopping_bag_outlined;
      case 'bills & utilities':
      case 'bills':
      case 'utilities':
        return Icons.bolt_outlined;
      case 'subscriptions':
        return Icons.subscriptions_outlined;
      case 'entertainment':
        return Icons.movie_outlined;
      case 'travel':
        return Icons.flight_outlined;
      case 'health':
        return Icons.local_hospital_outlined;
      case 'education':
        return Icons.school_outlined;
      default:
        return Icons.receipt_long_outlined;
    }
  }

  Color _sourceColor(String source) {
    switch (source) {
      case 'MPESA':
        return const Color(0xFF00AA00);
      case 'CARD':
        return const Color(0xFF1565C0);
      case 'CASH':
        return const Color(0xFF795548);
      default:
        return const Color(0xFF5B2EFF);
    }
  }

  InputDecoration _inputStyle(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.black45),
      enabledBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Colors.black12),
        borderRadius: BorderRadius.circular(12),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Color(0xFF5B2EFF), width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
      filled: true,
      fillColor: const Color(0xFFF5F5FA),
    );
  }

  Widget _sheetHandle() => Center(
        child: Container(
          width: 40,
          height: 4,
          margin: const EdgeInsets.only(bottom: 20),
          decoration: BoxDecoration(
            color: Colors.black12,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );

  // ── Filter sheet ───────────────────────────────────────────────────────────
  void _showFilterSheet() {
    final cats = {..._fCategories};
    final srcs = {..._fSources};
    DateTimeRange? range = _fDates;
    final minCtrl =
        TextEditingController(text: _fMin == null ? '' : _fMin!.toStringAsFixed(0));
    final maxCtrl =
        TextEditingController(text: _fMax == null ? '' : _fMax!.toStringAsFixed(0));
    String? err;

    // Standard categories first, then any older ones already in the data.
    final catOptions = <String>{
      ..._categories,
      ..._transactions.map((t) => (t['category_name'] as String?) ?? 'Other'),
    }.toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sheetHandle(),
                const Text('Filter transactions',
                    style: TextStyle(
                        color: Color(0xFF1A1A2E),
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 18),

                const Text('Category',
                    style: TextStyle(
                        color: Colors.black54,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: catOptions.map((c) {
                    final selected = cats.contains(c);
                    return FilterChip(
                      label: Text(c),
                      selected: selected,
                      selectedColor: const Color(0xFF5B2EFF).withOpacity(0.15),
                      checkmarkColor: const Color(0xFF5B2EFF),
                      onSelected: (v) =>
                          setModal(() => v ? cats.add(c) : cats.remove(c)),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),

                const Text('Payment method',
                    style: TextStyle(
                        color: Colors.black54,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: kSources.map((s) {
                    final selected = srcs.contains(s);
                    return FilterChip(
                      label: Text(s),
                      selected: selected,
                      selectedColor: const Color(0xFF5B2EFF).withOpacity(0.15),
                      checkmarkColor: const Color(0xFF5B2EFF),
                      onSelected: (v) =>
                          setModal(() => v ? srcs.add(s) : srcs.remove(s)),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),

                const Text('Date range',
                    style: TextStyle(
                        color: Colors.black54,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await showDateRangePicker(
                            context: ctx,
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                            initialDateRange: range,
                          );
                          if (picked != null) setModal(() => range = picked);
                        },
                        icon: const Icon(Icons.date_range, size: 18),
                        label: Text(
                          range == null
                              ? 'Any date'
                              : '${_fmtDate(range!.start)} – ${_fmtDate(range!.end)}',
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF1A1A2E),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    if (range != null)
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () => setModal(() => range = null),
                      ),
                  ],
                ),
                const SizedBox(height: 16),

                const Text('Amount (KSh)',
                    style: TextStyle(
                        color: Colors.black54,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: minCtrl,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        decoration: _inputStyle('Min'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: maxCtrl,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        decoration: _inputStyle('Max'),
                      ),
                    ),
                  ],
                ),
                if (err != null) ...[
                  const SizedBox(height: 8),
                  Text(err!,
                      style: const TextStyle(
                          color: Color(0xFFE53935), fontSize: 12)),
                ],
                const SizedBox(height: 22),

                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          _clearFilters();
                          Navigator.pop(ctx);
                        },
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 52),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Reset'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: () {
                          final min = minCtrl.text.trim().isEmpty
                              ? null
                              : _parseAmount(minCtrl.text);
                          final max = maxCtrl.text.trim().isEmpty
                              ? null
                              : _parseAmount(maxCtrl.text);
                          if ((minCtrl.text.trim().isNotEmpty && min == null) ||
                              (maxCtrl.text.trim().isNotEmpty && max == null)) {
                            setModal(() => err = 'Enter amounts as numbers only.');
                            return;
                          }
                          if (min != null && max != null && min > max) {
                            setModal(() =>
                                err = 'Minimum cannot be more than maximum.');
                            return;
                          }
                          setState(() {
                            _fCategories = cats;
                            _fSources = srcs;
                            _fDates = range;
                            _fMin = min;
                            _fMax = max;
                          });
                          Navigator.pop(ctx);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF5B2EFF),
                          foregroundColor: Colors.white,
                          minimumSize: const Size(0, 52),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Apply filters',
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600)),
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

  // ── Add transaction sheet ──────────────────────────────────────────────────
  void _showAddDialog() {
    final amountCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String category = 'Food & Dining';
    String source = 'MPESA';
    DateTime date = DateTime.now();
    bool saving = false;
    String? error;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) {
          Future<void> save() async {
            final amount = _parseAmount(amountCtrl.text);
            if (amount == null || amount <= 0) {
              setModal(() => error = 'Enter an amount greater than 0, e.g. 1500');
              return;
            }
            setModal(() {
              saving = true;
              error = null;
            });
            try {
              // A payment added for today gets the current time; for an
              // earlier day the exact time is not known, so none is sent.
              final now = DateTime.now();
              final isToday = date.year == now.year &&
                  date.month == now.month &&
                  date.day == now.day;
              await ApiService.createTransaction(
                userId: widget.userId,
                amount: amount,
                date: _apiDate(date),
                occurredAt: isToday ? now : null,
                source: source,
                counterparty:
                    descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
                categoryName: category,
              );
              if (ctx.mounted) Navigator.pop(ctx);
              await _loadTransactions(silent: true);
              AppEvents.notifyTransactionsChanged();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Transaction added')),
                );
              }
            } catch (e) {
              setModal(() {
                saving = false;
                error = e.toString().replaceAll('Exception: ', '');
              });
            }
          }

          return Padding(
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 24,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sheetHandle(),
                  const Text('Add Transaction',
                      style: TextStyle(
                          color: Color(0xFF1A1A2E),
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  TextField(
                    controller: amountCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: Color(0xFF1A1A2E)),
                    decoration: _inputStyle('Amount (KSh)'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    // The key makes the field reset if "+ New category" is cancelled
                    key: ValueKey('$category-${_categories.length}'),
                    value: category,
                    dropdownColor: Colors.white,
                    style: const TextStyle(color: Color(0xFF1A1A2E)),
                    decoration: _inputStyle('Category'),
                    items: [
                      ..._categories
                          .map((c) => DropdownMenuItem(value: c, child: Text(c))),
                      const DropdownMenuItem(
                        value: _kNewCategory,
                        child: Text('+ New category',
                            style: TextStyle(
                                color: Color(0xFF5B2EFF),
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                    onChanged: (v) async {
                      if (v == _kNewCategory) {
                        final created = await _createCategoryDialog(ctx);
                        setModal(() => category = created ?? category);
                      } else {
                        setModal(() => category = v!);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: source,
                    dropdownColor: Colors.white,
                    style: const TextStyle(color: Color(0xFF1A1A2E)),
                    decoration: _inputStyle('Payment Method'),
                    items: kSources
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (v) => setModal(() => source = v!),
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: date,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) setModal(() => date = picked);
                    },
                    child: InputDecorator(
                      decoration: _inputStyle('Date'),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(_fmtDate(date),
                                style: const TextStyle(
                                    color: Color(0xFF1A1A2E))),
                          ),
                          const Icon(Icons.calendar_today_outlined,
                              size: 18, color: Colors.black45),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descCtrl,
                    style: const TextStyle(color: Color(0xFF1A1A2E)),
                    decoration: _inputStyle('Description (optional)'),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(error!,
                        style: const TextStyle(
                            color: Color(0xFFE53935), fontSize: 13)),
                  ],
                  const SizedBox(height: 24),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF5B2EFF),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 52),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: saving ? null : save,
                    child: saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5, color: Colors.white),
                          )
                        : const Text('Save Transaction',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Edit category sheet ────────────────────────────────────────────────────
  void _showEditCategory(Map<String, dynamic> tx) {
    final txId = tx['transaction_id'] as int;
    final counterparty = ((tx['counterparty'] as String?) ?? '').trim();
    String selected = (tx['category_name'] as String?) ?? 'Other';
    bool applyToAll = counterparty.isNotEmpty;
    bool saving = false;
    String? error;


    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) {
          Future<void> save() async {
            setModal(() {
              saving = true;
              error = null;
            });
            try {
              final res = await ApiService.updateCategory(
                transactionId: txId,
                categoryName: selected,
                applyToAll: applyToAll,
              );
              if (ctx.mounted) Navigator.pop(ctx);
              await _loadTransactions(silent: true);
              AppEvents.notifyTransactionsChanged();
              if (mounted) {
                final n = res['updated_count'] as int? ?? 1;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(n > 1
                      ? 'Updated $n transactions to $selected'
                      : 'Category changed to $selected'),
                ));
              }
            } catch (e) {
              setModal(() {
                saving = false;
                error = e.toString().replaceAll('Exception: ', '');
              });
            }
          }

          return Padding(
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 24,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sheetHandle(),
                  const Text('Change category',
                      style: TextStyle(
                          color: Color(0xFF1A1A2E),
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text(
                    '${counterparty.isEmpty ? 'Transaction' : counterparty}  •  KSh ${(tx['amount'] as num).toStringAsFixed(0)}',
                    style: const TextStyle(color: Colors.black54, fontSize: 13),
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      ...<String>{..._categories, selected}.map((c) {
                        final isCustom = _customCategoryIds.containsKey(c);
                        return GestureDetector(
                          // Long-press one of your own categories to delete it
                          onLongPress: isCustom
                              ? () async {
                                  final deleted = await _confirmDeleteCategory(ctx, c);
                                  if (deleted) {
                                    setModal(() {
                                      if (selected == c) selected = 'Other';
                                    });
                                  }
                                }
                              : null,
                          child: ChoiceChip(
                            label: Text(c),
                            selected: selected == c,
                            selectedColor:
                                const Color(0xFF5B2EFF).withOpacity(0.15),
                            onSelected: (_) => setModal(() => selected = c),
                          ),
                        );
                      }),
                      ActionChip(
                        avatar: const Icon(Icons.add, size: 16, color: Color(0xFF5B2EFF)),
                        label: const Text('New',
                            style: TextStyle(color: Color(0xFF5B2EFF))),
                        backgroundColor: Colors.white,
                        side: const BorderSide(color: Color(0xFF5B2EFF)),
                        onPressed: () async {
                          final created = await _createCategoryDialog(ctx);
                          if (created != null) setModal(() => selected = created);
                        },
                      ),
                    ],
                  ),
                  if (_customCategoryIds.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    const Text('Tip: long-press one of your own categories to delete it.',
                        style: TextStyle(color: Colors.black38, fontSize: 11)),
                  ],
                  if (counterparty.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      activeColor: const Color(0xFF5B2EFF),
                      value: applyToAll,
                      onChanged: (v) => setModal(() => applyToAll = v ?? false),
                      title: Text('Apply to all from $counterparty',
                          style: const TextStyle(fontSize: 14)),
                      subtitle: const Text(
                          'Past and future transactions will use this category',
                          style: TextStyle(fontSize: 12)),
                    ),
                  ],
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(error!,
                        style: const TextStyle(
                            color: Color(0xFFE53935), fontSize: 13)),
                  ],
                  const SizedBox(height: 20),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF5B2EFF),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 52),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: saving ? null : save,
                    child: saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5, color: Colors.white),
                          )
                        : const Text('Save',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Active-filter bar ──────────────────────────────────────────────────────
  Widget _activeFiltersBar(int shown) {
    final chips = <Widget>[];

    Widget chip(String label, VoidCallback onDelete) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: InputChip(
            label: Text(label, style: const TextStyle(fontSize: 12)),
            backgroundColor: const Color(0xFF5B2EFF).withOpacity(0.10),
            side: BorderSide.none,
            deleteIconColor: const Color(0xFF5B2EFF),
            onDeleted: onDelete,
          ),
        );

    for (final c in _fCategories) {
      chips.add(chip(c, () => setState(() => _fCategories.remove(c))));
    }
    for (final s in _fSources) {
      chips.add(chip(s, () => setState(() => _fSources.remove(s))));
    }
    if (_fDates != null) {
      chips.add(chip(
          '${_fmtDate(_fDates!.start)} – ${_fmtDate(_fDates!.end)}',
          () => setState(() => _fDates = null)));
    }
    if (_fMin != null || _fMax != null) {
      final lo = _fMin == null ? '' : 'KSh ${_fMin!.toStringAsFixed(0)}';
      final hi = _fMax == null ? '' : 'KSh ${_fMax!.toStringAsFixed(0)}';
      final label = _fMin != null && _fMax != null
          ? '$lo – $hi'
          : _fMin != null
              ? 'From $lo'
              : 'Up to $hi';
      chips.add(chip(label, () => setState(() {
            _fMin = null;
            _fMax = null;
          })));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: chips),
          ),
          Row(
            children: [
              Text('Showing $shown of ${_transactions.length}',
                  style: const TextStyle(color: Colors.black45, fontSize: 12)),
              const Spacer(),
              TextButton(
                onPressed: _clearFilters,
                child: const Text('Clear all',
                    style: TextStyle(color: Color(0xFF5B2EFF), fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Transaction card ───────────────────────────────────────────────────────
  Widget _txCard(Map<String, dynamic> tx) {
    final source = (tx['source'] as String?) ?? 'OTHER';
    final icon = _iconForCategory(tx['category_name'] as String?);
    final counterparty = (tx['counterparty'] as String?)?.trim() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF5B2EFF).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: const Color(0xFF5B2EFF), size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Who the money went to comes first; category underneath
                Text(
                    counterparty.isNotEmpty
                        ? counterparty
                        : (tx['category_name'] ?? 'Other'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Color(0xFF1A1A2E),
                        fontWeight: FontWeight.w600,
                        fontSize: 14)),
                if (counterparty.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(tx['category_name'] ?? 'Other',
                      style: const TextStyle(
                          color: Color(0xFF5B2EFF),
                          fontSize: 12,
                          fontWeight: FontWeight.w500)),
                ],
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text((tx['date'] as String).split(' ')[0],
                        style: const TextStyle(
                            color: Colors.black45, fontSize: 12)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _sourceColor(source).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(source,
                          style: TextStyle(
                              color: _sourceColor(source),
                              fontSize: 10,
                              fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Text(
            '- KSh ${(tx['amount'] as num).toStringAsFixed(0)}',
            style: const TextStyle(
                color: Color(0xFF1A1A2E),
                fontWeight: FontWeight.bold,
                fontSize: 15),
          ),
        ],
      ),
    );
  }

  // ── Body ───────────────────────────────────────────────────────────────────
  Widget _buildBody(List<Map<String, dynamic>> shown) {
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFF5B2EFF)));
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.black38, size: 48),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.black45)),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadTransactions,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF5B2EFF),
                foregroundColor: Colors.white,
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (_transactions.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long_outlined, color: Colors.black26, size: 48),
            SizedBox(height: 12),
            Text('No transactions yet',
                style: TextStyle(color: Colors.black45)),
            SizedBox(height: 4),
            Text('Tap + Add to record your first one',
                style: TextStyle(color: Colors.black26, fontSize: 12)),
          ],
        ),
      );
    }
    if (shown.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off, color: Colors.black26, size: 48),
            const SizedBox(height: 12),
            const Text('No transactions match your filters',
                style: TextStyle(color: Colors.black45)),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _clearFilters,
              child: const Text('Clear filters',
                  style: TextStyle(color: Color(0xFF5B2EFF))),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      color: const Color(0xFF5B2EFF),
      onRefresh: () => _loadTransactions(silent: true),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        itemCount: shown.length,
        itemBuilder: (ctx, i) => GestureDetector(
          onTap: () => _showEditCategory(shown[i]),
          child: _txCard(shown[i]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shown = _filtered;
    final showBar = !_isLoading && _error == null && _activeFilterCount > 0;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5FA),
      appBar: AppBar(
        title: const Text('Transactions',
            style: TextStyle(
                color: Color(0xFF1A1A2E),
                fontWeight: FontWeight.bold,
                fontSize: 20)),
        backgroundColor: const Color(0xFFF5F5FA),
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Sync from SMS',
            icon: _isSyncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Color(0xFF5B2EFF)),
                  )
                : const Icon(Icons.sms_outlined, color: Color(0xFF1A1A2E)),
            onPressed: _isSyncing ? null : _syncSms,
          ),
          IconButton(
            icon: Badge(
              isLabelVisible: _activeFilterCount > 0,
              backgroundColor: const Color(0xFF5B2EFF),
              label: Text('$_activeFilterCount'),
              child: const Icon(Icons.filter_list, color: Color(0xFF1A1A2E)),
            ),
            onPressed: _showFilterSheet,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddDialog,
        backgroundColor: const Color(0xFF5B2EFF),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      ),
      body: Column(
        children: [
          if (showBar) _activeFiltersBar(shown.length),
          Expanded(child: _buildBody(shown)),
        ],
      ),
    );
  }
}