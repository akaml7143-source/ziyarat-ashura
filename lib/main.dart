import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';

const Color gold = Color(0xFFFFD700);
const Color green = Color(0xFF26734D);
const Color darkBackground = Color(0xFF121212);

const Map<String, Color> appColors = {
  'أخضر': Color(0xFF26734D),
  'نيلي': Color(0xFF303F9F),
  'ماروني': Color(0xFF800020),
  'فيروزي': Color(0xFF40BFC1),
};

final FlutterLocalNotificationsPlugin notifications =
    FlutterLocalNotificationsPlugin();

late AudioHandler audioHandler;

Future<void> tapFeedback() async {
  try {
    if (await Vibration.hasVibrator() == true) {
      await Vibration.vibrate(duration: 12);
    }
  } catch (_) {}
}

class AshuraAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final AudioPlayer _player = AudioPlayer();

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<bool> get playingStream => _player.playingStream;
  bool get isPlaying => _player.playing;

  Future<void> seekRelative(Duration offset) async {
    final target = _player.position + offset;
    final duration = _player.duration ?? target;
    final bounded = target < Duration.zero
        ? Duration.zero
        : (target > duration ? duration : target);
    await _player.seek(bounded);
  }

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
    unawaited(_player.play());
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

class AshuraReminder {
  final int id;
  final int hour;
  final int minute;
  final List<int> weekdays;
  final bool enabled;

  const AshuraReminder({
    required this.id,
    required this.hour,
    required this.minute,
    required this.weekdays,
    required this.enabled,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'hour': hour,
        'minute': minute,
        'weekdays': weekdays,
        'enabled': enabled,
      };

  factory AshuraReminder.fromJson(Map<String, dynamic> json) => AshuraReminder(
        id: (json['id'] as num).toInt(),
        hour: (json['hour'] as num).toInt(),
        minute: (json['minute'] as num).toInt(),
        weekdays: (json['weekdays'] as List)
            .map((value) => (value as num).toInt())
            .where((day) => day >= 1 && day <= 7)
            .toList(),
        enabled: json['enabled'] == true,
      );

  AshuraReminder copyWith({
    int? hour,
    int? minute,
    List<int>? weekdays,
    bool? enabled,
  }) => AshuraReminder(
        id: id,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
        weekdays: weekdays ?? this.weekdays,
        enabled: enabled ?? this.enabled,
      );
}

const String reminderMessage =
    'عندما يتّسع يومك لزيارة عاشوراء رغم ضيق الوقت، فهذا التوفيق بعينه';

int _notificationId(int reminderId, int weekday) => reminderId * 10 + weekday;

Future<void> cancelReminderNotifications(AshuraReminder reminder) async {
  for (final day in reminder.weekdays) {
    await notifications.cancel(_notificationId(reminder.id, day));
  }
  // Also cancel all seven IDs in case the selected days were edited earlier.
  for (var day = 1; day <= 7; day++) {
    await notifications.cancel(_notificationId(reminder.id, day));
  }
}

Future<void> scheduleReminder(AshuraReminder reminder) async {
  await cancelReminderNotifications(reminder);
  if (!reminder.enabled || reminder.weekdays.isEmpty) return;

  final details = NotificationDetails(
    android: AndroidNotificationDetails(
      'ashura_reminders',
      'منبّهات زيارة عاشوراء',
      channelDescription: 'تذكيرات مخصصة لقراءة زيارة عاشوراء',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );
  final now = tz.TZDateTime.now(tz.local);
  for (final weekday in reminder.weekdays) {
    var scheduled = tz.TZDateTime(
      tz.local, now.year, now.month, now.day, reminder.hour, reminder.minute,
    );
    while (scheduled.weekday != weekday || !scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    await notifications.zonedSchedule(
      _notificationId(reminder.id, weekday),
      'تذكير زيارة عاشوراء',
      reminderMessage,
      scheduled,
      details,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
    );
  }
}

Future<List<AshuraReminder>> loadSavedReminders() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString('ashura_reminders_v2');
  if (raw == null || raw.isEmpty) return [];
  try {
    final decoded = jsonDecode(raw) as List;
    return decoded
        .map((item) => AshuraReminder.fromJson(
            Map<String, dynamic>.from(item as Map)))
        .toList();
  } catch (error) {
    debugPrint('تعذر قراءة المنبّهات المحفوظة: $error');
    return [];
  }
}

Future<void> saveReminders(List<AshuraReminder> reminders) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
    'ashura_reminders_v2',
    jsonEncode(reminders.map((item) => item.toJson()).toList()),
  );
}

Future<void> rescheduleSavedReminders() async {
  final reminders = await loadSavedReminders();
  for (final reminder in reminders) {
    try {
      await scheduleReminder(reminder);
    } catch (error) {
      debugPrint('تعذر إعادة جدولة المنبّه ${reminder.id}: $error');
    }
  }
}

const int salawatReminderNotificationId = 31001;

