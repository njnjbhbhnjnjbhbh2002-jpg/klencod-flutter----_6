import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:intl/intl.dart';
import 'firebase_options.dart'; // يتولد تلقائياً من: flutterfire configure

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const App());
}

String money(num n) => '${NumberFormat('#,###', 'en_US').format(n)} د.ع';

int? parseAmount(String s) {
  const ar = '٠١٢٣٤٥٦٧٨٩';
  var t = s.split('').map((c) => ar.contains(c) ? ar.indexOf(c).toString() : c).join();
  t = t.replaceAll(RegExp(r'[^0-9]'), '');
  final v = int.tryParse(t);
  return (v == null || v <= 0) ? null : v;
}

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'سجل الديون',
        locale: const Locale('ar'),
        builder: (c, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
        home: StreamBuilder<User?>(
          stream: FirebaseAuth.instance.authStateChanges(),
          builder: (c, s) {
            if (s.connectionState == ConnectionState.waiting) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            return s.data == null ? const LoginPage() : HomePage(user: s.data!);
          },
        ),
      );
}

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  Future<void> _signIn(BuildContext context) async {
    try {
      final g = await GoogleSignIn().signIn();
      if (g == null) return;
      final a = await g.authentication;
      final cred = GoogleAuthProvider.credential(accessToken: a.accessToken, idToken: a.idToken);
      await FirebaseAuth.instance.signInWithCredential(cred);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('فشل تسجيل الدخول، حاول مجدداً')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('📒', style: TextStyle(fontSize: 64)),
              const SizedBox(height: 8),
              const Text('سجل الديون', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('سجّل الدخول لحفظ ديونك بأمان'),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: () => _signIn(context),
                icon: const Icon(Icons.login),
                label: const Padding(padding: EdgeInsets.all(10), child: Text('تسجيل الدخول بحساب Google')),
              ),
            ]),
          ),
        ),
      );
}

class HomePage extends StatelessWidget {
  final User user;
  const HomePage({super.key, required this.user});

  CollectionReference<Map<String, dynamic>> get col =>
      FirebaseFirestore.instance.collection('users').doc(user.uid).collection('debtors');

  Future<void> _add(BuildContext context) async {
    final nm = TextEditingController(), am = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('شخص جديد'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nm, decoration: const InputDecoration(labelText: 'الاسم')),
          TextField(
              controller: am,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'الدين الأولي (اختياري)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('إضافة')),
        ],
      ),
    );
    if (ok != true || nm.text.trim().isEmpty) return;
    final a = parseAmount(am.text) ?? 0;
    await col.add({
      'name': nm.text.trim(),
      'balance': a,
      'log': a > 0 ? [{'k': 'd', 'a': a, 't': DateTime.now().millisecondsSinceEpoch}] : [],
      'created': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> _delete(BuildContext context, DocumentSnapshot<Map<String, dynamic>> d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('حذف «${d['name']}»؟'),
        content: const Text('سيتم حذف الاسم وسجله بالكامل ولا يمكن التراجع.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('حذف')),
        ],
      ),
    );
    if (ok == true) await d.reference.delete();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('📒 سجل الديون'),
          actions: [
            IconButton(
              tooltip: 'تسجيل الخروج',
              icon: const Icon(Icons.logout),
              onPressed: () async {
                await GoogleSignIn().signOut();
                await FirebaseAuth.instance.signOut();
              },
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _add(context),
          icon: const Icon(Icons.person_add),
          label: const Text('شخص جديد'),
        ),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: col.snapshots(),
          builder: (c, s) {
            if (!s.hasData) return const Center(child: CircularProgressIndicator());
            final docs = s.data!.docs.toList()
              ..sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
            final total = docs.fold<num>(0, (p, d) => p + ((d['balance'] as num) > 0 ? d['balance'] as num : 0));
            return Column(children: [
              Card(
                margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                child: ListTile(
                  title: const Text('مجموع الديون المستحقة'),
                  subtitle: Text(money(total),
                      style: const TextStyle(color: Colors.red, fontSize: 22, fontWeight: FontWeight.bold)),
                ),
              ),
              Expanded(
                child: docs.isEmpty
                    ? const Center(child: Text('لا يوجد مدينون بعد'))
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 90),
                        itemCount: docs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (c, i) {
                          final d = docs[i];
                          return Material(
                            color: const Color(0xFF8EC5FF),
                            borderRadius: BorderRadius.circular(14),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () => showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                builder: (_) => PersonSheet(ref: d.reference),
                              ),
                              onLongPress: () => _delete(context, d),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(children: [
                                  Expanded(
                                      child: Text(d['name'],
                                          style: const TextStyle(
                                              color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold))),
                                  Text(money(d['balance']),
                                      style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                                ]),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ]);
          },
        ),
      );
}

class PersonSheet extends StatefulWidget {
  final DocumentReference<Map<String, dynamic>> ref;
  const PersonSheet({super.key, required this.ref});
  @override
  State<PersonSheet> createState() => _PersonSheetState();
}

class _PersonSheetState extends State<PersonSheet> {
  final ctrl = TextEditingController();

  Future<void> _act(bool debt) async {
    final a = parseAmount(ctrl.text);
    if (a == null) return;
    await widget.ref.update({
      'balance': FieldValue.increment(debt ? a : -a),
      'log': FieldValue.arrayUnion([
        {'k': debt ? 'd' : 'p', 'a': a, 't': DateTime.now().millisecondsSinceEpoch}
      ]),
    });
    ctrl.clear();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: widget.ref.snapshots(),
          builder: (c, s) {
            final m = s.data?.data();
            if (m == null) return const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()));
            final log = ((m['log'] as List?) ?? []).reversed.take(15).toList();
            return SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(m['name'], style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                Text(money(m['balance']), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                TextField(
                  controller: ctrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'المبلغ بالدينار العراقي', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: Colors.red, padding: const EdgeInsets.all(14)),
                      onPressed: () => _act(true),
                      child: const Text('إضافة دين'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.all(14)),
                      onPressed: () => _act(false),
                      child: const Text('تسديد دين'),
                    ),
                  ),
                ]),
                const SizedBox(height: 14),
                for (final l in log)
                  ListTile(
                    dense: true,
                    title: Text('${l['k'] == 'd' ? 'دين +' : 'تسديد −'}${money(l['a'])}',
                        style: TextStyle(color: l['k'] == 'd' ? Colors.red : Colors.green)),
                    trailing: Text(DateFormat('dd/MM/yyyy').format(DateTime.fromMillisecondsSinceEpoch(l['t']))),
                  ),
              ]),
            );
          },
        ),
      );
}
