import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

const Color gold = Color(0xFFFFD700);
const Color green = Color(0xFF1B4332);
const Color darkBackground = Color(0xFF121212);

final FlutterLocalNotificationsPlugin notifications =
    FlutterLocalNotificationsPlugin();

Future<void> initNotifications() async {
  tzdata.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Asia/Baghdad'));
  const android = AndroidInitializationSettings('@mipmap/ic_launcher');
  const settings = InitializationSettings(android: android);
  await notifications.initialize(settings);
}

Future<bool> askNotificationPermission() async {
  final android = notifications.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  return await android?.requestNotificationsPermission() ?? true;
}

Future<void> scheduleDailyReminder(int hour, int minute) async {
  final now = tz.TZDateTime.now(tz.local);
  var scheduled = tz.TZDateTime(
      tz.local, now.year, now.month, now.day, hour, minute);
  if (!scheduled.isAfter(now)) {
    scheduled = scheduled.add(const Duration(days: 1));
  }
  const details = NotificationDetails(
    android: AndroidNotificationDetails(
      'ashura_daily_reminder',
      'تذكير زيارة عاشوراء',
      channelDescription: 'تذكير يومي بقراءة زيارة عاشوراء',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );
  await notifications.zonedSchedule(
    1001,
    'إشعار',
    'عندما يتّسع يومك لزيارة عاشوراء رغم ضيقه، فهذا هو التوفيق بعينه.',
    scheduled,
    details,
    androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    matchDateTimeComponents: DateTimeComponents.time,
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initNotifications();
  runApp(const AshuraApp());
}

class AshuraApp extends StatefulWidget {
  const AshuraApp({super.key});
  @override
  State<AshuraApp> createState() => _AshuraAppState();
}

class _AshuraAppState extends State<AshuraApp> {
  bool isDarkMode = true;
  double fontSize = 20;
  bool entered = false;
  bool loaded = false;

  @override
  void initState() {
    super.initState();
    loadSettings();
  }

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      isDarkMode = prefs.getBool('ashura_dark') ?? true;
      fontSize = prefs.getDouble('ashura_font') ?? 20;
      entered = prefs.getBool('ashura_entered') ?? false;
      loaded = true;
    });
  }

  Future<void> toggleTheme() async {
    setState(() => isDarkMode = !isDarkMode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('ashura_dark', isDarkMode);
  }

  Future<void> changeFontSize(double delta) async {
    setState(() => fontSize = (fontSize + delta).clamp(16.0, 32.0));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('ashura_font', fontSize);
  }

  Future<void> enterApp() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('ashura_entered', true);
    if (mounted) setState(() => entered = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'زيارة عاشوراء',
      themeMode: isDarkMode ? ThemeMode.dark : ThemeMode.light,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: darkBackground,
        cardColor: const Color(0xFF1E1E1E),
        colorScheme: const ColorScheme.dark(
          primary: gold,
          surface: Color(0xFF1E1E1E),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1F1F1F),
          foregroundColor: gold,
          centerTitle: true,
        ),
        bottomNavigationBarTheme:
            const BottomNavigationBarThemeData(backgroundColor: Color(0xFF1F1F1F)),
      ),
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF9F6F0),
        cardColor: Colors.white,
        colorScheme: const ColorScheme.light(
          primary: green,
          surface: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: green,
          foregroundColor: gold,
          centerTitle: true,
        ),
        bottomNavigationBarTheme:
            const BottomNavigationBarThemeData(backgroundColor: Colors.white),
      ),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: entered
            ? HomeScreen(
                isDarkMode: isDarkMode,
                fontSize: fontSize,
                onToggleTheme: toggleTheme,
                onChangeFontSize: changeFontSize,
              )
            : WelcomeScreen(onEnter: enterApp),
      ),
    );
  }
}

