import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';

const Color gold = Color(0xFFFFD700);
const Color green = Color(0xFF1B4332);
const Color darkBackground = Color(0xFF121212);

const Map<String, Color> appColors = {
  'أخضر': Color(0xFF1B4332),
  'نيلي': Color(0xFF303B78),
  'عنابي': Color(0xFF7B263A),
  'فيروزي': Color(0xFF176B70),
};

final FlutterLocalNotificationsPlugin notifications =
    FlutterLocalNotificationsPlugin();

late AudioHandler audioHandler;

class AshuraAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final AudioPlayer _player = AudioPlayer();

  AshuraAudioHandler() {
    _player.playbackEventStream.listen(_broadcastState);
    _player.durationStream.listen((duration) {
      final current = mediaItem.value;
      if (current != null && duration != null) {
        mediaItem.add(current.copyWith(duration: duration));
      }
    });
  }

  Future<void> playAsset(
    String assetPath,
    String title, {
    String album = 'زيارة عاشوراء',
  }) async {
    final item = MediaItem(
      id: assetPath,
      title: title,
      album: album,
      artUri: null,
    );
    mediaItem.add(item);
    await _player.stop();
    await _player.setAudioSource(AudioSource.asset(assetPath));
    await _player.play();
  }

  void _broadcastState(PlaybackEvent event) {
    final processing = <ProcessingState, AudioProcessingState>{
      ProcessingState.idle: AudioProcessingState.idle,
      ProcessingState.loading: AudioProcessingState.loading,
      ProcessingState.buffering: AudioProcessingState.buffering,
      ProcessingState.ready: AudioProcessingState.ready,
      ProcessingState.completed: AudioProcessingState.completed,
    }[_player.processingState]!;

    playbackState.add(PlaybackState(
      controls: [
        if (_player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.stop,
      ],
      systemActions: const {MediaAction.seek},
      androidCompactActionIndices: const [0, 1],
      processingState: processing,
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: 0,
    ));
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }
}

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

