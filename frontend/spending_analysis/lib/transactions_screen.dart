import 'package:flutter/material.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  // Dummy data for now — we'll replace with real API later
  final List<Map<String, dynamic>> _transactions = [
    {'category': 'Dining & Food', 'amount': 1200.0, 'date': '2024-10-20', 'source': 'MPESA'},
    {'category': 'Transport', 'amount': 500.0, 'date': '2024-10-19', 'source': 'CASH'},
    {'category': 'Shopping', 'amount': 3400.0, 'date': '2024-10-18', 'source': 'CARD'},
    {'category': 'Utilities', 'amount': 2100.0, 'date': '2024-10-17', 'source': 'MPESA'},
    {'category': 'Subscriptions', 'amount': 800.0, 'date': '2024-10-15', 'source': 'CARD'},
  ];

  void _showAddDialog() {
    final amountCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String selectedCategory = 'Dining & Food';
    String selectedSource = 'MPESA';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 24, right: 24, top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: StatefulBuilder(
          builder: (ctx, setModal) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Add Transaction',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: _inputStyle('Amount (KSh)'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selectedCategory,
                dropdownColor: const Color(0xFF1A1A2E),
                style: const TextStyle(color: Colors.white),
                decoration: _inputStyle('Category'),
                items: ['Dining & Food', 'Transport', 'Shopping', 'Utilities', 'Subscriptions', 'Entertainment', 'Health']
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) => setModal(() => selectedCategory = v!),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selectedSource,
                dropdownColor: const Color(0xFF1A1A2E),
                style: const TextStyle(color: Colors.white),
                decoration: _inputStyle('Payment Method'),
                items: ['MPESA', 'CARD', 'CASH', 'WALLET']
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (v) => setModal(() => selectedSource = v!),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: _inputStyle('Description (optional)'),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF5B2EFF),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  final amount = double.tryParse(amountCtrl.text);
                  if (amount == null) return;
                  setState(() {
                    _transactions.insert(0, {
                      'category': selectedCategory,
                      'amount': amount,
                      'date': DateTime.now().toString().split(' ')[0],
                      'source': selectedSource,
                    });
                  });
                  Navigator.pop(ctx);
                },
                child: const Text('Save Transaction', style: TextStyle(fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputStyle(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white60),
      enabledBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Colors.white24),
        borderRadius: BorderRadius.circular(12),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Color(0xFF5B2EFF)),
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }

  Color _sourceColor(String source) {
    switch (source) {
      case 'MPESA': return const Color(0xFF00AA00);
      case 'CARD': return const Color(0xFF1565C0);
      case 'CASH': return const Color(0xFF795548);
      default: return const Color(0xFF5B2EFF);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1F),
      appBar: AppBar(
        title: const Text('Transactions', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0D0D1F),
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddDialog,
        backgroundColor: const Color(0xFF5B2EFF),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add', style: TextStyle(color: Colors.white)),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
        itemCount: _transactions.length,
        itemBuilder: (ctx, i) {
          final tx = _transactions[i];
          final source = tx['source'] as String;
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFF5B2EFF).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.receipt_long, color: Color(0xFF5B2EFF), size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tx['category'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(tx['date'], style: const TextStyle(color: Colors.white54, fontSize: 12)),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: _sourceColor(source).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(source,
                                style: TextStyle(color: _sourceColor(source), fontSize: 10, fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Text('KSh ${tx['amount'].toStringAsFixed(0)}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
              ],
            ),
          );
        },
      ),
    );
  }
}