class WelcomeScreen extends StatelessWidget {
  final VoidCallback onEnter;
  const WelcomeScreen({super.key, required this.onEnter});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/wallpaper_1326_1793992364813.jpg', fit: BoxFit.cover),
          Container(color: Colors.black.withValues(alpha: 0.38)),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 30, 22, 26),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    children: [
                      Text('بِسْمِ اللهِ الرَّحْمٰنِ الرَّحِيم',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: gold, fontSize: 21,
                              fontWeight: FontWeight.bold)),
                      SizedBox(height: 12),
                      Text('زيارة عاشوراء',
                          style: TextStyle(color: Colors.white, fontSize: 30,
                              fontWeight: FontWeight.bold)),
                      Text('السلام عليك يا أبا عبد الله الحسين',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white, fontSize: 18)),
                    ],
                  ),
                  Column(
                    children: [
                      const Text(
                        'إذا شئتَ النَّجاةَ فَزُرْ حُسيناً .. لِكَي تَلْقَى الإلهَ قَريرَ عَينِ\n'
                        'فإنَّ النارَ لَيْسَ تَمَسُّ جِسماً .. عَليهِ غُبارُ زوّارِ الحُسين',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white, fontSize: 19,
                            height: 2, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 28),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: onEnter,
                          icon: const Icon(Icons.arrow_forward),
                          label: const Text('الدخول إلى البرنامج',
                              style: TextStyle(fontSize: 19,
                                  fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: green,
                            foregroundColor: gold,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: const BorderSide(color: gold)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  final bool isDarkMode;
  final double fontSize;
  final VoidCallback onToggleTheme;
  final Function(double) onChangeFontSize;

  const HomeScreen({
    super.key,
    required this.isDarkMode,
    required this.fontSize,
    required this.onToggleTheme,
    required this.onChangeFontSize,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      ZiyaratPage(fontSize: widget.fontSize),
      FavorsPage(fontSize: widget.fontSize),
      FarVisitPage(fontSize: widget.fontSize),
      NoticePage(fontSize: widget.fontSize),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('زيارة عاشوراء وفضلها',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SettingsPage(
                  isDarkMode: widget.isDarkMode,
                  fontSize: widget.fontSize,
                  onToggleTheme: widget.onToggleTheme,
                  onChangeFontSize: widget.onChangeFontSize,
                ),
              ),
            ),
            icon: const Icon(Icons.settings),
            tooltip: 'الإعدادات',
          ),
        ],
      ),
      body: IndexedStack(index: selectedIndex, children: pages),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: selectedIndex,
        onTap: (i) => setState(() => selectedIndex = i),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: gold,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.menu_book), label: 'الزيارة'),
          BottomNavigationBarItem(icon: Icon(Icons.auto_awesome), label: 'فضل الزيارة'),
          BottomNavigationBarItem(icon: Icon(Icons.place), label: 'من بعيد'),
          BottomNavigationBarItem(icon: Icon(Icons.notifications_active), label: 'إشعار'),
        ],
      ),
    );
  }
}

class SectionCard extends StatelessWidget {
  final String title;
  final String content;
  final double fontSize;
  final bool highlight;
  const SectionCard({
    super.key,
    required this.title,
    required this.content,
    required this.fontSize,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: highlight ? const BorderSide(color: gold, width: 1) : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 19,
                fontWeight: FontWeight.bold, color: gold)),
            const Divider(),
            SelectableText(content,
                style: TextStyle(fontSize: fontSize, height: 1.95)),
          ],
        ),
      ),
    );
  }
}

class ZiyaratPage extends StatelessWidget {
  final double fontSize;
  const ZiyaratPage({super.key, required this.fontSize});

