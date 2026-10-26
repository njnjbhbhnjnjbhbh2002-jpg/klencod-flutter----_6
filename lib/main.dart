import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DebtDatabase.instance.database;
  runApp(const DebtManagerApp());
}

const Color brandBlue = Color(0xFF1769E0);
const Color pageBackground = Color(0xFFF4F7FB);
const Color ink = Color(0xFF202938);
const Color green = Color(0xFF159B72);
const Color red = Color(0xFFD94A4A);

class DebtManagerApp extends StatelessWidget {
  const DebtManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'مدير الديون',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: brandBlue),
        scaffoldBackgroundColor: pageBackground,
        fontFamily: 'Roboto',
        appBarTheme: const AppBarTheme(
          backgroundColor: pageBackground,
          foregroundColor: ink,
          centerTitle: false,
          elevation: 0,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE4EAF2)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: brandBlue, width: 1.5),
          ),
        ),
      ),
      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: DebtHomePage(),
      ),
    );
  }
}

class DebtDatabase {
  DebtDatabase._();
  static final DebtDatabase instance = DebtDatabase._();
  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    final root = await getDatabasesPath();
    _db = await openDatabase(
      p.join(root, 'debt_manager.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE people (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            phone TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE debts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            person_id INTEGER NOT NULL,
            title TEXT NOT NULL,
            amount REAL NOT NULL,
            note TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL,
            FOREIGN KEY(person_id) REFERENCES people(id) ON DELETE CASCADE
          )
        ''');
        await db.execute('''
          CREATE TABLE payments (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            debt_id INTEGER NOT NULL,
            amount REAL NOT NULL,
            note TEXT NOT NULL DEFAULT '',
            paid_at TEXT NOT NULL,
            FOREIGN KEY(debt_id) REFERENCES debts(id) ON DELETE CASCADE
          )
        ''');
      },
    );
    return _db!;
  }

  Future<int> addPerson({
    required String name,
    required String phone,
  }) async {
    final db = await database;
    return db.insert('people', {
      'name': name.trim(),
      'phone': phone.trim(),
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<int> addDebt({
    required String personName,
    required String phone,
    required String title,
    required double amount,
    required String note,
  }) async {
    final db = await database;
    return db.transaction((txn) async {
      final existing = await txn.query(
        'people',
        where: 'name = ? AND phone = ?',
        whereArgs: [personName.trim(), phone.trim()],
        limit: 1,
      );
      int personId;
      if (existing.isNotEmpty) {
        personId = existing.first['id'] as int;
      } else {
        personId = await txn.insert('people', {
          'name': personName.trim(),
          'phone': phone.trim(),
          'created_at': DateTime.now().toIso8601String(),
        });
      }
      return txn.insert('debts', {
        'person_id': personId,
        'title': title.trim(),
        'amount': amount,
        'note': note.trim(),
        'created_at': DateTime.now().toIso8601String(),
      });
    });
  }

  Future<void> addPayment({
    required int debtId,
    required double amount,
    required String note,
  }) async {
    final db = await database;
    await db.insert('payments', {
      'debt_id': debtId,
      'amount': amount,
      'note': note.trim(),
      'paid_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, Object?>>> getDebts() async {
    final db = await database;
    return db.rawQuery('''
      SELECT debts.id, debts.person_id, debts.title, debts.amount, debts.note,
             debts.created_at, people.name AS person_name, people.phone AS phone,
             COALESCE((SELECT SUM(payments.amount) FROM payments
                       WHERE payments.debt_id = debts.id), 0) AS paid
      FROM debts
      INNER JOIN people ON people.id = debts.person_id
      ORDER BY debts.id DESC
    ''');
  }

  Future<Map<String, double>> getSummary() async {
    final debts = await getDebts();
    double total = 0;
    double paid = 0;
    for (final row in debts) {
      total += (row['amount'] as num).toDouble();
      paid += (row['paid'] as num).toDouble();
    }
    return {'total': total, 'paid': paid, 'remaining': total - paid};
  }

  Future<void> deleteDebt(int id) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('payments', where: 'debt_id = ?', whereArgs: [id]);
      await txn.delete('debts', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<List<Map<String, Object?>>> getPayments(int debtId) async {
    final db = await database;
    return db.query(
      'payments',
      where: 'debt_id = ?',
      whereArgs: [debtId],
      orderBy: 'id DESC',
    );
  }
}

String money(num value) {
  final rounded = value.round();
  final text = rounded.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]},',
  );
  return '$text د.ع';
}

class DebtHomePage extends StatefulWidget {
  const DebtHomePage({super.key});

  @override
  State<DebtHomePage> createState() => _DebtHomePageState();
}

class _DebtHomePageState extends State<DebtHomePage> {
  List<Map<String, Object?>> debts = [];
  Map<String, double> summary = {'total': 0, 'paid': 0, 'remaining': 0};
  bool loading = true;
  String search = '';

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    final results = await Future.wait([
      DebtDatabase.instance.getDebts(),
      DebtDatabase.instance.getSummary(),
    ]);
    if (!mounted) return;
    setState(() {
      debts = results[0] as List<Map<String, Object?>>;
      summary = results[1] as Map<String, double>;
      loading = false;
    });
  }

  List<Map<String, Object?>> get filteredDebts {
    final q = search.trim().toLowerCase();
    if (q.isEmpty) return debts;
    return debts.where((d) {
      return (d['person_name'] as String).toLowerCase().contains(q) ||
          (d['title'] as String).toLowerCase().contains(q) ||
          (d['phone'] as String).toLowerCase().contains(q);
    }).toList();
  }

  Future<void> showAddDebt() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => const AddDebtDialog(),
    );
    if (result == true) refresh();
  }

  Future<void> showPayment(Map<String, Object?> debt) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => PaymentDialog(debt: debt),
    );
    if (result == true) refresh();
  }

  Future<void> confirmDelete(Map<String, Object?> debt) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف سجل الدين؟'),
        content: const Text('سيتم حذف الدين والدفعات المرتبطة به نهائيًا.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (yes == true) {
      await DebtDatabase.instance.deleteDebt(debt['id'] as int);
      refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final remaining = summary['remaining'] ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('مدير الديون', style: TextStyle(fontWeight: FontWeight.w800)),
            Text('إدارة الديون والأقساط بسهولة',
                style: TextStyle(fontSize: 12, color: Colors.black54)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 6),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: showAddDebt,
        icon: const Icon(Icons.add_rounded),
        label: const Text('إضافة دين'),
      ),
      body: RefreshIndicator(
        onRefresh: refresh,
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                children: [
                  _buildBalanceCard(),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      const Expanded(
                        child: Text('سجل الديون',
                            style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                                color: ink)),
                      ),
                      Text('${debts.length} سجل',
                          style: const TextStyle(color: Colors.black54)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    onChanged: (v) => setState(() => search = v),
                    decoration: const InputDecoration(
                      hintText: 'ابحث بالاسم أو رقم الهاتف أو الدين',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (filteredDebts.isEmpty)
                    _emptyState()
                  else
                    ...filteredDebts.map(_debtCard),
                ],
              ),
      ),
    );
  }

  Widget _buildBalanceCard() {
    final total = summary['total'] ?? 0;
    final paid = summary['paid'] ?? 0;
    final remaining = summary['remaining'] ?? 0;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1769E0), Color(0xFF4596F5)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: brandBlue.withOpacity(.18),
            blurRadius: 20,
            offset: const Offset(0, 8),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.account_balance_wallet_outlined,
                  color: Colors.white70),
              SizedBox(width: 8),
              Text('إجمالي المبالغ المسجلة',
                  style: TextStyle(color: Colors.white70, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 8),
          Text(money(total),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w900)),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(child: _summaryItem('المتبقي', money(remaining))),
              Container(width: 1, height: 42, color: Colors.white30),
              Expanded(child: _summaryItem('المسدّد', money(paid))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryItem(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 5),
            Text(value,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w800)),
          ],
        ),
      );

  Widget _emptyState() => Container(
        padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE7ECF3)),
        ),
        child: const Column(
          children: [
            Icon(Icons.receipt_long_outlined, size: 48, color: Colors.black26),
            SizedBox(height: 12),
            Text('لا توجد ديون مسجلة',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            SizedBox(height: 5),
            Text('اضغط على «إضافة دين» لتسجيل أول دين.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54)),
          ],
        ),
      );

  Widget _debtCard(Map<String, Object?> debt) {
    final amount = (debt['amount'] as num).toDouble();
    final paid = (debt['paid'] as num).toDouble();
    final remaining = (amount - paid).clamp(0, double.infinity).toDouble();
    final progress = amount <= 0 ? 0.0 : (paid / amount).clamp(0.0, 1.0);
    final settled = remaining <= 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE7ECF3)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: const Color(0xFFEAF1FF),
                foregroundColor: brandBlue,
                child: Text(
                  (debt['person_name'] as String).isNotEmpty
                      ? (debt['person_name'] as String).characters.first
                      : '؟',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(debt['person_name'] as String,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(height: 3),
                    Text(debt['title'] as String,
                        style: const TextStyle(color: Colors.black54)),
                    if ((debt['phone'] as String).isNotEmpty)
                      Text(debt['phone'] as String,
                          style: const TextStyle(
                              color: Colors.black45, fontSize: 12)),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'delete') confirmDelete(debt);
                  if (value == 'payments') showPaymentHistory(debt);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                      value: 'payments', child: Text('سجل الدفعات')),
                  PopupMenuItem(value: 'delete', child: Text('حذف الدين')),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _amountColumn('أصل الدين', money(amount))),
              Expanded(child: _amountColumn('المسدّد', money(paid))),
              Expanded(
                child: _amountColumn(
                  'المتبقي',
                  money(remaining),
                  valueColor: settled ? green : red,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: const Color(0xFFEAF0F7),
              color: settled ? green : brandBlue,
            ),
          ),
          if ((debt['note'] as String).isNotEmpty) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: Text('ملاحظة: ${debt['note']}',
                  style: const TextStyle(color: Colors.black54)),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: settled ? null : () => showPayment(debt),
              icon: const Icon(Icons.payments_outlined),
              label: Text(settled ? 'تم تسديد الدين بالكامل' : 'تسجيل دفعة'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _amountColumn(String label, String value, {Color? valueColor}) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.black54, fontSize: 12)),
          const SizedBox(height: 5),
          Text(value,
              style: TextStyle(
                  color: valueColor ?? ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 13)),
        ],
      );

  Future<void> showPaymentHistory(Map<String, Object?> debt) async {
    final rows = await DebtDatabase.instance.getPayments(debt['id'] as int);
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('دفعات ${debt['person_name']}',
                  style: const TextStyle(
                      fontSize: 19, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              if (rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: Text('لا توجد دفعات مسجلة بعد.')),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const Divider(),
                    itemBuilder: (_, i) {
                      final row = rows[i];
                      final date = DateTime.tryParse(row['paid_at'] as String);
                      return ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Color(0xFFE4F6EF),
                          child: Icon(Icons.check, color: green),
                        ),
                        title: Text(money((row['amount'] as num).toDouble())),
                        subtitle: Text([
                          if (date != null)
                            '${date.year}/${date.month}/${date.day}',
                          if ((row['note'] as String).isNotEmpty)
                            row['note'] as String,
                        ].join(' • ')),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class AddDebtDialog extends StatefulWidget {
  const AddDebtDialog({super.key});

  @override
  State<AddDebtDialog> createState() => _AddDebtDialogState();
}

class _AddDebtDialogState extends State<AddDebtDialog> {
  final formKey = GlobalKey<FormState>();
  final personController = TextEditingController();
  final phoneController = TextEditingController();
  final titleController = TextEditingController();
  final amountController = TextEditingController();
  final noteController = TextEditingController();
  bool saving = false;

  @override
  void dispose() {
    personController.dispose();
    phoneController.dispose();
    titleController.dispose();
    amountController.dispose();
    noteController.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (!formKey.currentState!.validate()) return;
    setState(() => saving = true);
    try {
      await DebtDatabase.instance.addDebt(
        personName: personController.text,
        phone: phoneController.text,
        title: titleController.text,
        amount: double.parse(amountController.text.trim()),
        note: noteController.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر حفظ الدين: $e')),
        );
      }
    }
  }

  String? requiredText(String? value) =>
      value == null || value.trim().isEmpty ? 'هذا الحقل مطلوب' : null;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('إضافة دين جديد',
          style: TextStyle(fontWeight: FontWeight.w800)),
      content: SingleChildScrollView(
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: personController,
                decoration: const InputDecoration(labelText: 'اسم الشخص *'),
                validator: requiredText,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: phoneController,
                decoration: const InputDecoration(labelText: 'رقم الهاتف'),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: titleController,
                decoration:
                    const InputDecoration(labelText: 'سبب الدين / الوصف *'),
                validator: requiredText,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: amountController,
                decoration: const InputDecoration(
                    labelText: 'المبلغ بالدينار العراقي *',
                    prefixText: 'د.ع '),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'أدخل المبلغ';
                  }
                  final amount = double.tryParse(value.trim());
                  if (amount == null || amount <= 0) return 'أدخل مبلغًا صحيحًا';
                  return null;
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: noteController,
                decoration: const InputDecoration(labelText: 'ملاحظات (اختياري)'),
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context, false),
          child: const Text('إلغاء'),
        ),
        FilledButton.icon(
          onPressed: saving ? null : save,
          icon: saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: const Text('حفظ الدين'),
        ),
      ],
    );
  }
}

class PaymentDialog extends StatefulWidget {
  final Map<String, Object?> debt;
  const PaymentDialog({super.key, required this.debt});

  @override
  State<PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<PaymentDialog> {
  final formKey = GlobalKey<FormState>();
  final amountController = TextEditingController();
  final noteController = TextEditingController();
  bool saving = false;

  @override
  void dispose() {
    amountController.dispose();
    noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final amount = (widget.debt['amount'] as num).toDouble();
    final paid = (widget.debt['paid'] as num).toDouble();
    final remaining = (amount - paid).clamp(0, double.infinity).toDouble();

    return AlertDialog(
      title: const Text('تسجيل دفعة',
          style: TextStyle(fontWeight: FontWeight.w800)),
      content: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Text('المتبقي: ${money(remaining)}',
                  style: const TextStyle(
                      color: brandBlue, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: amountController,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'مبلغ الدفعة *', prefixText: 'د.ع '),
              validator: (value) {
                final entered = double.tryParse(value?.trim() ?? '');
                if (entered == null || entered <= 0) {
                  return 'أدخل مبلغًا صحيحًا';
                }
                if (entered > remaining) return 'الدفعة أكبر من المبلغ المتبقي';
                return null;
              },
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: noteController,
              decoration: const InputDecoration(labelText: 'ملاحظة (اختياري)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context, false),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: saving
              ? null
              : () async {
                  if (!formKey.currentState!.validate()) return;
                  setState(() => saving = true);
                  try {
                    await DebtDatabase.instance.addPayment(
                      debtId: widget.debt['id'] as int,
                      amount: double.parse(amountController.text.trim()),
                      note: noteController.text,
                    );
                    if (context.mounted) Navigator.pop(context, true);
                  } catch (e) {
                    if (context.mounted) {
                      setState(() => saving = false);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('تعذر حفظ الدفعة: $e')),
                      );
                    }
                  }
                },
          child: const Text('حفظ الدفعة'),
        ),
      ],
    );
  }
} 