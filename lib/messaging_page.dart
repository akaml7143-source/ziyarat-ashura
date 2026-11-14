import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

const String ashuraOwnerUid = 'WvoTCtdUdYhbMluOwfwmBg6CJSL2';

class MessagingEntryPage extends StatelessWidget {
  const MessagingEntryPage({super.key});
  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
    stream: FirebaseAuth.instance.authStateChanges(),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      final user = snapshot.data;
      if (user == null) return const MessagingAuthPage();
      if (user.uid == ashuraOwnerUid) return const OwnerInboxPage();
      return UserConversationPage(user: user);
    },
  );
}

class MessagingAuthPage extends StatefulWidget {
  const MessagingAuthPage({super.key});
  @override
  State<MessagingAuthPage> createState() => _MessagingAuthPageState();
}

class _MessagingAuthPageState extends State<MessagingAuthPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _register = true, _busy = false;
  String? _error;

  @override
  void dispose() { _email.dispose(); _password.dispose(); super.dispose(); }

  Future<void> _submit() async {
    final email = _email.text.trim(), password = _password.text;
    if (email.isEmpty || password.length < 6) {
      setState(() => _error = 'أدخل البريد الإلكتروني وكلمة مرور من 6 أحرف على الأقل.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      if (_register) {
        await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email, password: password);
      } else {
        await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: password);
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _authError(e.code));
    } catch (_) {
      setState(() => _error = 'تعذر إكمال العملية. تحقق من الاتصال وحاول مجدداً.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _authError(String code) {
    switch (code) {
      case 'email-already-in-use': return 'هذا البريد مسجل مسبقاً. جرّب تسجيل الدخول.';
      case 'invalid-email': return 'صيغة البريد الإلكتروني غير صحيحة.';
      case 'weak-password': return 'كلمة المرور ضعيفة. استخدم 6 أحرف على الأقل.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential': return 'البريد الإلكتروني أو كلمة المرور غير صحيحة.';
      case 'network-request-failed': return 'تحقق من اتصال الإنترنت.';
      default: return 'تعذر تسجيل الدخول أو إنشاء الحساب. رمز الخطأ: ' + code;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('المراسلة الخاصة')),
    body: Center(child: SingleChildScrollView(
      padding: const EdgeInsets.all(22),
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 460), child: Column(children: [
        const Icon(Icons.lock_outline, size: 54, color: Color(0xFFFFD700)),
        const SizedBox(height: 12),
        Text(_register ? 'إنشاء حساب جديد' : 'تسجيل الدخول',
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('محادثة خاصة بينك وبين إدارة التطبيق', textAlign: TextAlign.center),
        const SizedBox(height: 22),
        TextField(controller: _email, keyboardType: TextInputType.emailAddress,
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(labelText: 'البريد الإلكتروني', border: OutlineInputBorder())),
        const SizedBox(height: 14),
        TextField(controller: _password, obscureText: true, textDirection: TextDirection.ltr,
          decoration: const InputDecoration(labelText: 'كلمة المرور', border: OutlineInputBorder()),
          onSubmitted: (_) { if (!_busy) _submit(); }),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
        ],
        const SizedBox(height: 18),
        SizedBox(width: double.infinity, child: ElevatedButton(
          onPressed: _busy ? null : _submit,
          child: _busy ? const SizedBox(width: 22, height: 22,
            child: CircularProgressIndicator(strokeWidth: 2))
            : Text(_register ? 'إنشاء الحساب' : 'دخول'))),
        TextButton(
          onPressed: _busy ? null : () => setState(() { _register = !_register; _error = null; }),
          child: Text(_register ? 'لديك حساب؟ سجّل الدخول' : 'ليس لديك حساب؟ أنشئ حساباً')),
      ])),
    )),
  );
}

class OwnerInboxPage extends StatelessWidget {
  const OwnerInboxPage({super.key});
  Future<void> _signOut() => FirebaseAuth.instance.signOut();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('رسائل المستخدمين'),
      actions: [IconButton(onPressed: _signOut, icon: const Icon(Icons.logout), tooltip: 'تسجيل الخروج')]),
    body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('conversations').orderBy('updatedAt', descending: true).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Center(child: Text('تعذر تحميل المحادثات. تحقق من قواعد Firestore.'));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) return const Center(child: Text('لا توجد رسائل حتى الآن.'));
        return ListView.separated(itemCount: docs.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final doc = docs[index], data = doc.data();
            final email = data['email'] as String? ?? doc.id;
            return ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person_outline)),
              title: Text(email, textDirection: TextDirection.ltr),
              subtitle: const Text('افتح المحادثة للقراءة والرد'),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => ConversationPage(conversationId: doc.id, title: email, ownerMode: true))),
            );
          });
      }),
  );
}