  static const String introduction =
      'قال صالح بن عقبة وسيف بن عميرة: قال علقمة بن محمد الحضرمي: قلت للباقر صلوات الله وسلامه عليه: علّمني دعاءً أدعو به ذلك اليوم إذا أنا زرته من قرب، ودعاءً أدعو به إذا لم أزره من قرب وأومأت من بُعد البلاد ومن داري بالسلام إليه.\n\n'
      'قال: فقال لي: يا علقمة، إذا أنت صلّيت الركعتين بعد أن تومئ إليه بالسلام فقل بعد الإيماء إليه من بعد التكبير هذا القول (أي الزيارة الآتية)، فإنك إذا قلت ذلك فقد دعوت بما يدعو به زوّاره من الملائكة، وكتب الله لك مئة ألف ألف درجة، وكنت كمن استشهدوا مع الحسين عليه السلام حتى تشاركهم في درجاتهم، وما عُرفت إلا في الشهداء الذين استشهدوا معه، وكُتب لك ثواب زيارة كل نبي وكل رسول، وزيارة كل من زار الحسين عليه السلام منذ يوم قُتل عليه السلام وعلى أهل بيته.';

  static const String visitText =
      'السَّلَامُ عَلَيْكَ يَا أَبَا عَبْدِ اللهِ، السَّلَامُ عَلَيْكَ يَا ابْنَ رَسُولِ اللهِ، السَّلَامُ عَلَيْكَ يَا ابْنَ أَمِيرِ الْمُؤْمِنِينَ، وَابْنَ سَيِّدِ الْوَصِيِّينَ، السَّلَامُ عَلَيْكَ يَا ابْنَ فَاطِمَةَ سَيِّدَةِ نِسَاءِ الْعَالَمِينَ، السَّلَامُ عَلَيْكَ يَا ثَارَ اللهِ وَابْنَ ثَارِهِ وَالْوِتْرَ الْمَوْتُورَ، السَّلَامُ عَلَيْكَ وَعَلَى الْأَرْوَاحِ الَّتِي حَلَّتْ بِفِنَائِكَ، عَلَيْكُمْ مِنِّي جَمِيعاً سَلَامُ اللهِ أَبَداً مَا بَقِيتُ وَبَقِيَ اللَّيْلُ وَالنَّهَارُ.\n\n'
      'يَا أَبَا عَبْدِ اللهِ، لَقَدْ عَظُمَتِ الرَّزِيَّةُ وَجَلَّتْ، وَعَظُمَتِ الْمُصِيبَةُ بِكَ عَلَيْنَا وَعَلَى جَمِيعِ أَهْلِ الْإِسْلَامِ، وَجَلَّتْ وَعَظُمَتْ مُصِيبَتُكَ فِي السَّمَاوَاتِ عَلَى جَمِيعِ أَهْلِ السَّمَاوَاتِ. فَلَعَنَ اللهُ أُمَّةً أَسَّسَتْ أَسَاسَ الظُّلْمِ وَالْجَوْرِ عَلَيْكُمْ أَهْلَ الْبَيْتِ، وَلَعَنَ اللهُ أُمَّةً دَفَعَتْكُمْ عَنْ مَقَامِكُمْ وَأَزَالَتْكُمْ عَنْ مَرَاتِبِكُمُ الَّتِي رَتَّبَكُمُ اللهُ فِيهَا، وَلَعَنَ اللهُ أُمَّةً قَتَلَتْكُمْ، وَلَعَنَ اللهُ الْمُمَهِّدِينَ لَهُمْ بِالتَّمْكِينِ مِنْ قِتَالِكُمْ، بَرِئْتُ إِلَى اللهِ وَإِلَيْكُمْ مِنْهُمْ وَأَشْيَاعِهِمْ وَأَتْبَاعِهِمْ وَأَوْلِيَائِهِمْ.\n\n'
      'يَا أَبَا عَبْدِ اللهِ، إِنِّي سِلْمٌ لِمَنْ سَالَمَكُمْ، وَحَرْبٌ لِمَنْ حَارَبَكُمْ إِلَى يَوْمِ الْقِيَامَةِ، وَلَعَنَ اللهُ آلَ زِيَادٍ وَآلَ مَرْوَانَ، وَلَعَنَ اللهُ بَنِي أُمَيَّةَ قَاطِبَةً، وَلَعَنَ اللهُ ابْنَ مَرْجَانَةَ، وَلَعَنَ اللهُ عُمَرَ بْنَ سَعْدٍ، وَلَعَنَ اللهُ شِمْراً، وَلَعَنَ اللهُ أُمَّةً أَسْرَجَتْ وَأَلْجَمَتْ وَتَنَقَّبَتْ لِقِتَالِكَ. بِأَبِي أَنْتَ وَأُمِّي، لَقَدْ عَظُمَ مُصَابِي بِكَ، فَأَسْأَلُ اللهَ الَّذِي أَكْرَمَ مَقَامَكَ وَأَكْرَمَنِي بِكَ أَنْ يَرْزُقَنِي طَلَبَ ثَارِكَ مَعَ إِمَامٍ مَنْصُورٍ مِنْ أَهْلِ بَيْتِ مُحَمَّدٍ صَلَّى اللهُ عَلَيْهِ وَآلِهِ.\n\n'
      'اللَّهُمَّ اجْعَلْنِي عِنْدَكَ وَجِيهاً بِالْحُسَيْنِ عَلَيْهِ السَّلَامُ فِي الدُّنْيَا وَالْآخِرَةِ. يَا أَبَا عَبْدِ اللهِ، إِنِّي أَتَقَرَّبُ إِلَى اللهِ وَإِلَى رَسُولِهِ وَإِلَى أَمِيرِ الْمُؤْمِنِينَ وَإِلَى فَاطِمَةَ وَإِلَى الْحَسَنِ وَإِلَيْكَ بِمُوَالَاتِكَ، وَبِالْبَرَاءَةِ مِمَّنْ قَاتَلَكَ وَنَصَبَ لَكَ الْحَرْبَ، وَبِالْبَرَاءَةِ مِمَّنْ أَسَّسَ أَسَاسَ الظُّلْمِ وَالْجَوْرِ عَلَيْكُمْ، وَأَبْرَأُ إِلَى اللهِ وَإِلَى رَسُولِهِ مِمَّنْ أَسَّسَ أَسَاسَ ذَلِكَ وَبَنَى عَلَيْهِ بُنْيَانَهُ، وَجَرَى فِي ظُلْمِهِ وَجَوْرِهِ عَلَيْكُمْ وَعَلَى أَشْيَاعِكُمْ. بَرِئْتُ إِلَى اللهِ وَإِلَيْكُمْ مِنْهُمْ، وَأَتَقَرَّبُ إِلَى اللهِ ثُمَّ إِلَيْكُمْ بِمُوَالَاتِكُمْ وَمُوَالَاةِ وَلِيِّكُمْ، وَبِالْبَرَاءَةِ مِنْ أَعْدَائِكُمْ وَالنَّاصِبِينَ لَكُمُ الْحَرْبَ، وَبِالْبَرَاءَةِ مِنْ أَشْيَاعِهِمْ وَأَتْبَاعِهِمْ. إِنِّي سِلْمٌ لِمَنْ سَالَمَكُمْ، وَحَرْبٌ لِمَنْ حَارَبَكُمْ، وَوَلِيٌّ لِمَنْ وَالَاكُمْ، وَعَدُوٌّ لِمَنْ عَادَاكُمْ. فَأَسْأَلُ اللهَ الَّذِي أَكْرَمَنِي بِمَعْرِفَتِكُمْ وَمَعْرِفَةِ أَوْلِيَائِكُمْ، وَرَزَقَنِي الْبَرَاءَةَ مِنْ أَعْدَائِكُمْ، أَنْ يَجْعَلَنِي مَعَكُمْ فِي الدُّنْيَا وَالْآخِرَةِ، وَأَنْ يُثَبِّتَ لِي عِنْدَكُمْ قَدَمَ صِدْقٍ فِي الدُّنْيَا وَالْآخِرَةِ، وَأَسْأَلُهُ أَنْ يُبَلِّغَنِي الْمَقَامَ الْمَحْمُودَ لَكُمْ عِنْدَ اللهِ، وَأَنْ يَرْزُقَنِي طَلَبَ ثَارِي مَعَ إِمَامِ هُدًى ظَاهِرٍ نَاطِقٍ بِالْحَقِّ مِنْكُمْ، وَأَسْأَلُ اللهَ بِحَقِّكُمْ وَبِالشَّأْنِ الَّذِي لَكُمْ عِنْدَهُ أَنْ يُعْطِيَنِي بِمُصَابِي بِكُمْ أَفْضَلَ مَا يُعْطِي مُصَاباً بِمُصِيبَتِهِ، مُصِيبَةً مَا أَعْظَمَهَا وَأَعْظَمَ رَزِيَّتَهَا فِي الْإِسْلَامِ وَفِي جَمِيعِ السَّمَاوَاتِ وَالْأَرْضِ.\n\n'
      'اللَّهُمَّ اجْعَلْنِي فِي مَقَامِي هَذَا مِمَّنْ تَنَالُهُ مِنْكَ صَلَوَاتٌ وَرَحْمَةٌ وَمَغْفِرَةٌ. اللَّهُمَّ اجْعَلْ مَحْيَايَ مَحْيَا مُحَمَّدٍ وَآلِ مُحَمَّدٍ، وَمَمَاتِي مَمَاتَ مُحَمَّدٍ وَآلِ مُحَمَّدٍ. اللَّهُمَّ إِنَّ هَذَا يَوْمٌ تَبَرَّكَتْ بِهِ بَنُو أُمَيَّةَ وَابْنُ آكِلَةِ الْأَكْبَادِ، اللَّعِينُ ابْنُ اللَّعِينِ عَلَى لِسَانِكَ وَلِسَانِ نَبِيِّكَ صَلَّى اللهُ عَلَيْهِ وَآلِهِ فِي كُلِّ مَوْطِنٍ وَمَوْقِفٍ وَقَفَ فِيهِ نَبِيُّكَ صَلَّى اللهُ عَلَيْهِ وَآلِهِ.\n\n'
      'اللَّهُمَّ الْعَنْ أَبَا سُفْيَانَ وَمُعَاوِيَةَ وَيَزِيدَ بْنَ مُعَاوِيَةَ، عَلَيْهِمْ مِنْكَ اللَّعْنَةُ أَبَدَ الْآبِدِينَ. وَهَذَا يَوْمٌ فَرِحَتْ بِهِ آلُ زِيَادٍ وَآلُ مَرْوَانَ بِقَتْلِهِمُ الْحُسَيْنَ صَلَوَاتُ اللهِ عَلَيْهِ. اللَّهُمَّ فَضَاعِفْ عَلَيْهِمُ اللَّعْنَ مِنْكَ وَالْعَذَابَ الْأَلِيمَ.\n\n'
      'اللَّهُمَّ إِنِّي أَتَقَرَّبُ إِلَيْكَ فِي هَذَا الْيَوْمِ وَفِي مَوْقِفِي هَذَا وَأَيَّامِ حَيَاتِي بِالْبَرَاءَةِ مِنْهُمْ وَاللَّعْنَةِ عَلَيْهِمْ، وَبِالْمُوَالَاةِ لِنَبِيِّكَ وَآلِ نَبِيِّكَ عَلَيْهِ وَعَلَيْهِمُ السَّلَامُ.';