Future<void> scheduleSalawatReminder({
  required bool enabled,
  required int hour,
  required int minute,
}) async {
  await notifications.cancel(salawatReminderNotificationId);
  if (!enabled) return;
  final now = tz.TZDateTime.now(tz.local);
  var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
  if (!scheduled.isAfter(now)) scheduled = scheduled.add(const Duration(days: 1));
  const details = NotificationDetails(
    android: AndroidNotificationDetails(
      'ashura_reminders',
      'منبّهات زيارة عاشوراء',
      channelDescription: 'تذكيرات الزيارة والصلاة على محمد وآل محمد',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );
  await notifications.zonedSchedule(
    salawatReminderNotificationId,
    'تذكير الصلاة على محمد وآل محمد',
    'هل صليت على محمد وآل محمد هذا اليوم؟',
    scheduled,
    details,
    uiLocalNotificationDateInterpretation:
        UILocalNotificationDateInterpretation.absoluteTime,
    androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    matchDateTimeComponents: DateTimeComponents.time,
  );
}

Future<void> restoreSalawatReminder() async {
  final prefs = await SharedPreferences.getInstance();
  await scheduleSalawatReminder(
    enabled: prefs.getBool('salawat_reminder_enabled') ?? false,
    hour: prefs.getInt('salawat_reminder_hour') ?? 9,
    minute: prefs.getInt('salawat_reminder_minute') ?? 0,
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
    await notifications.cancel(1001); // إلغاء التذكير القديم ذي المعرّف الثابت.
    await rescheduleSavedReminders();
    await restoreSalawatReminder();
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
      entered = false; // شاشة البداية تظهر عند كل تشغيل للتطبيق.
      final savedFont = prefs.getString('ashura_font_family') ?? 'Amiri';
      selectedFont = savedFont == 'AmiriQuran' ? 'AmiriQuran' : 'Amiri';
      final savedColor = prefs.getString('ashura_theme_color') ?? 'أخضر';
      selectedColor = appColors.containsKey(savedColor) ? savedColor : 'أخضر';
      loaded = true;
    });

    // إعادة جدولة جميع المنبّهات المحفوظة عند فتح التطبيق.
    try {
      await rescheduleSavedReminders();
    } catch (error) {
      debugPrint('تعذر إعادة جدولة المنبّهات: $error');
    }
  }

  Future<void> toggleTheme() async {
    setState(() => isDarkMode = !isDarkMode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('ashura_dark', isDarkMode);
  }

  Future<void> changeFontSize(double delta) async {
    setState(() => fontSize = (fontSize + delta).clamp(16.0, 32.0).toDouble());
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
        appBarTheme: AppBarTheme(
          backgroundColor: primaryColor,
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

class WelcomeScreen extends StatefulWidget {
  final VoidCallback onEnter;
  const WelcomeScreen({super.key, required this.onEnter});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  bool pressed = false;

  Future<void> enter() async {
    if (pressed) return;
    setState(() => pressed = true);
    unawaited(tapFeedback());
    await Future.delayed(const Duration(milliseconds: 220));
    if (mounted) widget.onEnter();
  }

  static const String story = '''للشاعر أبو الحسن جمال الدين الخليعي الحلّي، وقصته انه ولد من أبوين ناصبيين، وكانت أُمّه نذرت أنّها إن رُزقت ولداً ترسله لقطع الطريق على زوّار الإمام الحسين(عليه السلام) وقتلهم!! فلمّا ولدت به وبلغ أشدّه، أرسلته إلى جهة نذرها، فلمّا بلغ إلى نواحي المسيّب بمقربة من كربلاء المشرّفة، طفق ينتظر قدوم الزائرين فاستولى عليه النوم، واجتازت عليه القوافل، فرأى فيما يراه النائم، أنّ القيامة قد قامت وقد أُمر به إلى النار لكنّها لم تمسّه لما عليه من ذلك غبار الزوّار، فانتبه مرتدعاً عن نيّته السيّئة، واعتنق ولاء العترة الطاهرة، وزار كربلاء، وأقام فيها فترة من الزمن، وانشدفيها شعرا.

هنيئا لخدام الامام الحسين عليه السلام وزواره هذه المنزلة الرفيعة فاذا كانت اجساد من وقع عليه الغبار لا تمسه النار فكيف بمن يخدم ويبذل ومن يقطع المسافات الى كربلاء

اللهم اجعلنا من زوار الحسين عليه السلام''';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/welcome_background.png',
            fit: BoxFit.cover,
            alignment: Alignment.center,
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'زيارة عاشوراء',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFFC5A45E),
                            fontSize: 34,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'AmiriQuran',
                            shadows: [Shadow(color: Colors.black87, blurRadius: 5)],
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'اللَّهُمَّ صَلِّ عَلَىٰ مُحَمَّدٍ وَآلِ مُحَمَّدٍ وَعَجِّلْ فَرَجَهُمْ',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 30,
                            height: 1.45,
                            fontFamily: 'AmiriQuran',
                            shadows: [Shadow(color: Colors.black87, blurRadius: 5)],
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'إذا شئتَ النَّجاةَ فَزُرْ حُسيناً ●●● لِكَي تَلْقَى الإلهَ قَريرَ عَينِ\n'
                          'فإنَّ النارَ لَيْسَ تَمَسُّ جِسماً ●●● عَليهِ غُبارُ زوّارِ الحُسيــنِ',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 30,
                            height: 1.65,
                            fontFamily: 'AmiriQuran',
                            shadows: [Shadow(color: Colors.black87, blurRadius: 5)],
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          story,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            height: 1.65,
                            fontFamily: 'Amiri',
                            shadows: [Shadow(color: Colors.black87, blurRadius: 5)],
                          ),
                        ),
                        const SizedBox(height: 18),
                        GestureDetector(
                          onTap: enter,
                          child: AnimatedScale(
                            scale: pressed ? 1.08 : 1.0,
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOut,
                            child: Container(
                              width: 142,
                              height: 142,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withValues(alpha: 0.12),
                                border: Border.all(color: const Color(0xFFC5A45E), width: 2),
                              ),
                              padding: const EdgeInsets.all(14),
                              child: const Text(
                                'اضغط هنا\nللدخول',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Color(0xFFC5A45E),
                                  fontSize: 19,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Amiri',
                                  shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
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
    final appPrimary = Theme.of(context).colorScheme.primary;
    final fixedVisitTheme = Theme.of(context).copyWith(
      colorScheme: Theme.of(context).colorScheme.copyWith(primary: green),
    );
    final pages = [
      Theme(data: fixedVisitTheme, child: ZiyaratPage(fontSize: widget.fontSize)),
      Theme(data: fixedVisitTheme, child: FavorsPage(fontSize: widget.fontSize)),
      Theme(data: fixedVisitTheme, child: AbbasVisitPage(fontSize: widget.fontSize)),
      Theme(data: fixedVisitTheme, child: ListeningPage(fontSize: widget.fontSize)),
      Theme(data: fixedVisitTheme, child: TasbeehPage(fontSize: widget.fontSize, selectedColor: widget.selectedColor)),
    ];
    const labels = ['زِيَارَةُ عَاشُورَاءَ', 'فَضْــلُ الزِّيَــارَةِ', 'زِيَارَةُ العَبَّاسِ', 'اسْتِمَــاعُ الزِّيَــارَةِ', 'المِسْبَحَةُ الإِلِكْتُرُونِيَّةُ'];
    return Scaffold(
      appBar: AppBar(
        backgroundColor: appPrimary,
        title: const Text('زيارة عاشوراء',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            onPressed: () {
              unawaited(tapFeedback());
              Navigator.push(
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
            );
            },
            icon: const Icon(Icons.settings),
            tooltip: 'الإعدادات',
          ),
        ],
      ),
      body: IndexedStack(index: selectedIndex, children: pages),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(5, 8, 5, 8),
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF1F1F1F)
              : Colors.white,
          child: Row(
            children: List.generate(labels.length, (index) {
              final selected = selectedIndex == index;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: GestureDetector(
                    onTap: () { unawaited(tapFeedback()); setState(() => selectedIndex = index); },
                    child: AnimatedScale(
                      scale: selected ? 1.045 : 1.0,
                      duration: const Duration(milliseconds: 190),
                      curve: Curves.easeOutBack,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 190),
                        curve: Curves.easeOut,
                        height: 66,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
                        decoration: BoxDecoration(
                          color: appPrimary.withValues(alpha: selected ? 1.0 : 0.78),
                          borderRadius: BorderRadius.circular(13),
                          border: Border.all(
                            color: selected ? gold : appPrimary.withValues(alpha: 0.35),
                            width: selected ? 1.5 : 0.7,
                          ),
                        ),
                        child: Text(
                          labels[index],
                          textAlign: TextAlign.center,
                          softWrap: true,
                          maxLines: 2,
                          overflow: TextOverflow.clip,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
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
            onPressed: () { unawaited(tapFeedback()); Navigator.pop(dialogContext, false); },
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () { unawaited(tapFeedback()); Navigator.pop(dialogContext, true); },
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
                onPressed: isLoading ? null : () { unawaited(tapFeedback()); markVisitCompleted(); },
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('أتممت قراءة الزيارة كاملة'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: isLoading || completedVisits == 0 ? null : () { unawaited(tapFeedback()); resetCount(); },
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
                  onPressed: count < 100 ? () { unawaited(tapFeedback()); increment(); } : null,
                  icon: const Icon(Icons.touch_app),
                  label: Text('العدد: $count'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary, foregroundColor: Colors.white),
                ),
                IconButton(onPressed: () { unawaited(tapFeedback()); reset(); }, icon: const Icon(Icons.refresh),
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
                      unawaited(tapFeedback());
                      try {
                        await (audioHandler as AshuraAudioHandler).playAsset(
                          'assets/shibr_maalla_abbas.mp3',
                          'الشيخ شـبـر مـعـلـه',
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
                      backgroundColor: Theme.of(context).colorScheme.primary,
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

class ListeningPage extends StatefulWidget {
  final double fontSize;
  const ListeningPage({super.key, required this.fontSize});

  static const List<Map<String, String>> readers = [
    {'name': 'الشيخ شـبـر مـعـلـه', 'file': 'shibr_maalla.mp3'},
    {'name': 'الشيخ باقـر المقـدسي', 'file': 'baqir_almaqdisi.mp3'},
    {'name': 'الرادود باسـم الكربلائي', 'file': 'basim_alkarbalaei.mp3'},
    {'name': 'الرادود أحمـد الفتـلاوي', 'file': 'ahmed_alftlawi.mp3'},
    {'name': 'الرادود محمـد باقـر الخاقاني', 'file': 'mohammed_baqir_alkhaqani.mp3'},
    {'name': 'الرادود أبـا ذر الحلـواجي', 'file': 'aba_thar_alhelwachi.mp3'},
    {'name': 'الحاج علـي الكعبـي', 'file': 'ali_alkabi.mp3'},
    {'name': 'الحاج مهـدي سماواتـي', 'file': 'mahdi_samawati.mp3'},
    {'name': 'الرادود عمـار الكناني', 'file': 'ammar_alkinani.mp3'},
    {'name': 'الرادود أسامـة الكربلائـي', 'file': 'osama_al_karbalaei.mp3'},
    {'name': 'الشيخ ميثـم كاظـم', 'file': 'maytham_kadhim.mp3'},
    {'name': 'الشيخ ميثـم التمـار', 'file': 'maytham_al_tammar.mp3'},
    {'name': 'الحاج عبـد الحـي قمبـر', 'file': 'abdulhay_qambar.mp3'},
    {'name': 'الحاج علـي فانـي', 'file': 'ali_fani.mp3'},
    {'name': 'القارئ علـي أبو ريحـان', 'file': 'ali_abu_rayhan.mp3'},
  ];

  @override
  State<ListeningPage> createState() => _ListeningPageState();
}

class _ListeningPageState extends State<ListeningPage> {
  String? selectedAsset;

  AshuraAudioHandler get handler => audioHandler as AshuraAudioHandler;

  Future<void> playReader(Map<String, String> reader) async {
    final asset = 'assets/${reader['file']!}';
    try {
      await handler.playAsset(asset, reader['name']!);
      if (mounted) setState(() => selectedAsset = asset);
    } catch (error) {
      debugPrint('Audio error: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر تشغيل ${reader['name']}؛ تحقق من وجود الملف في assets.')),
        );
      }
    }
  }

  String formatDuration(Duration value) {
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hours = value.inHours;
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: isDark ? const Color(0xFF101810) : const Color(0xFFF5F0E5)),
        Image.asset(
          'assets/listening_background.jpg',
          fit: BoxFit.cover,
          alignment: Alignment.center,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
        SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: Text(
                  'استماع زيارة عاشوراء',
                  style: TextStyle(
                    color: isDark ? Colors.white : const Color(0xFF18251C),
                    fontSize: widget.fontSize + 3,
                    fontWeight: FontWeight.bold,
                    shadows: const [Shadow(color: Colors.black54, blurRadius: 5)],
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                  itemCount: ListeningPage.readers.length,
                  itemBuilder: (context, index) {
                    final reader = ListeningPage.readers[index];
                    final asset = 'assets/${reader['file']!}';
                    return InkWell(
                      onTap: () { unawaited(tapFeedback()); playReader(reader); },
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        child: Text(
                          reader['name']!,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            color: selectedAsset == asset ? gold : Colors.white,
                            fontSize: widget.fontSize,
                             fontFamily: 'Amiri',
                             fontWeight: FontWeight.bold,
                             shadows: const [
                               Shadow(color: Colors.black, blurRadius: 6, offset: Offset(1, 1)),
                               Shadow(color: Colors.black87, blurRadius: 2),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                  },
                ),
              ),
              _AudioPlayerControls(
                handler: handler,
                formatDuration: formatDuration,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AudioPlayerControls extends StatelessWidget {
  final AshuraAudioHandler handler;
  final String Function(Duration) formatDuration;
  const _AudioPlayerControls({
    required this.handler,
    required this.formatDuration,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration?>(
      stream: handler.durationStream,
      builder: (context, durationSnapshot) {
        final duration = durationSnapshot.data ?? Duration.zero;
        return StreamBuilder<Duration>(
          stream: handler.positionStream,
          initialData: Duration.zero,
          builder: (context, positionSnapshot) {
            final rawPosition = positionSnapshot.data ?? Duration.zero;
            final position = rawPosition > duration ? duration : rawPosition;
            final maxMs = duration.inMilliseconds > 0 ? duration.inMilliseconds : 1;
            return Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  StreamBuilder<MediaItem?>(
                    stream: handler.mediaItem,
                    builder: (context, snapshot) => Text(
                      snapshot.data?.title ?? 'اختر أحد القرّاء',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: gold, fontWeight: FontWeight.bold, fontSize: 16,
                        shadows: [Shadow(color: Colors.black87, blurRadius: 5)],
                      ),
                    ),
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: gold,
                      inactiveTrackColor: Colors.white54,
                      thumbColor: gold,
                      overlayColor: gold.withValues(alpha: 0.16),
                      trackHeight: 2.5,
                    ),
                    child: Slider(
                      min: 0,
                      max: maxMs.toDouble(),
                      value: position.inMilliseconds.clamp(0, maxMs).toDouble(),
                      onChanged: duration == Duration.zero
                          ? null
                          : (value) => handler.seek(Duration(milliseconds: value.round())),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(formatDuration(position), style: const TextStyle(color: Colors.white, shadows: [Shadow(color: Colors.black87, blurRadius: 4)])),
                      Text(formatDuration(duration), style: const TextStyle(color: Colors.white, shadows: [Shadow(color: Colors.black87, blurRadius: 4)])),
                    ],
                  ),
                  StreamBuilder<bool>(
                    stream: handler.playingStream,
                    initialData: handler.isPlaying,
                    builder: (context, snapshot) {
                      final playing = snapshot.data ?? false;
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            tooltip: 'تأخير 10 ثوانٍ',
                            onPressed: duration == Duration.zero ? null : () { unawaited(tapFeedback()); handler.seekRelative(const Duration(seconds: -10)); },
                            icon: const Icon(Icons.replay_10, color: Colors.white, size: 32),
                          ),
                          IconButton(
                            tooltip: playing ? 'إيقاف مؤقت' : 'تشغيل',
                            onPressed: duration == Duration.zero ? null : () { unawaited(tapFeedback()); playing ? handler.pause() : handler.play(); },
                            icon: Icon(playing ? Icons.pause_circle_filled : Icons.play_circle_fill, color: gold, size: 48),
                          ),
                          IconButton(
                            tooltip: 'تقديم 10 ثوانٍ',
                            onPressed: duration == Duration.zero ? null : () { unawaited(tapFeedback()); handler.seekRelative(const Duration(seconds: 10)); },
                            icon: const Icon(Icons.forward_10, color: Colors.white, size: 32),
                          ),
                          IconButton(
                            tooltip: 'إيقاف التسجيل',
                            onPressed: duration == Duration.zero ? null : () async { await handler.stop(); },
                            icon: const Icon(Icons.stop_circle_outlined, color: Colors.white, size: 32),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}


class TasbeehPage extends StatefulWidget {
  final double fontSize;
  final String selectedColor;
  const TasbeehPage({super.key, required this.fontSize, required this.selectedColor});
  @override
  State<TasbeehPage> createState() => _TasbeehPageState();
}

class _TasbeehPageState extends State<TasbeehPage> {
  int count = 0;
  int target = 500;
  int dailyCount = 0;
  Color backgroundColor = const Color(0xFF121212);
  bool loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final today = '\${now.year}-\${now.month}-\${now.day}';
    if (prefs.getString('tasbeeh_daily_date') != today) {
      await prefs.setString('tasbeeh_daily_date', today);
      await prefs.setInt('tasbeeh_daily_count', 0);
    }
    if (!mounted) return;
    setState(() {
      count = prefs.getInt('tasbeeh_salawat_count') ?? 0;
      target = prefs.getInt('tasbeeh_target') ?? 500;
      dailyCount = prefs.getInt('tasbeeh_daily_count') ?? 0;
      backgroundColor = Color(prefs.getInt('tasbeeh_background_color') ?? 0xFF121212);
      loaded = true;
    });
  }

  Future<void> _increment() async {
    if (!loaded) return;
    setState(() { count++; dailyCount++; });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('tasbeeh_salawat_count', count);
    await prefs.setInt('tasbeeh_daily_count', dailyCount);
    await tapFeedback();
    if (count == target && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أحسنت، أتممت العدد المحدد من الصلاة على محمد وآل محمد')),
      );
    }
  }

  Future<void> _reset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إعادة العداد'),
        content: const Text('هل تريد تصفير العدد الكلي؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('تصفير')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => count = 0);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('tasbeeh_salawat_count', 0);
  }

  Future<void> _setTarget(int value) async {
    if (value < 1) return;
    setState(() => target = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('tasbeeh_target', value);
  }

  Future<void> _customTarget() async {
    final controller = TextEditingController(text: target.toString());
    final value = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تحديد العدد'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'العدد المطلوب'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () {
              final parsed = int.tryParse(controller.text.trim());
              if (parsed != null && parsed > 0) Navigator.pop(context, parsed);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    if (value != null) await _setTarget(value);
  }

  Future<void> _chooseBackground() async {
    const choices = <Color>[
      Color(0xFF121212), Color(0xFF1B4332), Color(0xFF172554),
      Color(0xFF3B1024), Color(0xFF173D3D), Color(0xFF30234A),
    ];
    final chosen = await showDialog<Color>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('خلفية المسبحة'),
        content: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: choices.map((color) => InkWell(
            onTap: () => Navigator.pop(context, color),
            child: CircleAvatar(
              backgroundColor: color,
              radius: 22,
              child: const Icon(Icons.check, color: Colors.white),
            ),
          )).toList(),
        ),
      ),
    );
    if (chosen == null) return;
    setState(() => backgroundColor = chosen);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('tasbeeh_background_color', chosen.value);
  }

  @override
  Widget build(BuildContext context) {
    final accent = appColors[widget.selectedColor] ?? green;
    return Column(
      children: [
        Container(
          width: double.infinity,
          color: backgroundColor,
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
          child: Column(
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('بِسْمِ اللهِ الرَّحْمٰنِ الرَّحِيمِ',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: gold, fontSize: 19, fontWeight: FontWeight.bold, fontFamily: 'AmiriQuran')),
                  ),
                  IconButton(onPressed: _chooseBackground, icon: const Icon(Icons.palette_outlined, color: gold), tooltip: 'تغيير الخلفية'),
                ],
              ),
              GestureDetector(
                onTap: _increment,
                child: Container(
                  width: 148,
                  height: 148,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [accent.withValues(alpha: 0.85), backgroundColor]),
                    border: Border.all(color: gold, width: 4),
                    boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 12, spreadRadius: 1)],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('$count', style: const TextStyle(color: gold, fontSize: 34, fontWeight: FontWeight.bold)),
                      const Text('اضغط للتسبيح', style: TextStyle(color: Colors.white, fontSize: 12)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text('الهدف: $target  •  المتبقي: \${(target - count).clamp(0, target)}',
                style: const TextStyle(color: Colors.white, fontSize: 15)),
              Text('ورد اليوم: $dailyCount', style: const TextStyle(color: gold, fontWeight: FontWeight.bold)),
              const SizedBox(height: 7),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 7,
                children: [
                  OutlinedButton(onPressed: () => _setTarget(500), child: const Text('تحدي 500')),
                  OutlinedButton(onPressed: () => _setTarget(1000000), child: const Text('تحدي المليون')),
                  OutlinedButton(onPressed: _customTarget, child: const Text('تحديد العدد')),
                  IconButton(onPressed: _reset, icon: const Icon(Icons.refresh, color: gold), tooltip: 'تصفير العداد'),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                '﴿إِنَّ اللَّهَ وَمَلَائِكَتَهُ يُصَلُّونَ عَلَى النَّبِيِّ ۚ يَا أَيُّهَا الَّذِينَ آمَنُوا صَلُّوا عَلَيْهِ وَسَلِّمُوا تَسْلِيمًا﴾',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: widget.fontSize, height: 2, fontFamily: 'AmiriQuran'),
              ),
              const SizedBox(height: 5),
              const Text('سورة الأحزاب، الآية 56', textAlign: TextAlign.center, style: TextStyle(color: gold)),
              const SizedBox(height: 18),
              const Divider(color: gold),
              const Text('فضل الصلاة على محمد وآل محمد',
                textAlign: TextAlign.center,
                style: TextStyle(color: gold, fontSize: 19, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                'قال رسول الله (صلى الله عليه وآله): «مَنْ صَلَّى عَلَيَّ صَلَاةً صَلَّى اللهُ عَلَيْهِ بِهَا عَشْرًا».',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: widget.fontSize - 1, height: 1.9, fontFamily: 'Amiri'),
              ),
              const SizedBox(height: 6),
              const Text('المصدر: صحيح مسلم، كتاب الصلاة، حديث الصلاة على النبي (رقم 408 في ترقيم مشهور).',
                textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, height: 1.6)),
              const SizedBox(height: 20),
            ],
          ),
        ),
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
  late String localFont;
  late String localColor;

  @override
  void initState() {
    super.initState();
    localFont = widget.selectedFont;
    localColor = widget.selectedColor;
  }

  @override
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedFont != widget.selectedFont) localFont = widget.selectedFont;
    if (oldWidget.selectedColor != widget.selectedColor) localColor = widget.selectedColor;
  }

  @override
  Widget build(BuildContext context) {
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
                    title: Text('تغيير لون التطبيق'),
                  ),
                  DropdownButtonFormField<String>(
                    value: localColor,
                    isExpanded: true,
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                    items: appColors.keys.map((name) => DropdownMenuItem<String>(
                      value: name, child: Text(name),
                    )).toList(),
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
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem<String>(value: 'Amiri', child: Text('Amiri - خط النسخ')),
                      DropdownMenuItem<String>(value: 'AmiriQuran', child: Text('Amiri Quran - الخط القرآني')),
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
                  IconButton(onPressed: () { unawaited(tapFeedback()); widget.onChangeFontSize(-2); }, icon: const Icon(Icons.remove)),
                  IconButton(onPressed: () { unawaited(tapFeedback()); widget.onChangeFontSize(2); }, icon: const Icon(Icons.add)),
                ],
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.alarm, color: gold),
              title: const Text('منبه الزيارة'),
              subtitle: const Text('إعداد ثلاثة منبّهات يومية لزيارة عاشوراء'),
              trailing: const Icon(Icons.chevron_left),
              onTap: () { unawaited(tapFeedback()); Navigator.push(context, MaterialPageRoute(builder: (_) => const ReminderManagerPage())); },
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.info_outline, color: gold),
              title: const Text('حول التطبيق'),
              subtitle: const Text('معلومات التطبيق وحقوق التصميم'),
              trailing: const Icon(Icons.chevron_left),
              onTap: () { unawaited(tapFeedback()); Navigator.push(context, MaterialPageRoute(builder: (_) => const AboutAppPage())); },
            ),
          ),
        ],
      ),
    );
  }
}

class ReminderManagerPage extends StatefulWidget {
  const ReminderManagerPage({super.key});
  @override
  State<ReminderManagerPage> createState() => _ReminderManagerPageState();
}

class _ReminderManagerPageState extends State<ReminderManagerPage> {
  List<AshuraReminder> reminders = [];
  bool loading = true;
  bool salawatEnabled = false;
  int salawatHour = 9;
  int salawatMinute = 0;

  static const List<String> dayNames = ['الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final saved = await loadSavedReminders();
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      reminders = saved;
      salawatEnabled = prefs.getBool('salawat_reminder_enabled') ?? false;
      salawatHour = prefs.getInt('salawat_reminder_hour') ?? 9;
      salawatMinute = prefs.getInt('salawat_reminder_minute') ?? 0;
      loading = false;
    });
  }

  Future<void> updateSalawatReminder({bool? enabled, int? hour, int? minute}) async {
    final nextEnabled = enabled ?? salawatEnabled;
    if (nextEnabled && !await ensurePermissions()) return;
    final nextHour = hour ?? salawatHour;
    final nextMinute = minute ?? salawatMinute;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('salawat_reminder_enabled', nextEnabled);
    await prefs.setInt('salawat_reminder_hour', nextHour);
    await prefs.setInt('salawat_reminder_minute', nextMinute);
    await scheduleSalawatReminder(
      enabled: nextEnabled,
      hour: nextHour,
      minute: nextMinute,
    );
    if (!mounted) return;
    setState(() {
      salawatEnabled = nextEnabled;
      salawatHour = nextHour;
      salawatMinute = nextMinute;
    });
  }

  Future<void> chooseSalawatTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: salawatHour, minute: salawatMinute),
    );
    if (picked != null) {
      await updateSalawatReminder(hour: picked.hour, minute: picked.minute);
    }
  }

  Future<bool> ensurePermissions() async {
    final notificationGranted = await askNotificationPermission();
    if (!notificationGranted) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يرجى السماح بإشعارات التطبيق من إعدادات الهاتف.')));
      return false;
    }
    final exactGranted = await askExactAlarmPermission();
    if (!exactGranted) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يرجى السماح للتطبيق بالمنبّهات الدقيقة من إعدادات الهاتف.')));
      return false;
    }
    return true;
  }

  Future<void> persist() async {
    await saveReminders(reminders);
    for (final reminder in reminders) {
      await scheduleReminder(reminder);
    }
  }

  Future<void> addReminder() async {
    if (reminders.length >= 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يمكنك إضافة ثلاثة منبّهات فقط.')),
      );
      return;
    }
    final nextId = (reminders.isEmpty ? 2000 : reminders.map((r) => r.id).reduce((a, b) => a > b ? a : b)) + 1;
    final draft = AshuraReminder(id: nextId, hour: 20, minute: 0, weekdays: const [1,2,3,4,5,6,7], enabled: true);
    final result = await showDialog<AshuraReminder>(context: context, builder: (_) => ReminderEditorDialog(reminder: draft, dayNames: dayNames));
    if (result == null) return;
    if (result.enabled && !await ensurePermissions()) return;
    setState(() => reminders = [...reminders, result]);
    await persist();
  }

  Future<void> editReminder(AshuraReminder old) async {
    final result = await showDialog<AshuraReminder>(context: context, builder: (_) => ReminderEditorDialog(reminder: old, dayNames: dayNames));
    if (result == null) return;
    if (result.enabled && !await ensurePermissions()) return;
    setState(() => reminders = reminders.map((r) => r.id == old.id ? result : r).toList());
    await persist();
  }

  Future<void> toggleReminder(AshuraReminder reminder, bool enabled) async {
    if (enabled && !await ensurePermissions()) return;
    setState(() => reminders = reminders.map((r) => r.id == reminder.id ? r.copyWith(enabled: enabled) : r).toList());
    await persist();
  }

  Future<void> deleteReminder(AshuraReminder reminder) async {
    await cancelReminderNotifications(reminder);
    setState(() => reminders.removeWhere((r) => r.id == reminder.id));
    await saveReminders(reminders);
  }

  String daySummary(List<int> days) {
    if (days.length == 7) return 'كل أيام الأسبوع';
    if (days.isEmpty) return 'لم تُحدد أيام';
    return days.map((d) => dayNames[d - 1]).join('، ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إدارة المنبّهات')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: reminders.length >= 3 ? null : () { unawaited(tapFeedback()); addReminder(); },
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_alarm),
        label: const Text('إضافة منبّه'),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
              children: [
                Card(
                  child: Column(
                    children: [
                      SwitchListTile(
                        secondary: const Icon(Icons.volunteer_activism, color: gold),
                        title: const Text('منبه الصلاة على محمد وآل محمد'),
                        subtitle: const Text('هل صليت على محمد وآل محمد هذا اليوم؟'),
                        value: salawatEnabled,
                        onChanged: (value) => updateSalawatReminder(enabled: value),
                      ),
                      ListTile(
                        leading: const Icon(Icons.access_time, color: gold),
                        title: const Text('وقت التذكير المستقل'),
                        subtitle: Text(TimeOfDay(hour: salawatHour, minute: salawatMinute).format(context)),
                        trailing: const Icon(Icons.edit, color: gold),
                        onTap: chooseSalawatTime,
                      ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('منبّهات زيارة عاشوراء (حتى ثلاثة أوقات مستقلة)',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: gold, fontWeight: FontWeight.bold)),
                ),
                if (reminders.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('لا توجد منبّهات للزيارة حالياً. أضف منبّهاً وحدد وقته وأيام تكراره.',
                      textAlign: TextAlign.center),
                  ),
                ...reminders.map((reminder) {
                  final time = TimeOfDay(hour: reminder.hour, minute: reminder.minute).format(context);
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.alarm, color: gold, size: 30),
                      title: Text(time, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
                      subtitle: Text(daySummary(reminder.weekdays)),
                      onTap: () { unawaited(tapFeedback()); editReminder(reminder); },
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Switch(value: reminder.enabled, onChanged: (value) => toggleReminder(reminder, value)),
                          PopupMenuButton<String>(
                            onSelected: (value) {
                              if (value == 'edit') editReminder(reminder);
                              if (value == 'delete') deleteReminder(reminder);
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'edit', child: Text('تعديل')),
                              PopupMenuItem(value: 'delete', child: Text('حذف')),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
    );
  }
}

class ReminderEditorDialog extends StatefulWidget {
  final AshuraReminder reminder;
  final List<String> dayNames;
  const ReminderEditorDialog({super.key, required this.reminder, required this.dayNames});
  @override
  State<ReminderEditorDialog> createState() => _ReminderEditorDialogState();
}

class _ReminderEditorDialogState extends State<ReminderEditorDialog> {
  late int hour;
  late int minute;
  late List<int> days;

  @override
  void initState() {
    super.initState();
    hour = widget.reminder.hour;
    minute = widget.reminder.minute;
    days = [...widget.reminder.weekdays];
  }

  @override
  Widget build(BuildContext context) {
    final time = TimeOfDay(hour: hour, minute: minute);
    return AlertDialog(
      title: const Text('إعداد المنبّه'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.access_time, color: gold),
              title: const Text('وقت التنبيه'),
              subtitle: Text(time.format(context)),
              onTap: () async {
                final picked = await showTimePicker(context: context, initialTime: time);
                if (picked != null) setState(() { hour = picked.hour; minute = picked.minute; });
              },
            ),
            const Divider(),
            const Align(alignment: Alignment.centerRight, child: Text('أيام التكرار', style: TextStyle(fontWeight: FontWeight.bold))),
            ...List.generate(widget.dayNames.length, (index) => CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(widget.dayNames[index]),
              value: days.contains(index + 1),
              onChanged: (checked) => setState(() {
                if (checked == true) { if (!days.contains(index + 1)) days.add(index + 1); }
                else { days.remove(index + 1); }
                days.sort();
              }),
            )),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        ElevatedButton(
          onPressed: days.isEmpty ? null : () => Navigator.pop(context, widget.reminder.copyWith(hour: hour, minute: minute, weekdays: days)),
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}

class AboutAppPage extends StatelessWidget {
  const AboutAppPage({super.key});
  static const String aboutText = '''تطبيق «زيارة عاشوراء» وهو تطبيق ديني روحاني متكامل يُعنى بتيسير قراءة واستماع «زيارة عاشوراء» المباركة ليكون رفيقاً إيمانياً يومياً للمؤمنين أينما كانوا.

اللهم اغفر لي ولوالديّ وارحمهما كما ربّياني صغيراً، واجزهما عني خير ما جزيت والداً عن ولده. اللهم اغفر للمؤمنين والمؤمنات، والمسلمين والمسلمات، الأحياء منهم والأموات، واجمعنا وإياهم في جنات النعيم بجوار محمد وآله الطاهرين.

تصميم كامل الكميتي 11/11/2026
جميع الحقوق محفوظة''';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('حول التطبيق')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const SizedBox(height: 18),
          const Icon(Icons.mosque, color: gold, size: 58),
          const SizedBox(height: 18),
          const SelectableText(
            aboutText,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, height: 2.0),
          ),
        ],
      ),
    );
  }
}