Future<bool> askExactAlarmPermission() async {
  final android = notifications.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  return await android?.requestExactAlarmsPermission() ?? false;
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
    androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    matchDateTimeComponents: DateTimeComponents.time,
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  audioHandler = await AudioService.init(
    builder: () => AshuraAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.ziyaratashura.audio',
      androidNotificationChannelName: 'استماع زيارة عاشوراء',
      androidNotificationOngoing: true,
    ),
  );
  try {
    await initNotifications();
  } catch (error) {
    debugPrint('تعذر تهيئة الإشعارات: $error');
  }
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
  String selectedFont = 'Amiri';
  String selectedColor = 'أخضر';

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
      final savedFont = prefs.getString('ashura_font_family') ?? 'Amiri';
      selectedFont = savedFont == 'AmiriQuran' ? 'AmiriQuran' : 'Amiri';
      final savedColor = prefs.getString('ashura_theme_color') ?? 'أخضر';
      selectedColor = appColors.containsKey(savedColor) ? savedColor : 'أخضر';
      loaded = true;
    });

    // إعادة جدولة التذكير بعد فتح التطبيق إذا كان مفعّلاً سابقاً.
    if (prefs.getBool('ashura_reminder_enabled') ?? false) {
      final hour = prefs.getInt('ashura_reminder_hour') ?? 20;
      final minute = prefs.getInt('ashura_reminder_minute') ?? 0;
      try {
        await scheduleDailyReminder(hour, minute);
      } catch (error) {
        debugPrint('تعذر إعادة جدولة التذكير: $error');
      }
    }
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

  Future<void> changeFontFamily(String value) async {
    if (value != 'Amiri' && value != 'AmiriQuran') return;
    setState(() => selectedFont = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ashura_font_family', value);
  }

  Future<void> changeThemeColor(String value) async {
    if (!appColors.containsKey(value)) return;
    setState(() => selectedColor = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ashura_theme_color', value);
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
    final primaryColor = appColors[selectedColor] ?? green;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'زيارة عاشوراء',
      themeMode: isDarkMode ? ThemeMode.dark : ThemeMode.light,
      darkTheme: ThemeData(
        fontFamily: selectedFont,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: darkBackground,
        cardColor: const Color(0xFF1E1E1E),
        colorScheme: ColorScheme.dark(
          primary: primaryColor,
          secondary: gold,
          surface: const Color(0xFF1E1E1E),
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
        fontFamily: selectedFont,
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF9F6F0),
        cardColor: Colors.white,
        colorScheme: ColorScheme.light(
          primary: primaryColor,
          secondary: gold,
          surface: Colors.white,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: primaryColor,
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
                selectedFont: selectedFont,
                selectedColor: selectedColor,
                onToggleTheme: toggleTheme,
                onChangeFontSize: changeFontSize,
                onChangeFontFamily: changeFontFamily,
                onChangeThemeColor: changeThemeColor,
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
                            backgroundColor: Theme.of(context).colorScheme.primary,
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
  final String selectedFont;
  final String selectedColor;
  final VoidCallback onToggleTheme;
  final Function(double) onChangeFontSize;
  final Function(String) onChangeFontFamily;
  final Function(String) onChangeThemeColor;

  const HomeScreen({
    super.key,
    required this.isDarkMode,
    required this.fontSize,
    required this.selectedFont,
    required this.selectedColor,
    required this.onToggleTheme,
    required this.onChangeFontSize,
    required this.onChangeFontFamily,
    required this.onChangeThemeColor,
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
      AbbasVisitPage(fontSize: widget.fontSize),
      ListeningPage(fontSize: widget.fontSize),
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
                  selectedFont: widget.selectedFont,
                  selectedColor: widget.selectedColor,
                  onToggleTheme: widget.onToggleTheme,
                  onChangeFontSize: widget.onChangeFontSize,
                  onChangeFontFamily: widget.onChangeFontFamily,
                  onChangeThemeColor: widget.onChangeThemeColor,
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
        selectedItemColor: Theme.of(context).colorScheme.primary,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.menu_book), label: 'الزيارة'),
          BottomNavigationBarItem(icon: Icon(Icons.auto_awesome), label: 'فضل الزيارة'),
          BottomNavigationBarItem(icon: Icon(Icons.mosque), label: 'زيارة العباس'),
          BottomNavigationBarItem(icon: Icon(Icons.headphones), label: 'استماع الزيارة'),
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
        const SizedBox(height: 12),
        CompletedVisitCounter(),
        const SizedBox(height: 20),
        const Text('المصدر: مفاتيح الجنان، زيارة عاشوراء.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey)),
      ],
    );
  }
}


class CompletedVisitCounter extends StatefulWidget {
  const CompletedVisitCounter({super.key});

  @override
  State<CompletedVisitCounter> createState() => _CompletedVisitCounterState();
}

class _CompletedVisitCounterState extends State<CompletedVisitCounter> {
  static const String storageKey = 'ashura_completed_visits';
  int completedVisits = 0;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    loadCompletedVisits();
  }

  Future<void> loadCompletedVisits() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      completedVisits = prefs.getInt(storageKey) ?? 0;
      isLoading = false;
    });
  }

  Future<void> markVisitCompleted() async {
    final nextCount = completedVisits + 1;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(storageKey, nextCount);
    if (!mounted) return;
    setState(() => completedVisits = nextCount);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تقبّل الله زيارتكم، تم تسجيل القراءة')),
    );
  }

  Future<void> resetCount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('إعادة العداد'),
        content: const Text('هل تريد تصفير عدد الزيارات المكتملة؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('تصفير'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(storageKey, 0);
    if (mounted) setState(() => completedVisits = 0);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: gold, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text(
              'عداد الزيارات المكتملة',
              style: TextStyle(
                color: gold,
                fontSize: 19,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'بعد إكمال قراءة الزيارة مع فقراتها، اضغط الزر لتسجيلها.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            isLoading
                ? const CircularProgressIndicator()
                : Text(
                    '$completedVisits زيارة مكتملة',
                    style: const TextStyle(
                      fontSize: 25,
                      color: gold,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: isLoading ? null : markVisitCompleted,
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('أتممت قراءة الزيارة كاملة'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: isLoading || completedVisits == 0 ? null : resetCount,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('تصفير العداد'),
              ),
            ),
          ],
        ),
      ),
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
                      backgroundColor: Theme.of(context).colorScheme.primary, foregroundColor: Colors.white),
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
          title: 'زيارة عاشوراء وآثارها العجيبة عند الأئمة (ع) والعلماء الكبار',
          fontSize: fontSize,
          highlight: true,
          content: r'''قد وردت روايات كثيرة حول زيارة عاشوراء. وقد علم الإمام الباقر (عليه السلام) هذه الزيارة لأحد أصحابه وهو علقمة بن محمد الحضري.

إن زيارة عاشوراء تعتبر من الأدعية التي أكد الأئمة المعصومون (عليهم السلام) والعلماء الكبار على مواظبتها، وأن لها آثاراً بناءة وفريدة على الأفراد.''',
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'ثواب قراءة زيارة عاشوراء في كلام الأئمة المعصومين (عليهم السلام)',
          fontSize: fontSize,
          highlight: true,
          content: r'''1- قال الإمام محمد الباقر (ع) لعلقمة بن محمد الحضري الذي سأل عن كيفية زيارة الإمام الحسين (ع) من بعيد:

"بعد أن تشير إليه بالسلام فتصلي ركعتين ثم تقرأ زيارة عاشوراء. فإذا قرأت هذه الزيارة فقد دعوته بما يدعوه به كل ملك يريد زيارته، وكتب الله لك ألف ألف حسنة، وحط عنك ألف ألف سيئة، ورفع لك ألف ألف ضعف. أنت مثل أولئك الذين بذلوا مهجهم دون الإمام. حتى أنك تشارك في درجاتهم". (كامل الزيارات - ص 74).

2- قال الإمام الصادق (عليه السلام) لأحد أصحابه، صفوان، عن آثار زيارة عاشوراء:

"تَعَاهَدْ هَذِهِ الزِّيَارَةَ وَادْعُ بِهَذَا الدُّعَاءِ وَزُرْ بِهِ فَإِنِّي ضَامِنٌ عَلَى اللَّهِ تَعَالَى لِكُلِّ مَنْ زَارَ بِهَذِهِ الزِّيَارَةِ وَدَعَا بِهَذَا الدُّعَاءِ مِنْ قُرْبٍ أَوْ بُعْدٍ أَنَّ زِيَارَتَهُ مَقْبُولَةٌ وَسَعْيَهُ مَشْكُورٌ وَسَلَامَهُ وَاصِلٌ غَيْرُ مَحْجُوبٍ وَحَاجَتَهُ مَقْضِيَّةٌ مِنَ اللَّهِ بَالِغاً مَا بَلَغَتْ وَلَا يُخَيِّبُهُ فَإِنَّ اللَّهَ لَا يُخْلِفُ الْمِيعَادَ". (بحار الأنوار، ج 98، ص 300).

3- جاء في رواية أخرى عن الإمام الباقر (عليه السلام):

"لو يعلم الناس ما في زيارة الحسين (عليه السلام) من الفضل لماتوا شوقاً إليه، وتقطّعت أنفسهم عليه حسرات". (بحار الأنوار - ج 101 - ص 18).

4- قال الإمام الصادق (عليه السلام) أيضاً:

"أقسم الله تعالى أنه من قرأ هذه الزيارة والدعاء، فإنه -تعالى- سيقبل زيارته ودعاءه ويقضي حاجته، ويعتقه من النار ويسكنه الجنة ويرزقه الشفاعة ومساعدة الناس".

5- جاء في كتاب مفاتيح الجنان وقبل نص زيارة عاشوراء حديث عن الإمام الباقر عليه السلام في ثواب هذه الزيارة فيقول:

"إن هذا الدعاء دعاء تدعو به الملائكة، ويكتب الله لك مائة ألف ألف درجة، وتكون كمن استشهد مع الحسين عليه السلام. وكتب لك ثواب زيارة كل نبي ورسول، وثواب زيارة كل من زار الحسين (عليه السلام) من يوم استشهاده".

6- جاء في كتاب مفاتيح الجنان قبل زيارة الجامعة الكبيرة وبعد دعاء العلقمة كلام عن إمام الزمان (ع) الموجه للسيد الرشتي هكذا:

"لماذا لا تقوم بقراءة زيارة عاشوراء؟: عاشوراء، عاشوراء، عاشوراء".''',
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'فضل قراءة زيارة عاشوراء في أقوال علماء وكبار الدين',
          fontSize: fontSize,
          highlight: true,
          content: r'''1- روى العلامة الشيخ عبد الهادي الحائري المازندراني عن أبيه الحاج ملا أبو الحسن أنني رأيت الحاج ميرزا علي نقي الطباطبائي في المنام بعد وفاته فقلت له: "هل لك أمنية"؟ قال: "لي أمنية واحدة، وهي عدم زيارتي لقراءة زيارة عاشوراء كل يوم في الدنيا".

وكان من عادة السيد أن يؤدي قراءة زيارة عاشوراء طوال العقد الأول من شهر محرم الحرام، ولكن بعد وفاته ندم على عدم تمكنه من أداء قراءتها طوال العام.

2- يقول آية الله الشبيري الزنجاني أحد مراجع التقليد:

"لقد أصبحت إحدى عيني ابن السيد الحاج سيد محمد البجنوردي عمياء بسبب حالة مرضية، وحسب الأطباء، وحتى الأطباء في الخارج، ومع تقدم الحالة، فإن عينه الأخرى سوف تصبح عمياء أيضاً. ولكن الرجل شفي. وقد رأى أحد أقاربه سيد الشهداء في المنام، فقال له: لقد أخذنا من الله سلامة عينه الأخرى لأنه استمر في قراءة زيارة عاشوراء".

3- يقول المرجع الكبير آية الله العظمى بهجت (ره) عن زيارة عاشوراء:

"إن زيارة عاشوراء من الأحاديث القدسية، وهذه الأمور هي التي دفعت علماءنا الكبار وأساتذتنا، أن يقيدوا أنفسهم على قراءتها على الرغم من كثرة انشغالاتهم العلمية وكثرة المراجعات إليهم، بحيث أن أستاذنا المرحوم الحاج الشيخ محمد حسين الأصفهاني، طلب من الله تعالى أن لا يقبض روحه في آخر عمره، إلا وهو في حالة قراءة زيارة عاشوراء؛ فاستجاب الله دعاءه، وقبض الله روحه بعد أن انتهى من قراءة هذه الزيارة".

4- روى المرحوم الشهيد دستغيب (رحمه الله) قصة عن فضل قراءة زيارة عاشوراء هكذا:

"رأى أحد علماء النجف سيدنا عزرائيل في المنام قبل نحو مئة عام، فسلم عليه، ثم سأله: من أين أنت؟ قال ملك الموت: من شيراز! لقد أخذت روح المرحوم ميرزا إبراهيم المحلاتي. فسأل الشيخ: في أي وضع كانت روحه؟ قال عزرائيل: في خير الأحوال وخير حدائق البرزخ. وضع الله ألف ملك لتنفيذ أوامر الشيخ. سأل العالم: ما هذه النعم؟ قال: من أجل قراءة زيارة عاشوراء".

ويقال إن المرحوم الميرزا إبراهيم المحلاتي لم يترك قراءة زيارة عاشوراء طوال الثلاثين سنة الأخيرة من حياته، وكان كل يوم لا يستطيع فيه القيام بها بسبب المرض أو غيره من الأسباب يعين نائباً عنه.

5- روي عن العارف الكبير المرحوم آية الله ميرزا سيد علي آقا قاضي (رحمه الله) (معلم آية الله بهجت والعلامة الطباطبائي) أنه بعد وفاته رآه شخص في المنام وسأله: "أي العمل أهم هناك؟".

قال: "قراءة زيارة عاشوراء، وأنا نادم لأني قرأت زيارة عاشوراء في كل يوم مرة واحدة ولم أقرأه مرتين!".

وكان المرحوم القاضي رحمه الله يقول: "كل ما عندي فهو من سيد الشهداء عليه السلام والقرآن".''',
        ),
        const SizedBox(height: 12),
        const Text(
          'تنبيه: نُقلت النصوص والمراجع كما وردت في المادة المرسلة، ويُستحسن مراجعة ألفاظ الروايات وأرقام الصفحات في مصادرها قبل اعتمادها للنشر.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey, height: 1.7),
        ),
      ],
    );
  }
}