  static const String cursePhrase =
      'اللَّهُمَّ الْعَنْ أَوَّلَ ظَالِمٍ ظَلَمَ حَقَّ مُحَمَّدٍ وَآلِ مُحَمَّدٍ وَآخِرَ تَابِعٍ لَهُ عَلَى ذَلِكَ. اللَّهُمَّ الْعَنِ الْعِصَابَةَ الَّتِي جَاهَدَتِ الْحُسَيْنَ وَشَايَعَتْ وَبَايَعَتْ وَتَابَعَتْ عَلَى قَتْلِهِ، اللَّهُمَّ الْعَنْهُمْ جَمِيعاً.';
  static const String salamPhrase =
      'السَّلَامُ عَلَيْكَ يَا أَبَا عَبْدِ اللهِ وَعَلَى الْأَرْوَاحِ الَّتِي حَلَّتْ بِفِنَائِكَ، عَلَيْكَ مِنِّي سَلَامُ اللهِ أَبَداً مَا بَقِيتُ وَبَقِيَ اللَّيْلُ وَالنَّهَارُ، وَلَا جَعَلَهُ اللهُ آخِرَ الْعَهْدِ مِنِّي لِزِيَارَتِكُمْ. السَّلَامُ عَلَى الْحُسَيْنِ وَعَلَى عَلِيِّ بْنِ الْحُسَيْنِ وَعَلَى أَوْلَادِ الْحُسَيْنِ وَعَلَى أَصْحَابِ الْحُسَيْنِ.';
  static const String afterHundred =
      'اللَّهُمَّ خُصَّ أَنْتَ أَوَّلَ ظَالِمٍ بِاللَّعْنِ مِنِّي، وَابْدَأْ بِهِ أَوَّلاً، ثُمَّ الْعَنِ الثَّانِيَ وَالثَّالِثَ وَالرَّابِعَ. اللَّهُمَّ الْعَنْ يَزِيدَ خَامِساً، وَالْعَنْ عُبَيْدَ اللهِ بْنَ زِيَادٍ وَابْنَ مَرْجَانَةَ وَعُمَرَ بْنَ سَعْدٍ وَشِمْراً وَآلَ أَبِي سُفْيَانَ وَآلَ زِيَادٍ وَآلَ مَرْوَانَ إِلَى يَوْمِ الْقِيَامَةِ.';
  static const String sajda =
      'اللَّهُمَّ لَكَ الْحَمْدُ حَمْدَ الشَّاكِرِينَ لَكَ عَلَى مُصَابِهِمْ، الْحَمْدُ لِلَّهِ عَلَى عَظِيمِ رَزِيَّتِي. اللَّهُمَّ ارْزُقْنِي شَفَاعَةَ الْحُسَيْنِ يَوْمَ الْوُرُودِ، وَثَبِّتْ لِي قَدَمَ صِدْقٍ عِنْدَكَ مَعَ الْحُسَيْنِ وَأَصْحَابِ الْحُسَيْنِ الَّذِينَ بَذَلُوا مُهَجَهُمْ دُونَ الْحُسَيْنِ عَلَيْهِ السَّلَامُ.';

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SectionCard(title: 'مقدمة الزيارة', content: introduction,
            fontSize: fontSize, highlight: true),
        const SizedBox(height: 12),
        SectionCard(title: 'نص زيارة عاشوراء كاملاً', content: visitText,
            fontSize: fontSize),
        const SizedBox(height: 12),
        CounterWidget(
          storageKey: 'ashura_lعن_counter',
          title: 'ثم تقول (100 مرّة) - اللعن',
          phrase: cursePhrase,
          fontSize: fontSize,
        ),
        const SizedBox(height: 12),
        CounterWidget(
          storageKey: 'ashura_salam_counter',
          title: 'ثم تقول (100 مرّة) - السلام',
          phrase: salamPhrase,
          fontSize: fontSize,
        ),
        const SizedBox(height: 12),
        SectionCard(title: 'بعد المئة', content: afterHundred,
            fontSize: fontSize, highlight: true),
        const SizedBox(height: 12),
        SectionCard(title: 'سجدة الزيارة', content: 'ثم تسجد وتقول:\n\n$sajda',
            fontSize: fontSize, highlight: true),
        const SizedBox(height: 20),
        const Text('المصدر: مفاتيح الجنان، زيارة عاشوراء.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey)),
      ],
    );
  }
}

