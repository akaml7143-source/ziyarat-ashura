import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'app_localization.dart';
import 'package:share_plus/share_plus.dart';

const _ownerUid = 'WvoTCtdUdYhbMluOwfwmBg6CJSL2';
const _gold = Color(0xFFFFD700);
String _t(String ar, String fa) => appLanguage.value == 'fa' ? fa : ar;

class GroupKhatmaPage extends StatefulWidget {
  const GroupKhatmaPage({super.key});
  @override
  State<GroupKhatmaPage> createState() => _GroupKhatmaPageState();
}
class _GroupKhatmaPageState extends State<GroupKhatmaPage> {
  bool loading = true;
  String? error;
  final links = AppLinks();
  StreamSubscription<Uri>? linkSub;
  bool get isOwner => Firebase.apps.isNotEmpty && FirebaseAuth.instance.currentUser?.uid == _ownerUid;

  @override
  void initState() {
    super.initState();
    _init();
    linkSub = links.uriLinkStream.listen(_openLink);
    links.getInitialLink().then((uri) { if (uri != null) _openLink(uri); });
  }
  @override
  void dispose() { linkSub?.cancel(); super.dispose(); }
  Future<void> _init() async {
    try {
      if (Firebase.apps.isEmpty) throw StateError(_t('خدمة الختمات غير متاحة حالياً.', 'سرویس ختم‌ها در دسترس نیست.'));
      if (FirebaseAuth.instance.currentUser == null) await FirebaseAuth.instance.signInAnonymously();
    } catch (e) { error = e.toString(); }
    if (mounted) setState(() => loading = false);
  }
  void _openLink(Uri uri) {
    if (uri.scheme == 'ziyaratashura' && uri.host == 'khatma' && uri.pathSegments.isNotEmpty && mounted) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => KhatmaDetailPage(id: uri.pathSegments.first)));
    }
  }
  void _msg(String s) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s))); }

  Future<void> _login() async {
    final email = TextEditingController(), pass = TextEditingController();
    final c = await showDialog<Map<String,String>>(context: context, builder: (x) => AlertDialog(
      title: Text(_t('دخول إدارة الختمات','ورود مدیریت ختم‌ها')),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: email, decoration: InputDecoration(labelText: _t('البريد الإلكتروني','ایمیل'))),
        TextField(controller: pass, obscureText: true, decoration: InputDecoration(labelText: _t('كلمة المرور','گذرواژه'))),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(x), child: Text(_t('إلغاء','لغو'))),
        ElevatedButton(onPressed: () => Navigator.pop(x, {'email':email.text.trim(),'pass':pass.text}), child: Text(_t('دخول','ورود'))),
      ],
    ));
    email.dispose(); pass.dispose(); if (c == null) return;
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(email:c['email']!,password:c['pass']!);
      if (!isOwner) { await FirebaseAuth.instance.signOut(); throw StateError(_t('هذا الحساب لا يملك صلاحية الإدارة.','این حساب اجازه مدیریت ندارد.')); }
      if (mounted) setState(() {});
    } catch(e) { _msg(e.toString()); }
  }

  Future<Map<String,dynamic>?> _form([Map<String,dynamic>? old]) async {
    final title=TextEditingController(text:old?['title'] as String? ?? '');
    final desc=TextEditingController(text:old?['description'] as String? ?? '');
    final ints=TextEditingController(text:((old?['intentions'] as List?)??const []).join('\n'));
    final result=await showDialog<Map<String,dynamic>>(context:context,builder:(x)=>AlertDialog(
      title:Text(old==null?_t('إضافة ختمة جديدة','افزودن ختم جدید'):_t('تعديل الختمة','ویرایش ختم')),
      content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        TextField(controller:title,maxLength:100,decoration:InputDecoration(labelText:_t('اسم الختمة','نام ختم'))),
        TextField(controller:desc,maxLines:3,maxLength:500,decoration:InputDecoration(labelText:_t('الوصف والإهداء','توضیحات و اهدا'))),
        TextField(controller:ints,maxLines:5,decoration:InputDecoration(labelText:_t('النيات، كل نية في سطر مستقل','نیت‌ها، هر نیت در یک خط'))),
      ])),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(x),child:Text(_t('إلغاء','لغو'))),
        ElevatedButton(onPressed:(){
          final list=ints.text.split('\n').map((v)=>v.trim()).where((v)=>v.isNotEmpty).toSet().toList();
          if(title.text.trim().isEmpty||list.isEmpty)return;
          Navigator.pop(x,{'title':title.text.trim(),'description':desc.text.trim(),'intentions':list});
        },child:Text(_t('حفظ','ذخیره'))),
      ],
    ));
    title.dispose();desc.dispose();ints.dispose();return result;
  }
  Future<void> _create() async {
    final d=await _form();if(d==null)return;
    try{await FirebaseFunctions.instance.httpsCallable('createGroupKhatma').call(d);_msg(_t('تمت إضافة الختمة.','ختم افزوده شد.'));}
    on FirebaseFunctionsException catch(e){_msg(e.message??e.code);}catch(e){_msg(e.toString());}
  }
  Future<void> _edit(String id,Map<String,dynamic> old) async {
    final d=await _form(old);if(d==null)return;
    try{await FirebaseFunctions.instance.httpsCallable('updateGroupKhatma').call({'khatmaId':id,...d});_msg(_t('تم تحديث الختمة.','ختم به‌روزرسانی شد.'));}
    on FirebaseFunctionsException catch(e){_msg(e.message??e.code);}catch(e){_msg(e.toString());}
  }
  Future<void> _status(String id,String status) async {
    try{await FirebaseFunctions.instance.httpsCallable('setGroupKhatmaStatus').call({'khatmaId':id,'status':status});}
    on FirebaseFunctionsException catch(e){_msg(e.message??e.code);}catch(e){_msg(e.toString());}
  }

  @override
  Widget build(BuildContext context) {
    if(loading)return const Center(child:CircularProgressIndicator());
    if(error!=null)return Center(child:Text(error!,textAlign:TextAlign.center));
    return StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(
      stream:FirebaseFirestore.instance.collection('group_khatmas').orderBy('createdAt',descending:true).snapshots(),
      builder:(context,s){
        if(s.hasError)return Center(child:Text(_t('تعذر تحميل الختمات.','بارگذاری ختم‌ها ناموفق بود.')));
        if(!s.hasData)return const Center(child:CircularProgressIndicator());
        final docs=s.data!.docs;
        return ListView(padding:const EdgeInsets.all(14),children:[
          const _GlobalStats(),
          const SizedBox(height:12),
          if(isOwner) SizedBox(width:double.infinity,child:ElevatedButton.icon(onPressed:_create,icon:const Icon(Icons.add),label:Text(_t('إضافة ختمة جديدة','افزودن ختم جدید'))))
          else Align(alignment:AlignmentDirectional.centerEnd,child:TextButton.icon(onPressed:_login,icon:const Icon(Icons.admin_panel_settings),label:Text(_t('دخول الإدارة','ورود مدیریت')))),
          const SizedBox(height:10),
          Text(_t('الختمات الجماعية','ختم‌های گروهی'),style:const TextStyle(color:_gold,fontSize:20,fontWeight:FontWeight.bold)),
          if(docs.isEmpty)Text(_t('لا توجد ختمات مضافة حالياً.','هنوز ختمی افزوده نشده است.'),textAlign:TextAlign.center),
          ...docs.map((doc){
            final d=doc.data();
            return _KhatmaTile(id:doc.id,data:d,admin:isOwner,
              open:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>KhatmaDetailPage(id:doc.id))),
              edit:()=>_edit(doc.id,d),status:(v)=>_status(doc.id,v));
          }),
        ]);
      },
    );
  }
}