class AbbasVisitPage extends StatelessWidget {
  final double fontSize;
  const AbbasVisitPage({super.key, required this.fontSize});

  static const String ziyaraText = r'''زيارة الامام العباس (عليه السلام)

سَلامُ اللهِ وَسَلامُ مَلائِكَتِهِ الْمُقَرَّبِينَ وَأَنْبِيَائِهِ الْمُرْسَلِينَ ، وَعِبَادِهِ الصَّالِحِينَ وَجَمِيعِ الشُّهَداءِ وَالصِّدِّيقِينَ ، وَالزَّاكِيَاتُ الطَّيِّبَاتُ فِيمَا تَغْتَدِي وَتَرُوحُ عَلَيْكَ يَابْنَ أَمِيرِ الْمُؤْمِنِينَ ، أَشْهَدُ لَكَ بِالتَّسْلِيمِ وَالتَّصْدِيقِ وَالْوَفَاءِ وَالنَّصِيحَةِ ، لِخَلَفِ النَّبِيِّ الْمُرْسَلِ ـ صَلَّى اللهُ عَلَيْهِ وَآلِهِ ـ ، وَالسِّبْطِ الْمُنْتَجَبِ ، وَالدَّلِيلِ الْعَالِمِ ، وَالْوَصِيِّ الْمُبَلِّغِ ، وَالْمَظْلُومِ الْمُهْتَضَمِ ، فَجَزَاكَ اللهُ عَن رَّسُولِهِ وَعَنْ أَمِيرِ الْمُؤْمِنينَ وَعَنْ فَاطِمَةَ والْحَسَنِ وَالْحُسَيْنِ ـ صَلَوَاتُ اللهِ عَلَيْهِمْ ـ أَفْضَلَ الْجَزاءِ ، بِمَا صَبَرْتَ وَاحْتَسَبْتَ وَأَعَنْتَ ، فَنِعْمَ عُقْبَى الدَّارِ ، لَعَنَ اللهُ مَنْ قَتَلَكَ ، وَلَعَنَ اللهُ مَنْ جَهِلَ حَقَّكَ وَاسْتَخَفَّ بِحُرْمَتِكَ ، وَلَعَنَ اللهُ مَنْ حَالَ بَيْنَكَ وَبَيْنَ مَاءِ الْفُرَاتِ ، أَشْهَدُ أَنَّكَ قُتِلْتَ مَظْلُوماً ، وَأَنَّ اللهَ مُنْجِزٌ لَّكُم مَّا وَعَدَكُمْ ، جِئْتُكَ يَابْنَ أَمِيرِ اْلُمْؤْمِنينَ وَافِداً إِلَيْكُمْ ، وَقَلْبِي مُسَلِّمٌ لَّكُمْ وَتابِعٌ ، وَأَنَا لَكُمْ تَابِعٌ وَنُصْرَتِي لَكُم مُّعَدَّةٌ ، حَتّى يَحْكُمَ اللهُ وَهُوَ خَيْرُ الْحَاكِمِينَ ، فَمَعَكُمْ مَعَكُمْ لا مَعَ عَدُوِّكُمْ ، إِنِّي بِكُمْ وَبِإِيَابِكُمْ مِنَ الْمُؤْمِنينَ ، وَبِمَنْ خَالَفَكُمْ وَقَتَلَكُمْ مِنَ الْكَافَرِينَ ، قَتَلَ اللهُ أُمَّةً قَتَلَتْكُمْ بِالأَيْدِي وَالأَلْسُنِ .

ثمّ ادخل فانكبّ على القبر وقلْ :

اَلسَّلامُ عَلَيْكَ أَيُّهَا الْعَبْدُ الصَّالِحُ الْمُطِيعُ للهِ وَلِرَسُولِهِ وَلِأَميرِ الْمُؤْمِنينَ وَالْحَسَنِ والْحُسَيْنِ ـ صَلَّى اللهُ عَلَيْهِمْ وَسَلَّمَ ـ ، اَلسَّلامُ عَلَيْكَ وَرَحْمَةُ اللهِ وَبَرَكَاتُهُ ، وَمَغْفِرَتُهُ وَرِضْوَانُهُ وَعَلَى رُوحِكَ وَبَدَنِكَ ، أَشْهَدُ ـ وأُشْهِدُ اللهَ ـ أَنَّكَ مَضَيْتَ عَلَى مَا مَضَى بِهِ الْبَدْرِيُّونَ وَالْمُجَاهِدُونَ فِي سَبيلِ اللهِ الْمُنَاصِحُونَ لَهُ فِي جِهَادِ أَعْدَائِهِ ، الْمُبَالِغُونَ فِي نُصْرَةِ أَوْلِيَائِهِ ، الذَّابُّونَ عَنْ أَحِبَّائِهِ ، فَجَزاكَ اللهُ أَفْضَلَ الْجَزاءِ ، وَأَكْثَرَ الْجَزاءِ ، وَأَوْفَرَ الْجَزَاءِ ، وَأَوْفَى جَزاءِ أَحَدٍ مِمَّن وَّفَى بِبَيْعَتِهِ ، وَاسْتَجابَ لَهُ دَعْوَتَهُ ، وَأَطَاعَ وُلاةَ أَمْرِهِ ، أَشْهَدُ أَنَّكَ قَدْ بَالَغْتَ فِي النَّصِيحَةِ وَأَعْطَيْتَ غايَةَ الْمَجْهُودِ ، فَبَعَثَكَ اللهُ فِي الشُّهَداءِ ، وَجَعَلَ رُوحَكَ مَعَ أَرْوَاحِ السُّعَداءِ ، وَأَعْطَاكَ مِنْ جِنَانِهِ أَفْسَحَهَا مَنْزِلاً وَّأَفْضَلَهَا غُرَفاً ، وَّرَفَعَ ذِكْرَكَ فِي عِلِّيِّينَ ، وَحَشَرَكَ مَعَ النَّبِيِّينَ وَالصِّدِّيقِينَ وَالشُّهَداءِ وَالصَّالِحِينَ ، وَحَسُنَ أُولَئِكَ رَفِيقاً ، أَشْهَدُ أَنَّكَ لَمْ تَهِن وَّلَمْ تَنْكُلْ ، وَأَنَّكَ مَضَيْتَ عَلَى بَصِيرَةٍ مِنْ أَمْرِكَ مُقْتَدِياً بِالصَّالِحِينَ ، وَمُتَّبِعاً لِّلنَّبِيِّينَ ، فَجَمَعَ اللهُ بَيْنَنَا وَبَيْنَكَ وَبَيْنَ رَسُولِهِ وَأَوْلِيَائِهِ فِي مَنَازِلِ الْمُخْبِتِينَ ، فَإِنَّهُ أَرْحَمُ الرَّاحِمِينَ .

ثمّ صرْ إلى الرأس الشريف وصلّ ركعتين وادعُ بهذا الدعاء :

اَللَّـهُمَّ صَلِّ عَلَى مُحَمَّدٍ وَّآلِ مُحَمَّدٍ ، وَّلا تَدَعْ لِي فِي هذَا الْمَكَانِ الْمُكَرَّمِ وَالْمَشْهَدِ الْمُعَظَّمِ ذَنْباً إِلَّا غَفَرْتَهُ ، وَلا هَمًّا إِلَّا فَرَّجَتَهُ ، وَلا مَرَضاً إِلَّا شَفَيْتَهُ ، وَلا عَيْباً إِلَّا سَتَرْتَهُ ، وَلا رِزْقاً إِلَّا بَسَطتَّهُ ، وَلا خَوْفاً إِلَّا آمَنْتَهُ ، وَلا شَمْلاً إِلَّا جَمَعْتَهُ ، وَلا غائِباً إِلَّا حَفِظْتَهُ وَأَدْنَيْتَهُ ، وَلا حَاجَةً مِّنْ حَوَائِجِ الدُّنْيَا وَالْآخِرَةِ لَكَ فِيهَا رِضًى وَلِيَ فِيهَا صَلاحٌ إِلَّا قَضَيْتَها يَا أَرْحَمَ الرَّاحِمِينَ .

ثمّ عُدْ إلى جهة الرّجلَيْن وقُلْ :

اَلسَّلامُ عَلَيْكَ يَا أَبَا الْفَضْلِ الْعَبَّاسَ بْنَ أَمِيرِ الْمُؤْمِنينَ ، اَلسَّلامُ عَلَيْكَ يَابْنَ سَيِّدِ الْوَصِيِّينَ ، اَلسَّلامُ عَلَيْكَ يَابْنَ أَوَّلِ الْقَوْمِ إِسْلاماً ، وَّأَقْدَمِهِمْ إِيْمَاناً وَّأَقْوَمِهِمْ بِدِينِ اللهِ ، وَأَحْوَطِهِمْ عَلَى الإِسْلامِ ، أَشْهَدُ لَقَدْ نَصَحْتَ للهِ وَلِرَسُولِهِ وَلِأَخيكَ ، فَنِعْمَ الأَخُ الْمُواسي ، فَلَعَنَ اللهُ أُمَّةً قَتَلَتْكَ ، وَلَعَنَ اللهُ أُمَّةً ظَلَمَتْكَ ، وَلَعَنَ اللهُ أُمَّةً اسْتَحَلَّتْ مِنْكَ الْمَحَارِمَ ، وَانْتَهَكَتْ حُرْمَةَ الإِسْلامِ ، فَنِعْمَ الصَّابِرُ الْمُجَاهِدُ الْمُحَامِي النَّاصِرُ ، وَالأَخُ الدَّافِعُ عَنْ أَخِيهِ ، الْمُجيبُ إِلَى طَاعَةِ رَبِّهِ ، الرَّاغِبُ فِيمَا زَهِدَ فِيهِ غَيْرُهُ مِنَ الثَّوَابِ الْجَزِيلِ وَالثَّنَاءِ الْجَمِيلِ ، وَأَلْحَقَكَ اللهُ بِدَرَجَةِ آبَائِكَ فِي جَنَّاتِ النَّعِيمِ ، اَللَّـهُمَّ إِنِّي تَعَرَّضْتُ لِزِيَارَةِ أَوْلِيَائِكَ رَغْبَةً فِي ثَوَابِكَ ، وَرَجَاءً لِّمَغْفِرَتِكَ وَجَزيلِ إِحْسَانِكَ ، فَأَسْأَلُكَ أَنْ تُصَلِّيَ عَلَى مُحَمَّدٍ وَّآلِهِ الطَّاهِرِينَ ، وَأَنْ تَجْعَلَ رِزْقِي بِهِمْ دَارًّا ، وَّعَيْشِي بِهِمْ قَارًّا ، وَّزِيَارَتِي بِهِمْ مَقْبُولَةً ، وَّحَيَاتِي بِهِمْ طَيِّبَةً ، وَّأَدْرِجْنِي إِدْرَاجَ الْمُكْرَمِينَ ، وَاجْعَلْنِي مِمَّن يَّنْقَلِبُ مِنْ زِيَارَةِ مَشَاهِدِ أَحِبَّائِكَ مُفْلِحاً مُّنْجِحاً ، قَدِ اسْتَوْجَبَ غُفْرَانَ الذُّنُوبِ وَسَتْرَ الْعُيُوبِ وَكَشْفَ الْكُرُوبِ ، إِنَّكَ أَهْلُ التَّقْوَى وَأَهْلُ الْمَغْفِرَةِ .''';

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SectionCard(
          title: 'زيارة الإمام العباس (عليه السلام)',
          content: ziyaraText,
          fontSize: fontSize,
          highlight: true,
        ),
        const SizedBox(height: 14),
        Card(
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: gold, width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Icon(Icons.headphones, color: gold, size: 38),
                const SizedBox(height: 8),
                const Text(
                  'استماع زيارة أبي الفضل العباس',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: gold),
                ),
                const SizedBox(height: 6),
                const Text('القارئ: الشيخ شبر معله', textAlign: TextAlign.center),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      try {
                        await (audioHandler as AshuraAudioHandler).playAsset(
                          'assets/shibr_maalla_abbas.mp3',
                          'الشيخ شبر معله',
                          album: 'زيارة أبي الفضل العباس',
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('جاري تشغيل زيارة أبي الفضل العباس بصوت الشيخ شبر معله')),
                          );
                        }
                      } catch (error) {
                        debugPrint('Abbas audio error: $error');
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('تعذر تشغيل التسجيل؛ تحقق من وجود الملف assets/shibr_maalla_abbas.mp3')),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('تشغيل الزيارة'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class ListeningPage extends StatelessWidget {
  final double fontSize;
  const ListeningPage({super.key, required this.fontSize});

  static const List<Map<String, String>> readers = [
    {'name': 'الشيخ شبر معله', 'file': 'shibr_maalla.mp3'},
    {'name': 'الشيخ باقر المقدسي', 'file': 'baqir_almaqdisi.mp3'},
    {'name': 'الرادود باسم الكربلائي', 'file': 'basim_alkarbalaei.mp3'},
    {'name': 'الرادود أحمد الفتلاوي', 'file': 'ahmed_alftlawi.mp3'},
    {'name': 'الرادود محمد باقر الخاقاني', 'file': 'mohammed_baqir_alkhaqani.mp3'},
    {'name': 'الرادود أبا ذر الحلواجي', 'file': 'aba_thar_alhelwachi.mp3'},
    {'name': 'الحاج علي الكعبي', 'file': 'ali_alkabi.mp3'},
    {'name': 'الحاج مهدي سماواتي', 'file': 'mahdi_samawati.mp3'},
    {'name': 'الحاج محمود كريمي', 'file': 'mahmoud_karimi.mp3'},
    {'name': 'الرادود عمار الكناني', 'file': 'ammar_alkinani.mp3'},
  ];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Image.asset(
            'assets/wallpaper_1326_1793992364813.jpg',
            height: 190,
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              height: 150,
              color: Theme.of(context).colorScheme.primary,
              alignment: Alignment.center,
              child: const Icon(Icons.mosque, color: gold, size: 64),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'استماع زيارة عاشوراء',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: fontSize + 3, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'اختر القارئ للاستماع إلى التسجيل المحفوظ داخل التطبيق',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 12),
        ...List.generate(readers.length, (index) {
          final reader = readers[index];
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 5),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primary,
                child: Text('${index + 1}',
                    style: const TextStyle(color: Colors.white)),
              ),
              title: Text(
                reader['name']!,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
              subtitle: const Text('تشغيل من ملفات التطبيق دون إنترنت'),
              trailing: IconButton(
                tooltip: 'تشغيل',
                icon: const Icon(Icons.play_circle_fill, color: gold, size: 32),
                onPressed: () async {
                  try {
                    await (audioHandler as AshuraAudioHandler).playAsset(
                      'assets/${reader['file']!}',
                      reader['name']!,
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('جاري تشغيل: ${reader['name']}')),
                      );
                    }
                  } catch (error) {
                    debugPrint('Audio error: $error');
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('تعذر تشغيل ${reader['name']}؛ تحقق من وجود الملف في assets.'),
                        ),
                      );
                    }
                  }
                },
              ),
            ),
          );
        }),
        const SizedBox(height: 10),
        const Text(
          'يمكن متابعة التشغيل عبر إشعار الوسائط أثناء الانتقال بين صفحات التطبيق، وقد يستمر بعد إطفاء الشاشة وفق إعدادات النظام.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey, height: 1.6),
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
  final String selectedFont;
  final String selectedColor;
  final VoidCallback onToggleTheme;
  final Function(double) onChangeFontSize;
  final Function(String) onChangeFontFamily;
  final Function(String) onChangeThemeColor;
  const SettingsPage({
    super.key,
    required this.isDarkMode,
    required this.fontSize,
    required this.selectedFont,
    required this.selectedColor,
    required this.onToggleTheme,
    required this.onChangeFontSize,
    required this.onChangeFontFamily,
    required this.onChangeThemeColor,
  });
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool reminderEnabled = false;
  int reminderHour = 20;
  int reminderMinute = 0;
  late String localFont;
  late String localColor;

  @override
  void initState() {
    super.initState();
    localFont = widget.selectedFont;
    localColor = widget.selectedColor;
    loadReminder();
  }

  @override
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedFont != widget.selectedFont) {
      localFont = widget.selectedFont;
    }
    if (oldWidget.selectedColor != widget.selectedColor) {
      localColor = widget.selectedColor;
    }
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
      final notificationGranted = await askNotificationPermission();
      if (!notificationGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('يرجى السماح بإشعارات التطبيق من إعدادات الهاتف.'),
            ),
          );
        }
        return;
      }

      final exactGranted = await askExactAlarmPermission();
      if (!exactGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'يرجى السماح للتطبيق بالمنبّهات الدقيقة من إعدادات الهاتف.',
              ),
            ),
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
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.palette, color: gold),
                    title: Text('لون التطبيق الرئيسي'),
                  ),
                  DropdownButtonFormField<String>(
                    value: localColor,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                    items: appColors.keys.map((colorName) =>
                      DropdownMenuItem<String>(
                        value: colorName,
                        child: Text(colorName),
                      ),
                    ).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => localColor = value);
                        widget.onChangeThemeColor(value);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.font_download, color: gold),
                    title: Text('نوع الخط'),
                  ),
                  DropdownButtonFormField<String>(
                    value: localFont,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem<String>(
                        value: 'Amiri',
                        child: Text('Amiri - خط النسخ'),
                      ),
                      DropdownMenuItem<String>(
                        value: 'AmiriQuran',
                        child: Text('Amiri Quran - الخط القرآني'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => localFont = value);
                        widget.onChangeFontFamily(value);
                      }
                    },
                  ),
                ],
              ),
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
            title: 'عن التطبيق وتطويره',
            content: 'تطبيق «زيارة عاشوراء» وهو تطبيق ديني روحاني متكامل يُعنى بتيسير قراءة واستماع «زيارة عاشوراء» المباركة ليكون رفيقاً إيمانياً يومياً للمؤمنين أينما كانوا.\n\nاللهم اغفر لي ولوالديّ وارحمهما كما ربّياني صغيراً، واجزهما عني خير ما جزيت والداً عن ولده. اللهم اغفر للمؤمنين والمؤمنات، والمسلمين والمسلمات، الأحياء منهم والأموات، واجمعنا وإياهم في جنات النعيم بجوار محمد وآله الطاهرين.\n\nتطوير وتصميم كامل الكميتي 2026/11/6\n\nجميع الحقوق محفوظة',
            fontSize: 18,
            highlight: true,
          ),
        ],
      ),
    );
  }
}