class CounterWidget extends StatefulWidget {
  final String title;
  final String phrase;
  final double fontSize;
  final String storageKey;
  const CounterWidget({
    super.key,
    required this.title,
    required this.phrase,
    required this.fontSize,
    required this.storageKey,
  });
  @override
  State<CounterWidget> createState() => _CounterWidgetState();
}

class _CounterWidgetState extends State<CounterWidget> {
  int count = 0;
  @override
  void initState() {
    super.initState();
    loadCount();
  }

  Future<void> loadCount() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => count = prefs.getInt(widget.storageKey) ?? 0);
  }

  Future<void> increment() async {
    if (count >= 100) return;
    setState(() => count++);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(widget.storageKey, count);
    if (count == 100) {
      try {
        if (await Vibration.hasVibrator() == true) {
          await Vibration.vibrate(duration: 450);
        }
      } catch (_) {}
    }
  }

  Future<void> reset() async {
    setState(() => count = 0);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(widget.storageKey, 0);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: gold, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(widget.title, style: const TextStyle(fontSize: 19,
                fontWeight: FontWeight.bold, color: gold)),
            const SizedBox(height: 12),
            SelectableText(widget.phrase, textAlign: TextAlign.center,
                style: TextStyle(fontSize: widget.fontSize, height: 1.9)),
            const SizedBox(height: 18),
            Text('$count / 100', style: const TextStyle(fontSize: 25,
                fontWeight: FontWeight.bold, color: gold)),
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: count / 100,
              minHeight: 8,
              borderRadius: BorderRadius.circular(10),
              color: count == 100 ? Colors.green : gold,
              backgroundColor: Colors.grey.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: count < 100 ? increment : null,
                  icon: const Icon(Icons.touch_app),
                  label: Text('العدد: $count'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: green, foregroundColor: Colors.white),
                ),
                IconButton(onPressed: reset, icon: const Icon(Icons.refresh),
                    tooltip: 'إعادة العداد'),
              ],
            ),
            if (count == 100)
              const Text('أحسنت، اكتمل العدد',
                  style: TextStyle(color: Colors.green,
                      fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

class FavorsPage extends StatelessWidget {
  final double fontSize;
  const FavorsPage({super.key, required this.fontSize});
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SectionCard(
          title: 'فضل وعظمة زيارة عاشوراء',
          fontSize: fontSize,
          highlight: true,
          content: 'ورد في رواية علقمة عن الإمام الباقر عليه السلام في فضل هذه الزيارة: «فإنك إذا قلت ذلك فقد دعوت بما يدعو به زوّاره من الملائكة...»\n\nالمصدر: كامل الزيارات، ومصباح المتهجد.',
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'زيارة الإمام الحسين عليه السلام',
          fontSize: fontSize,
          content: 'زيارة الإمام الحسين عليه السلام من القرب أو البعد بابٌ للتوجّه والسلام وإحياء ذكرى نهضته المباركة. ويمكن قراءة الزيارة من المنزل مع استحضار النية والتوجّه إلى الله تعالى.',
        ),
      ],
    );
  }
}