class UserConversationPage extends StatelessWidget {
  final User user;
  const UserConversationPage({super.key, required this.user});
  @override
  Widget build(BuildContext context) => ConversationPage(
    conversationId: user.uid, title: 'مراسلتي مع إدارة التطبيق',
    ownerMode: false, userEmail: user.email ?? '');
}

class ConversationPage extends StatefulWidget {
  final String conversationId, title;
  final bool ownerMode;
  final String userEmail;
  const ConversationPage({super.key, required this.conversationId, required this.title,
    required this.ownerMode, this.userEmail = ''});
  @override
  State<ConversationPage> createState() => _ConversationPageState();
}

class _ConversationPageState extends State<ConversationPage> {
  final _message = TextEditingController();
  bool _sending = false;
  @override
  void dispose() { _message.dispose(); super.dispose(); }

  Future<void> _send() async {
    final body = _message.text.trim();
    final user = FirebaseAuth.instance.currentUser;
    if (body.isEmpty || user == null || _sending) return;
    setState(() => _sending = true);
    try {
      final db = FirebaseFirestore.instance;
      final conversation = db.collection('conversations').doc(widget.conversationId);
      final existing = await conversation.get();
      if (!existing.exists && !widget.ownerMode) {
        await conversation.set({
          'uid': user.uid, 'email': user.email ?? '',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        await conversation.set({'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
      }
      await conversation.collection('messages').add({
        'senderUid': user.uid, 'text': body,
        'createdAt': FieldValue.serverTimestamp(),
      });
      _message.clear();
    } on FirebaseException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر إرسال الرسالة. رمز الخطأ: ' + e.code)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر إرسال الرسالة. حاول مرة أخرى.')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _signOut() => FirebaseAuth.instance.signOut();

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: widget.ownerMode ? const [] : [
          IconButton(onPressed: _signOut, icon: const Icon(Icons.logout), tooltip: 'تسجيل الخروج')]),
      body: Column(children: [
        Expanded(child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('conversations').doc(widget.conversationId)
            .collection('messages').orderBy('createdAt').snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) return const Center(child: Text('تعذر تحميل الرسائل. تحقق من الاتصال والصلاحيات.'));
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            final docs = snapshot.data!.docs;
            if (docs.isEmpty) return const Center(child: Text('ابدأ بكتابة رسالتك لإدارة التطبيق.'));
            return ListView.builder(padding: const EdgeInsets.all(12), itemCount: docs.length,
              itemBuilder: (context, index) {
                final data = docs[index].data();
                final mine = data['senderUid'] == currentUid;
                return Align(alignment: mine ? Alignment.centerLeft : Alignment.centerRight,
                  child: Container(constraints: const BoxConstraints(maxWidth: 310),
                    margin: const EdgeInsets.symmetric(vertical: 5),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: mine ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.20)
                        : Theme.of(context).colorScheme.surface,
                      border: Border.all(color: mine ? Theme.of(context).colorScheme.primary
                        : Colors.grey.withValues(alpha: 0.35)),
                      borderRadius: BorderRadius.circular(14)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(data['text'] as String? ?? ''),
                      const SizedBox(height: 4),
                      Text(mine ? 'أنت' : 'إدارة التطبيق',
                        style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    ])));
              });
          })),
        SafeArea(top: false, child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          child: Row(children: [
            Expanded(child: TextField(controller: _message, minLines: 1, maxLines: 4, maxLength: 2000,
              decoration: const InputDecoration(hintText: 'اكتب رسالتك...',
                border: OutlineInputBorder(), counterText: ''))),
            const SizedBox(width: 8),
            IconButton.filled(onPressed: _sending ? null : _send,
              icon: _sending ? const SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send),
              tooltip: 'إرسال'),
          ]))),
      ]),
    );
  }
}