class _GlobalStats extends StatelessWidget {
  const _GlobalStats();
  @override
  Widget build(BuildContext context)=>StreamBuilder<DocumentSnapshot<Map<String,dynamic>>>(
    stream:FirebaseFirestore.instance.collection('group_khatma_stats').doc('global').snapshots(),
    builder:(context,s){
      final d=s.data?.data()??const <String,dynamic>{};
      return Card(child:Padding(padding:const EdgeInsets.all(15),child:Column(children:[
        Text(_t('أثر الزيارة الجماعي','اثر گروهی زیارت'),style:const TextStyle(color:_gold,fontSize:19,fontWeight:FontWeight.bold)),
        Row(children:[
          Expanded(child:_Number(label:_t('إجمالي القراءات','مجموع قرائت‌ها'),value:(d['totalReadings'] as num?)?.toInt()??0)),
          Expanded(child:_Number(label:_t('المشاركون','شرکت‌کنندگان'),value:(d['totalParticipants'] as num?)?.toInt()??0)),
        ]),
        Text(_t('عداد الختمات الجماعية فقط، مستقل تماماً عن عداد زيارة عاشوراء الخاص.','این شمارنده فقط برای ختم‌های گروهی است و کاملاً مستقل از شمارنده شخصی است.'),textAlign:TextAlign.center),
      ])));
    },
  );
}
class _Number extends StatelessWidget {
  final String label;final int value;
  const _Number({required this.label,required this.value});
  @override
  Widget build(BuildContext context)=>Column(children:[
    Text('$value',style:const TextStyle(color:_gold,fontSize:26,fontWeight:FontWeight.bold)),
    Text(label,textAlign:TextAlign.center),
  ]);
}
class _KhatmaTile extends StatelessWidget {
  final String id;final Map<String,dynamic> data;final bool admin;
  final VoidCallback open,edit;final ValueChanged<String> status;
  const _KhatmaTile({required this.id,required this.data,required this.admin,required this.open,required this.edit,required this.status});
  @override
  Widget build(BuildContext context){
    final state=data['status'] as String? ?? 'open';
    final count=(data['intentions'] as List?)?.length??0;
    return Card(child:ListTile(onTap:open,title:Text(data['title'] as String? ?? '',style:const TextStyle(color:_gold,fontWeight:FontWeight.bold)),
      subtitle:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        if((data['description'] as String? ?? '').isNotEmpty)Text(data['description'] as String),
        Text(_t(state=='open'?'مفتوحة':state=='paused'?'متوقفة مؤقتاً':'مؤرشفة',state=='open'?'باز':state=='paused'?'متوقف':'بایگانی')),
        Text(_t('$count نيات','$count نیت')),
        StreamBuilder<DocumentSnapshot<Map<String,dynamic>>>(stream:FirebaseFirestore.instance.collection('group_khatma_stats').doc(id).snapshots(),builder:(context,s){
          final v=s.data?.data()??const <String,dynamic>{};
          return Text(_t('${v['totalReadings']??0} قراءة  •  ${v['totalParticipants']??0} مشارك','${v['totalReadings']??0} قرائت  •  ${v['totalParticipants']??0} مشارک'));
        }),
      ]),
      trailing:admin?PopupMenuButton<String>(onSelected:(v){if(v=='edit'){edit();}else{status(v);}},itemBuilder:(_)=>[
        PopupMenuItem(value:'edit',child:Text(_t('تعديل','ویرایش'))),
        PopupMenuItem(value:'open',child:Text(_t('فتح المشاركة','بازکردن'))),
        PopupMenuItem(value:'paused',child:Text(_t('إيقاف مؤقت','توقف موقت'))),
        PopupMenuItem(value:'archived',child:Text(_t('أرشفة','بایگانی'))),
      ]):const Icon(Icons.chevron_left),
    ));
  }
}