class FarVisitPage extends StatelessWidget {
  final double fontSize;
  const FarVisitPage({super.key, required this.fontSize});
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SectionCard(
          title: 'الزيارة من بعيد',
          fontSize: fontSize,
          highlight: true,
          content: 'يمكنك التوجّه إلى جهة مرقد الإمام الحسين عليه السلام، ثم تستحضر الزيارة وتقول:\n\nالسَّلَامُ عَلَيْكَ يَا أَبَا عَبْدِ اللهِ، السَّلَامُ عَلَيْكَ وَرَحْمَةُ اللهِ وَبَرَكَاتُهُ.\n\nثم اقرأ نص زيارة عاشوراء في قسم «الزيارة المباركة».',
        ),
      ],
    );
  }
}

class NoticePage extends StatelessWidget {
  final double fontSize;
  const NoticePage({super.key, required this.fontSize});
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const SizedBox(height: 35),
        const Icon(Icons.notifications_active, size: 58, color: gold),
        const SizedBox(height: 22),
        SectionCard(
          title: 'إشعار',
          fontSize: fontSize,
          highlight: true,
          content: 'عندما يتّسع يومك لزيارة عاشوراء رغم ضيقه، فهذا هو التوفيق بعينه.',
        ),
        const SizedBox(height: 18),
        const Text('يمكنك تفعيل التذكير اليومي وتحديد وقته من الإعدادات.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 15)),
      ],
    );
  }
}

class SettingsPage extends StatefulWidget {
  final bool isDarkMode;
  final double fontSize;
  final VoidCallback onToggleTheme;
  final Function(double) onChangeFontSize;
  const SettingsPage({
    super.key,
    required this.isDarkMode,
    required this.fontSize,
    required this.onToggleTheme,
    required this.onChangeFontSize,
  });
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool reminderEnabled = false;
  int reminderHour = 20;
  int reminderMinute = 0;

  @override
  void initState() {
    super.initState();
    loadReminder();
  }

  Future<void> loadReminder() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      reminderEnabled = prefs.getBool('ashura_reminder_enabled') ?? false;
      reminderHour = prefs.getInt('ashura_reminder_hour') ?? 20;
      reminderMinute = prefs.getInt('ashura_reminder_minute') ?? 0;
    });
  }

  Future<void> setReminder(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value) {
      final granted = await askNotificationPermission();
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('يرجى السماح بإشعارات التطبيق من إعدادات الهاتف.')),
          );
        }
        return;
      }
      await scheduleDailyReminder(reminderHour, reminderMinute);
    } else {
      await notifications.cancel(1001);
    }
    await prefs.setBool('ashura_reminder_enabled', value);
    if (mounted) setState(() => reminderEnabled = value);
  }

  Future<void> chooseTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: reminderHour, minute: reminderMinute),
    );
    if (picked == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('ashura_reminder_hour', picked.hour);
    await prefs.setInt('ashura_reminder_minute', picked.minute);
    if (mounted) {
      setState(() {
        reminderHour = picked.hour;
        reminderMinute = picked.minute;
      });
    }
    if (reminderEnabled) {
      await scheduleDailyReminder(reminderHour, reminderMinute);
    }
  }

  @override
  Widget build(BuildContext context) {
    final time = TimeOfDay(hour: reminderHour, minute: reminderMinute);
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: SwitchListTile(
              secondary: const Icon(Icons.dark_mode, color: gold),
              title: const Text('الوضع الليلي'),
              subtitle: Text(widget.isDarkMode ? 'مفعّل' : 'غير مفعّل'),
              value: widget.isDarkMode,
              onChanged: (_) => widget.onToggleTheme(),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.text_fields, color: gold),
              title: const Text('حجم الخط'),
              subtitle: Text('الحجم الحالي: ${widget.fontSize.toInt()}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(onPressed: () => widget.onChangeFontSize(-2),
                      icon: const Icon(Icons.remove)),
                  IconButton(onPressed: () => widget.onChangeFontSize(2),
                      icon: const Icon(Icons.add)),
                ],
              ),
            ),
          ),
          Card(
            child: SwitchListTile(
              secondary: const Icon(Icons.notifications_active, color: gold),
              title: const Text('التذكير اليومي'),
              subtitle: const Text('إشعار يومي بموعد زيارة عاشوراء'),
              value: reminderEnabled,
              onChanged: setReminder,
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.access_time, color: gold),
              title: const Text('وقت التذكير'),
              subtitle: Text(time.format(context)),
              trailing: const Icon(Icons.edit),
              onTap: chooseTime,
            ),
          ),
          const SizedBox(height: 18),
          const SectionCard(
            title: 'معلومات المبرمج',
            content: 'المبرمج: كامل الكميتي\nتاريخ إنتاج التطبيق: ٦/١١/٢٠٢٦\n\nنسألكم الدعاء',
            fontSize: 18,
            highlight: true,
          ),
        ],
      ),
    );
  }
}