class KhatmaDetailPage extends StatefulWidget {
  final String id;const KhatmaDetailPage({super.key,required this.id});
  @override
  State<KhatmaDetailPage> createState()=>_KhatmaDetailPageState();
}
class _KhatmaDetailPageState extends State<KhatmaDetailPage>{
  String? intention;bool busy=false;
  final dedicationController = TextEditingController();
  @override
  void dispose(){dedicationController.dispose();super.dispose();}
  Future<void> _share(Map<String,dynamic>d,int count)async{
    final title=d['title'] as String? ?? _t('ختمة جماعية','ختم گروهی');
    final uri=Uri(scheme:'ziyaratashura',host:'khatma',path:widget.id);
    await Share.share(_t('أدعوكم للمشاركة في ختمة "$title" ضمن تطبيق زيارة عاشوراء.\nعدد القراءات: $count\nافتحوا التطبيق واختاروا إهداء الزيارة.\n$uri','برای شرکت در ختم "$title" در برنامه زیارت عاشورا دعوتید.\nتعداد قرائت‌ها: $count\n$uri'));
  }
  Future<void> _record()async{
    if(intention==null||busy)return;setState(()=>busy=true);
    try{
      await FirebaseFunctions.instance.httpsCallable('recordGroupKhatmaReading').call({'khatmaId':widget.id,'intention':intention,'dedication':dedicationController.text.trim()});
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(_t('فِي مِيزَانِ حَسَنَاتِكُمْ إِنْ شَاءَ اللهُ','ان‌شاءالله در ترازوی حسنات شما باشد'))));
    }on FirebaseFunctionsException catch(e){
      final ms=e.details is Map?(e.details['retryAfterMs'] as num?)?.toInt():null;
      final msg=ms!=null&&ms>0?_t('يمكنك تسجيل قراءة جديدة بعد ${(ms/60000).ceil()} دقيقة.','پس از ${(ms/60000).ceil()} دقیقه می‌توانید قرائت دیگری ثبت کنید.'):(e.message??e.code);
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(msg)));
    }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}
    finally{if(mounted)setState(()=>busy=false);}
  }
  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text(_t('تفاصيل الختمة','جزئیات ختم')),actions:[IconButton(icon:const Icon(Icons.share),onPressed:()async{
      final k=await FirebaseFirestore.instance.collection('group_khatmas').doc(widget.id).get();
      final s=await FirebaseFirestore.instance.collection('group_khatma_stats').doc(widget.id).get();
      if(k.exists)await _share(k.data()??{},(s.data()?['totalReadings'] as num?)?.toInt()??0);
    })]),
    body:StreamBuilder<DocumentSnapshot<Map<String,dynamic>>>(stream:FirebaseFirestore.instance.collection('group_khatmas').doc(widget.id).snapshots(),builder:(context,k){
      if(!k.hasData)return const Center(child:CircularProgressIndicator());
      if(!k.data!.exists)return Center(child:Text(_t('الختمة غير موجودة.','ختم یافت نشد.')));
      final d=k.data!.data()!;final ints=(d['intentions'] as List?)?.whereType<String>().toList()??<String>[];
      final open=(d['status'] as String? ??'open')=='open';
      if(intention!=null&&!ints.contains(intention))intention=null;
      return StreamBuilder<DocumentSnapshot<Map<String,dynamic>>>(stream:FirebaseFirestore.instance.collection('group_khatma_stats').doc(widget.id).snapshots(),builder:(context,s){
        final v=s.data?.data()??const <String,dynamic>{};final counts=Map<String,dynamic>.from(v['intentionCounts'] as Map? ?? const {});
        return ListView(padding:const EdgeInsets.all(16),children:[
          Text(d['title'] as String? ?? '',textAlign:TextAlign.center,style:const TextStyle(color:_gold,fontSize:23,fontWeight:FontWeight.bold)),
          if((d['description'] as String? ??'').isNotEmpty)Text(d['description'] as String,textAlign:TextAlign.center),
          Row(children:[
            Expanded(child:_Number(label:_t('قراءات الختمة','قرائت‌های ختم'),value:(v['totalReadings'] as num?)?.toInt()??0)),
            Expanded(child:_Number(label:_t('المشاركون','شرکت‌کنندگان'),value:(v['totalParticipants'] as num?)?.toInt()??0)),
          ]),
          Text(_t('اختر نية الزيارة','نیت زیارت را انتخاب کنید'),style:const TextStyle(color:_gold,fontSize:18,fontWeight:FontWeight.bold)),
          ...ints.map((name)=>Card(child:RadioListTile<String>(value:name,groupValue:intention,onChanged:open?(x)=>setState(()=>intention=x):null,title:Text(name),secondary:Text('${counts[name]??0}',style:const TextStyle(color:_gold))))),
          if(open) TextField(controller:dedicationController,maxLength:100,decoration:InputDecoration(labelText:_t('إهداء إلى شخص أو فئة (اختياري)','اهدا به شخص یا گروه (اختیاری)'),helperText:_t('سيظهر المُهدى إليه فقط، دون اسم المشارك.','فقط نام دریافت‌کننده نمایش داده می‌شود، نه نام شرکت‌کننده.'))),
          if(!open)Text(_t('المشاركة متوقفة مؤقتاً.','مشارکت متوقف است.'),textAlign:TextAlign.center)
          else ElevatedButton.icon(onPressed:intention==null||busy?null:_record,icon:busy?const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.check_circle),label:Text(_t('أتممت قراءة الزيارة كاملة','قرائت کامل زیارت را انجام دادم'))),
          Text(_t('يجب الانتظار 15 دقيقة بين كل تسجيل وآخر.','بین هر ثبت قرائت باید ۱۵ دقیقه فاصله باشد.'),textAlign:TextAlign.center),
          const SizedBox(height:15),
          Text(_t('آخر القراءات المسجلة','آخرین قرائت‌ها'),style:const TextStyle(color:_gold,fontWeight:FontWeight.bold)),
          StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(stream:FirebaseFirestore.instance.collection('group_khatma_recent_reads').where('khatmaId',isEqualTo:widget.id).orderBy('createdAt',descending:true).limit(10).snapshots(),builder:(context,r){
            if(!r.hasData||r.data!.docs.isEmpty)return Text(_t('لا توجد قراءات مسجلة بعد.','هنوز قرائتی ثبت نشده است.'));
            return Column(children:r.data!.docs.map((doc){
              final read=doc.data();final stamp=read['createdAt'] as Timestamp?;
              final date=stamp?.toDate().toLocal();
              final dateText=date==null?'':'${date.year}/${date.month.toString().padLeft(2,'0')}/${date.day.toString().padLeft(2,'0')}  ${date.hour.toString().padLeft(2,'0')}:${date.minute.toString().padLeft(2,'0')}';
              final recipient=(read['dedication'] as String? ?? '').trim();
              final subtitle=recipient.isEmpty?dateText:'${_t('إهداء إلى','اهدا به')} $recipient\n$dateText';
              return ListTile(dense:true,title:Text(read['intention'] as String? ?? ''),subtitle:Text(subtitle),leading:const Icon(Icons.check_circle_outline,color:_gold));
            }).toList());
          }),
        ]);
      });
    }),
  );
}
