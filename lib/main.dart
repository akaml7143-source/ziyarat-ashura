import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:vibration/vibration.dart';
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
  'ذهبي رملي': Color(0xFFC6A15B),
  'بنفسجي': Color(0xFF7B2CBF),
  'سلفر': Color(0xFF9AA0A6),
  'تركوازي': Color(0xFF009FA3),
  'برغندي': Color(0xFF5A1020),
  'هافان': Color(0xFF8D5A3B),
};

final FlutterLocalNotificationsPlugin notifications = FlutterLocalNotificationsPlugin();
bool exactAlarmsAllowed = false;
const String reminderChannelKey = 'ashura_reminders_local_v1';
late AudioHandler audioHandler;

Future<void> tapFeedback() async {
  try { await HapticFeedback.selectionClick(); } catch (_) {}
  try { await HapticFeedback.mediumImpact(); } catch (_) {}
  try { await Vibration.vibrate(duration: 65, amplitude: 255); } catch (_) {}
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
  const settings = InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher'), iOS: DarwinInitializationSettings());
  await notifications.initialize(settings);
  exactAlarmsAllowed = await canScheduleExactAlarms();
}
const NotificationDetails reminderNotificationDetails = NotificationDetails(
  android: AndroidNotificationDetails(reminderChannelKey, 'منبّهات زيارة عاشوراء',
    channelDescription: 'تذكيرات الزيارة والصلاة على محمد وآل محمد',
    importance: Importance.max, priority: Priority.high, playSound: true,
    enableVibration: true, category: AndroidNotificationCategory.reminder),
  iOS: DarwinNotificationDetails(),
);
Future<bool> askNotificationPermission() async {
  final android = notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  return await android?.requestNotificationsPermission() ?? true;
}
Future<bool> canScheduleExactAlarms() async {
  final android = notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  return await android?.canScheduleExactNotifications() ?? true;
}
Future<bool> askExactAlarmPermission() async {
  final android = notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  return await android?.requestExactAlarmsPermission() ?? false;
}
Future<bool> ensureNotificationPermissions() async {
  if (!await askNotificationPermission()) return false;
  exactAlarmsAllowed = await canScheduleExactAlarms();
  if (!exactAlarmsAllowed) exactAlarmsAllowed = await askExactAlarmPermission();
  return true;
}
Future<void> showReminderTestNotification() async {
  await notifications.show(90999, 'زيارة عاشوراء',
    'هل زرت الإمام الحسين عليه السلام هذا اليوم؟', reminderNotificationDetails);
}
class AshuraReminder {
  final int id; final int hour; final int minute; final List<int> weekdays; final bool enabled;
  const AshuraReminder({required this.id, required this.hour, required this.minute, required this.weekdays, required this.enabled});
  Map<String, dynamic> toJson() => {'id': id, 'hour': hour, 'minute': minute, 'weekdays': weekdays, 'enabled': enabled};
  factory AshuraReminder.fromJson(Map<String, dynamic> json) => AshuraReminder(
    id: (json['id'] as num).toInt(), hour: (json['hour'] as num).toInt(), minute: (json['minute'] as num).toInt(),
    weekdays: (json['weekdays'] as List).map((v) => (v as num).toInt()).where((d) => d >= 1 && d <= 7).toList(),
    enabled: json['enabled'] == true);
  AshuraReminder copyWith({int? hour, int? minute, List<int>? weekdays, bool? enabled}) => AshuraReminder(
    id: id, hour: hour ?? this.hour, minute: minute ?? this.minute, weekdays: weekdays ?? this.weekdays, enabled: enabled ?? this.enabled);
}
const String reminderMessage = 'عندما يتّسع يومك لزيارة عاشوراء رغم ضيق الوقت، فهذا التوفيق بعينه';
int _notificationId(int reminderId, int weekday) => reminderId * 10 + weekday;
AndroidScheduleMode get _scheduleMode => exactAlarmsAllowed ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle;
tz.TZDateTime _nextWeekdayTime(int weekday, int hour, int minute) {
  final now = tz.TZDateTime.now(tz.local);
  var value = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
  while (value.weekday != weekday || !value.isAfter(now)) { value = value.add(const Duration(days: 1)); }
  return value;
}
Future<void> cancelReminderNotifications(AshuraReminder reminder) async {
  for (var day = 1; day <= 7; day++) { await notifications.cancel(_notificationId(reminder.id, day)); }
}
Future<void> scheduleReminder(AshuraReminder reminder) async {
  await cancelReminderNotifications(reminder);
  if (!reminder.enabled || reminder.weekdays.isEmpty) return;
  for (final weekday in reminder.weekdays) {
    await notifications.zonedSchedule(_notificationId(reminder.id, weekday), 'زيارة عاشوراء',
      'هل زرت الإمام الحسين عليه السلام هذا اليوم؟', _nextWeekdayTime(weekday, reminder.hour, reminder.minute),
      reminderNotificationDetails, androidScheduleMode: _scheduleMode,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime);
  }
}
Future<List<AshuraReminder>> loadSavedReminders() async {
  final prefs = await SharedPreferences.getInstance(); final raw = prefs.getString('ashura_reminders_v2');
  if (raw == null || raw.isEmpty) return [];
  try { return (jsonDecode(raw) as List).map((v) => AshuraReminder.fromJson(Map<String, dynamic>.from(v as Map))).toList(); }
  catch (error) { debugPrint('تعذر قراءة المنبّهات المحفوظة: $error'); return []; }
}
Future<void> saveReminders(List<AshuraReminder> reminders) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('ashura_reminders_v2', jsonEncode(reminders.map((v) => v.toJson()).toList()));
}
Future<void> rescheduleSavedReminders() async {
  for (final reminder in await loadSavedReminders()) {
    try { await scheduleReminder(reminder); } catch (error) { debugPrint('تعذر إعادة جدولة المنبّه ${reminder.id}: $error'); }
  }
}
const int salawatReminderNotificationId = 31001;
Future<void> scheduleSalawatReminder({required bool enabled, required int hour, required int minute}) async {
  await notifications.cancel(salawatReminderNotificationId);
  if (!enabled) return;
  final now = tz.TZDateTime.now(tz.local);
  var next = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
  if (!next.isAfter(now)) next = next.add(const Duration(days: 1));
  await notifications.zonedSchedule(salawatReminderNotificationId, 'تذكير الصلاة على محمد وآل محمد',
    'هل صليت على محمد وآل محمد هذا اليوم؟', next, reminderNotificationDetails,
    androidScheduleMode: _scheduleMode,
    uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    matchDateTimeComponents: DateTimeComponents.time);
}
Future<void> restoreSalawatReminder() async {
  final prefs = await SharedPreferences.getInstance();
  await scheduleSalawatReminder(enabled: prefs.getBool('salawat_reminder_enabled') ?? false,
    hour: prefs.getInt('salawat_reminder_hour') ?? 9, minute: prefs.getInt('salawat_reminder_minute') ?? 0);
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
    // تهيئة المنطقة الزمنية وإعادة جدولة المنبّهات المحفوظة.
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
      fontSize = (prefs.getDouble('ashura_font') ?? 20).clamp(16.0, 36.0).toDouble();
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
    setState(() => fontSize = (fontSize + delta).clamp(16.0, 36.0).toDouble());
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
         iconTheme: const IconThemeData(size: 22),        fontFamily: selectedFont,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: darkBackground,
        cardColor: const Color(0xFF1E1E1E),
        colorScheme: ColorScheme.dark(primary: primaryColor, secondary: gold, surface: const Color(0xFF1E1E1E)),
        splashFactory: InkRipple.splashFactory,
        splashColor: primaryColor.withValues(alpha: 0.30),
        highlightColor: primaryColor.withValues(alpha: 0.16),
        elevatedButtonTheme: ElevatedButtonThemeData(style: ElevatedButton.styleFrom(backgroundColor: primaryColor, foregroundColor: Colors.white)),
        outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(foregroundColor: primaryColor, side: BorderSide(color: primaryColor))),
        switchTheme: SwitchThemeData(thumbColor: WidgetStatePropertyAll(primaryColor)),
        sliderTheme: SliderThemeData(activeTrackColor: primaryColor, thumbColor: primaryColor),
        appBarTheme: AppBarTheme(
          backgroundColor: primaryColor,
          foregroundColor: gold,
          centerTitle: true,
        ),
        bottomNavigationBarTheme:
            const BottomNavigationBarThemeData(backgroundColor: Color(0xFF1F1F1F)),
      ),
      theme: ThemeData(
         iconTheme: const IconThemeData(size: 22),        fontFamily: selectedFont,
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF9F6F0),
        cardColor: Colors.white,
        colorScheme: ColorScheme.light(primary: primaryColor, secondary: gold, surface: Colors.white),
        splashFactory: InkRipple.splashFactory,
        splashColor: primaryColor.withValues(alpha: 0.30),
        highlightColor: primaryColor.withValues(alpha: 0.16),
        elevatedButtonTheme: ElevatedButtonThemeData(style: ElevatedButton.styleFrom(backgroundColor: primaryColor, foregroundColor: Colors.white)),
        outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(foregroundColor: primaryColor, side: BorderSide(color: primaryColor))),
        switchTheme: SwitchThemeData(thumbColor: WidgetStatePropertyAll(primaryColor)),
        sliderTheme: SliderThemeData(activeTrackColor: primaryColor, thumbColor: primaryColor),
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

class _WelcomeScreenState extends State<WelcomeScreen> with SingleTickerProviderStateMixin {
  bool pressed = false;
  late final AnimationController _floatController;
  late final Animation<double> _floatAnimation;

  @override
  void initState() {
    super.initState();
    _floatController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat(reverse: true);
    _floatAnimation = Tween<double>(begin: -6, end: 6).animate(CurvedAnimation(parent: _floatController, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _floatController.dispose();
    super.dispose();
  }

  Future<void> enter() async {
    if (pressed) return;
    setState(() => pressed = true);
    unawaited(tapFeedback());
    await Future.delayed(const Duration(milliseconds: 220));
    if (mounted) widget.onEnter();
  }



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
              builder: (context, constraints) {
                final h = constraints.maxHeight;
                return SizedBox.expand(
                  child: Stack(
                    children: [
                      Positioned(
                        top: h * 0.065,
                        left: 12,
                        right: 12,
                        child: const Text(
                          'زيارة عاشوراء',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFFC5A45E),
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'AmiriQuran',
                            shadows: [Shadow(color: Colors.black87, blurRadius: 5)],
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: h * 0.10,
                        right: 18,
                        left: 18,
                        child: Text.rich(
                          highlightImamHussein(
                            'إذا شئتَ النَّجاةَ فَزُرْ حُسيناً .. لِكَي تَلْقَى الإلهَ قَريرَ عَينِ\n'
                            'فإنَّ النارَ لَيْسَ تَمَسُّ جِسماً .. عَليهِ غُبارُ زوّارِ الحُسين',
                            const TextStyle(
                              color: Colors.white,
                              fontSize: 32,
                              height: 1.3,
                              fontFamily: 'AmiriQuran',
                              shadows: [Shadow(color: Colors.black87, blurRadius: 5)],
                            ),
                          ),
                          textAlign: TextAlign.right,
                        ),
                      ),
                      Positioned(
                        top: h * 0.5 - 62,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: AnimatedBuilder(
                            animation: _floatAnimation,
                            builder: (context, child) => Transform.translate(
                              offset: Offset(0, _floatAnimation.value),
                              child: child,
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: enter,
                                borderRadius: BorderRadius.circular(999),
                                splashFactory: InkRipple.splashFactory,
                                splashColor: const Color(0xFFC5A45E).withValues(alpha: 0.42),
                                highlightColor: const Color(0xFFC5A45E).withValues(alpha: 0.14),
                                child: AnimatedScale(
                                  scale: pressed ? 0.94 : 1.0,
                                  duration: const Duration(milliseconds: 160),
                                  child: Container(
                                    constraints: const BoxConstraints.tightFor(width: 118, height: 118),
                                    padding: const EdgeInsets.all(12),
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF17130D).withValues(alpha: 0.58),
                                      borderRadius: BorderRadius.circular(40),
                                      border: Border.all(color: const Color(0xFFC5A45E), width: 2.5),
                                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 12)],
                                    ),
                                    child: const Text(
                                      'الدخول إلى التطبيق',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w900,
                                        fontFamily: 'Amiri',
                                        shadows: [Shadow(color: Colors.black, blurRadius: 5)],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                    ],
                  ),
                );
              },
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
    final pages = [
      ZiyaratPage(fontSize: widget.fontSize),
      FavorsPage(fontSize: widget.fontSize),
      ListeningPage(fontSize: widget.fontSize),
      AbbasVisitPage(fontSize: widget.fontSize),
      TasbeehPage(fontSize: widget.fontSize, selectedColor: widget.selectedColor),
    ];
    const labels = [
      'زِيَارَةُ عَاشُورَاءَ',
      'فَضْلُ زِيَارَةِ عَاشُورَاءَ',
      'اِسْتِمَاعُ الزِّيَارَةِ',
      'زِيَارَةُ الإِمَامِ العَبَّاسِ (ع)',
      'الحَسَنَاتُ يُذْهِبْنَ السَّيِّئَاتِ',
    ];
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
          color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1F1F1F) : Colors.white,
          child: Row(
            children: List.generate(labels.length, (index) {
              final selected = selectedIndex == index;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    splashFactory: InkRipple.splashFactory,
                    onTap: () { unawaited(tapFeedback()); setState(() => selectedIndex = index); },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 190),
                      height: 98,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
                      decoration: BoxDecoration(
                        color: appPrimary.withValues(alpha: selected ? 1.0 : 0.78),
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(color: selected ? gold : appPrimary.withValues(alpha: 0.35), width: selected ? 1.5 : 0.7),
                      ),
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 1),
                          child: Text(
                            labels[index],
                            textAlign: TextAlign.center,
                            softWrap: true,
                            maxLines: 4,
                            overflow: TextOverflow.clip,
                            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900, height: 1.05),
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

TextSpan highlightImamHussein(String text, TextStyle baseStyle) {
  final expression = RegExp(r'(?:ا[\u064B-\u065F\u0670\u0640]*ل[\u064B-\u065F\u0670\u0640]*)?ح[\u064B-\u065F\u0670\u0640]*س[\u064B-\u065F\u0670\u0640]*ي[\u064B-\u065F\u0670\u0640]*ن[\u064B-\u065F\u0670\u0640]*');
  final spans = <TextSpan>[];
  var cursor = 0;
  for (final match in expression.allMatches(text)) {
    if (match.start > cursor) spans.add(TextSpan(text: text.substring(cursor, match.start)));
    spans.add(TextSpan(text: match.group(0), style: const TextStyle(color: Colors.red)));
    cursor = match.end;
  }
  if (cursor < text.length) spans.add(TextSpan(text: text.substring(cursor)));
  return TextSpan(style: baseStyle, children: spans);
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
            Text.rich(highlightImamHussein(title, const TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: gold))),
            const Divider(),
            SelectableText.rich(highlightImamHussein(content, TextStyle(fontSize: fontSize, height: 1.95))),
          ],
        ),
      ),
    );
  }
}

class ZiyaratPage extends StatelessWidget {
  final double fontSize;
  const ZiyaratPage({super.key, required this.fontSize});

  static const String intentionText =
      'بِسْمِ اللهِ الرَّحْمٰنِ الرَّحِيمِ\n'
      'اللَّهُمَّ صَلِّ عَلَىٰ مُحَمَّدٍ وَآلِ مُحَمَّدٍ\n\n'
      'أَزُورُ سَيِّدِي وَمَوْلَايَ أَبَا عَبْدِ اللهِ الْحُسَيْنَ (عَلَيْهِ السَّلَامُ)، بِالْأَصَالَةِ عَنْ نَفْسِي، وَبِالنِّيَابَةِ عَنْ صَاحِبِ الْعَصْرِ وَالزَّمَانِ، وَعَنْ وَالِدَيَّ وَوَالِدَي وَالِدَيَّ وَوَلَدِي، وَأَخَوَاتِي وَإِخْوَانِي، وَجِيرَانِي وَأَقَارِبِي وَأَعِزَّائِي، وَعَمَّنْ قَلَّدَنِي الدُّعَاءَ وَالزِّيَارَةَ، وَجَمِيعِ الْمُؤْمِنِينَ وَالْمُؤْمِنَاتِ، الْأَحْيَاءِ مِنْهُمْ وَالْأَمْوَاتِ، قُرْبَةً إِلَى اللهِ تَعَالَى.';

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
        SectionCard(title: 'نية الزيارة', content: intentionText,
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
                icon: const Icon(Icons.refresh, size: 22),
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
            SelectableText.rich(highlightImamHussein(widget.phrase,
                TextStyle(fontSize: widget.fontSize, height: 1.9)), textAlign: TextAlign.center),
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
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Text.rich(highlightImamHussein('أحاديث في فضل زيارة الحسين (ع) في يوم عاشوراء', const TextStyle(color: gold, fontSize: 22, fontWeight: FontWeight.bold, height: 1.6)), textAlign: TextAlign.center),
      const SizedBox(height: 14),
      SectionCard(title: 'الحديث: ١ — ترتيب جواهر البحار: ١٠٢٦٨', fontSize: fontSize, highlight: true,
        content: r'''قال الريّان بن شبیب: دخلت على الرضا (عليه السلام) في أوّل يوم من محرّم، فقال (عليه السلام) لي: يا بن شبيب، أ صائم أنت؟ فقلت: لا، فقال: إنّ هذا اليوم هو اليوم الذي دعا فيه زكريّا (عليه السلام) ربّه عزّ وجلّ فقال: ﴿رَبِّ هَبْ لي‏ مِنْ لَدُنْكَ ذُرِّيَّةً طَيِّبَةً إِنَّكَ سَميعُ الدُّعاءِ﴾ فاستجاب الله له، وأمر الملائكة فنادت زكريا (عليه السلام) ﴿وَهُوَ قائِمٌ يُصَلِّي فِي الْمِحْرابِ أَنَّ اللّهََ يُبَشِّرُكَ بِيَحْيى﴾، فمن صام هذا اليوم، ثمّ دعا الله عزّ وجلّ استجاب الله له كما استجاب لزكريّا (عليه السلام).

ثمّ قال (عليه السلام): يا بن شبيب، إنّ المحرّم هو الشهر الذي كان أهل الجاهلية فيما مضى يحرّمون فيه الظلم والقتال لحرمته، فما عرفت هذه الأمّة حرمة شهرها ولا حرمة نبيّها (صلى الله عليه وآله وسلم)، لقد قتلوا في هذا الشهر ذرّيّته، وسبوا نساءه، وانتهبوا ثقله، فلا غفر الله لهم ذلك أبداً.

يا بن شبيب، إن كنت باكياً لشيء فابك للحسين بن عليّ بن أبي طالب (عليه السلام)، فإنّه قُتل مظلوماً، وقُتل معه من أهل بيته ثمانية عشر رجلاً ما لهم في الأرض شبيه، ولقد بكت السموات السبع والأرضون لقتله، ولقد نزل إلى الأرض من الملائكة أربعة آلاف لنصره، فوجدوه قد قُتل، فهم عند قبره شعث غبر إلى أن يقوم القائم، فيكونون من أنصاره، وشعارهم «يا لثارات الحسين (عليه السلام)».

يا بن شبيب، لقد حدّثني أبي عن أبيه، عن جدّه (عليه السلام) أنّه لمّا قُتل جدّي الحسين (عليه السلام) أمطرت السماء دماً وتراباً أحمر.

يا بن شبيب، إن بكيت على الحسين (عليه السلام) حتّى تصير دموعك على خدّيك، غفر الله لك كلّ ذنب أذنبته، صغيراً كان أو كبيراً، قليلاً كان أو كثيراً.

يا بن شبيب، إن سرّك أن تلقى الله عزّ وجلّ ولا ذنب عليك، فزر الحسين (عليه السلام).

يا بن شبيب، إن سرّك أن تسكن الغرف المبنيّة في الجنّة مع النبيّ (صلى الله عليه وآله وسلم)، فالعن قتلة الحسين (عليه السلام).

يا بن شبيب، إن سرّك أن يكون لك من الثواب مثل ما لمن استشهد مع الحسين (عليه السلام)، فقل متى ما ذكرته: يا ليتني كنت معهم فأفوز فوزاً عظيماً.

يا بن شبيب، إن سرّك أن تكون معنا في الدرجات العلى من الجنان، فاحزن لحزننا، وافرح لفرحنا، وعليك بولايتنا، فلو أنّ رجلاً تولّى حجراً لحشره الله معه يوم القيامة.

المصدر الأصلي: عيون أخبار الرضا (عليه السلام)، الأمالي للصدوق.
المصدر من بحار الأنوار: ج ٩٨، ص ١٠٢-١٠٣.'''),
      const SizedBox(height: 12),
      SectionCard(title: 'الحديث: ٢ — ترتيب جواهر البحار: ١٠٢٦٩', fontSize: fontSize, highlight: true,
        content: r'''قال الصادق (عليه السلام): من بات عند قبر الحسين (عليه السلام) ليلة عاشورا، لقي الله يوم القيامة ملطّخاً بدمه، وكأنّما قُتل معه في عرصة كربلا.

المصدر الأصلي: مصباح المتهجّد، إقبال الأعمال.
المصدر من بحار الأنوار: ج ٩٨، ص ١٠٣.'''),
      const SizedBox(height: 12),
      SectionCard(title: 'أحاديث في فضل زيارة الإمام الحسين (ع) عموماً', fontSize: fontSize, highlight: true,
        content: r'''الحديث: ٣
قال الإمام الصادق (عليه السلام): «مَنْ زَارَ الْحُسَيْنَ (عليه السلام) عَارِفاً بِحَقِّهِ، يَأْتَمُّ بِهِ، غَفَرَ اللهُ لَهُ مَا تَقَدَّمَ مِنْ ذَنْبِهِ وَمَا تَأَخَّرَ».
المصدر: كامل الزيارات، الباب ٥٤؛ ونُقل في بحار الأنوار، ج ١٠١، ص ٢١-٢٢.

الحديث: ٤
قال الإمام الصادق (عليه السلام): «أَيُّمَا مُؤْمِنٍ زَارَ الْحُسَيْنَ (عليه السلام) عَارِفاً بِحَقِّهِ فِي غَيْرِ عِيدٍ وَلَا عَرَفَةَ، كَتَبَ اللهُ لَهُ عِشْرِينَ حِجَّةً وَعِشْرِينَ عُمْرَةً مَبْرُورَاتٍ مُتَقَبَّلَاتٍ وَعِشْرِينَ غَزْوَةً مَعَ نَبِيٍّ مُرْسَلٍ أَوْ إِمَامٍ عَدْلٍ».
المصدر: كامل الزيارات، الباب ٧٤، الحديث ١.

الحديث: ٥
قال الإمام الصادق (عليه السلام): «مَنْ أَتَى قَبْرَ الْحُسَيْنِ (عليه السلام) عَارِفاً بِحَقِّهِ، كَانَ كَمَنْ حَجَّ ثَلَاثَ حِجَجٍ مَعَ رَسُولِ اللهِ (صلى الله عليه وآله وسلم)».
المصدر: كامل الزيارات، ص ١٤٠.

تنبيه علمي: أُثبتت الروايات مع مصادرها، ولا يُراد بهذا العرض إصدار حكم رجالي مستقل بصحّة كل طريق؛ إذ يتطلّب ذلك دراسة أسانيد الروايات بحسب مباني أهل الاختصاص.'''),
    ],
  );
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
                const Icon(Icons.headphones, color: gold, size: 22),
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
    {'name': 'الشيخ شـــــــبّر معلّــــــه', 'file': 'shibr_maalla.mp3'},
    {'name': 'الشيخ بـاقر المقـــــدسي', 'file': 'baqir_almaqdisi.mp3'},
    {'name': 'بــاســـــــــــــم الكربلائي', 'file': 'basim_alkarbalaei.mp3'},
    {'name': 'أحمـــــــــــد الفتـــــلاوي', 'file': 'ahmed_alftlawi.mp3'},
    {'name': 'الرادود محمدباقر الخاقاني', 'file': 'mohammed_baqir_alkhaqani.mp3'},
    {'name': 'الرادود أبو ذر الحلواجـي', 'file': 'aba_thar_alhelwachi.mp3'},
    {'name': 'الحاج علــــــــــي فانــــي', 'file': 'ali_fani.mp3'},
    {'name': 'الحاج علــــــــــي الكعبي', 'file': 'ali_alkabi.mp3'},
    {'name': 'الرادود عمــــــــار الكناني', 'file': 'ammar_alkinani.mp3'},
    {'name': 'الحاج مهــــــدي سماواتي', 'file': 'mahdi_samawati.mp3'},
    {'name': 'الحاج اســــــامة الكربلائي', 'file': 'osama_al_karbalaei.mp3'},
    {'name': 'الحاج ميـــــــــــــثم كاظم', 'file': 'maytham_kadhim.mp3'},
    {'name': 'الشيخ ميـــــــــــــثم التمار', 'file': 'maytham_al_tammar.mp3'},
    {'name': 'الملا عبـــــــد الحجي قمبر', 'file': 'abdulhay_qambar.mp3'},
    {'name': 'الحاج علــــــــــي أبو ريحان', 'file': 'ali_abu_rayhan.mp3'},
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

  String equalizeReaderName(String name) {
    int letters(String value) => RegExp(r'[\u0621-\u064A]').allMatches(value).length;
    final counts = ListeningPage.readers.map((reader) => letters(reader['name']!)).toList();
    final target = counts.reduce((a, b) => a > b ? a : b);
    final missing = target - letters(name);
    if (missing <= 0) return name;
    final words = name.split(' ');
    final total = letters(name);
    var seenLetters = 0;
    return words.map((word) {
      final wordCount = letters(word);
      if (wordCount == 0) return word;
      final before = seenLetters;
      seenLetters += wordCount;
      final extra = (missing * seenLetters ~/ total) - (missing * before ~/ total);
      final buffer = StringBuffer();
      var localSeen = 0;
      final gapCount = wordCount - 1;
      for (final rune in word.runes) {
        final character = String.fromCharCode(rune);
        buffer.write(character);
        if (RegExp(r'[\u0621-\u064A]').hasMatch(character)) {
          localSeen++;
          if (localSeen < wordCount && gapCount > 0) {
            final gapIndex = localSeen - 1;
            final base = extra ~/ gapCount;
            final remainder = extra % gapCount;
            final kashidas = base + (gapIndex < remainder ? 1 : 0);
            if (kashidas > 0) buffer.write(List.filled(kashidas, 'ـ').join());
          }
        }
      }
      return buffer.toString();
    }).join(' ');
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
                            color: selectedAsset == asset ? Theme.of(context).colorScheme.primary : Colors.white,
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
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold, fontSize: 16,
                        shadows: const [Shadow(color: Colors.black87, blurRadius: 5)],
                      ),
                    ),
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: Theme.of(context).colorScheme.primary,
                      inactiveTrackColor: Colors.white54,
                      thumbColor: Theme.of(context).colorScheme.primary,
                      overlayColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.16),
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
                            icon: const Icon(Icons.replay_10, color: Colors.white, size: 22),
                          ),
                          IconButton(
                            tooltip: playing ? 'إيقاف مؤقت' : 'تشغيل',
                            onPressed: duration == Duration.zero ? null : () { unawaited(tapFeedback()); playing ? handler.pause() : handler.play(); },
                            icon: Icon(playing ? Icons.pause_circle_filled : Icons.play_circle_fill, color: gold, size: 22),
                          ),
                          IconButton(
                            tooltip: 'تقديم 10 ثوانٍ',
                            onPressed: duration == Duration.zero ? null : () { unawaited(tapFeedback()); handler.seekRelative(const Duration(seconds: 10)); },
                            icon: const Icon(Icons.forward_10, color: Colors.white, size: 22),
                          ),
                          IconButton(
                            tooltip: 'إيقاف التسجيل',
                            onPressed: duration == Duration.zero ? null : () async { unawaited(tapFeedback()); await handler.stop(); },
                            icon: const Icon(Icons.stop_circle_outlined, color: Colors.white, size: 22),
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

const List<String> tasbeehHadithTexts = [
  "قال الرضا (عليه السلام): من لم يقدر على ما يكفّر به ذنوبه فليكثر من الصلاة على محمّد وآله، فإنّها تهدم الذنوب هدماً، وقال (عليه السلام): الصلاة على محمّد وآله تعدل عند اللّه عزّ وجلّ التسبيح والتهليل والتكبير.",
  "قال الصادق (عليه السلام): إذا ذكر أحد من الأنبياء فابدأ بالصلاة على محمّد ثمّ عليه، صلّى الله على محمّد وآله وعلى جميع الأنبياء.",
  "قال الباقر (عليه السلام) أو الصادق (عليه السلام): أثقل ما يوضع في الميزان يوم القيامة الصلاة على محمّد وعلى أهل بيته.",
  "قال بعض الأصحاب عند الصادق (عليه السلام): اللّهمّ صلّ على محمّد وآل محمّد كما صلّيت على إبراهيم فقال (عليه السلام): لا، ولكن كأفضل ما صلّيت وباركت على إبراهيم وآل إبراهيم، إنّك حميد مجيد.",
  "قال أمير المؤمنين (عليه السلام): صلّوا على محمّد وآل محمّد، فإنّ الله عزّ وجلّ يقبل دعاءكم عند ذكر محمّد (صلى الله عليه وآله وسلم) ودعائكم له، وحفظكم إيّاه.",
  "قال النبيّ (صلى الله عليه وآله وسلم) في فضل شهر رمضان: من أكثر فيه من الصلاة عليّ ثقّل الله ميزانه يوم تخفّ الموازين.",
  "قال العسكري (عليه السلام): إنّما اتّخذ الله إبراهيم خليلاً، لكثرة صلاته على محمّد وأهل بيته (عليهم السلام).",
  "قال أبو حمزة الثمالي: سألت الصادق (عليه السلام) عن قول الله عزّ وجلّ: ﴿إِنَّ اللّهَ وَمَلائِكَتَهُ يُصَلُّونَ عَلَى النَّبِيِّ يا أَيُّهَا الَّذينَ آمَنُوا صَلُّوا عَلَيْهِ وَسَلِّمُوا تَسْليماً﴾، فقال (عليه السلام): الصلاة من الله عزّ وجلّ رحمة، ومن الملائكة تزكية، ومن الناس دعاء، وأمّا قوله عزّ وجلّ: ﴿وَسَلِّمُوا تَسْليماً﴾ فإنّه يعني التسليم له فيما ورد عنه، فقلت له: فكيف نصلّي على محمّد وآله؟ قال (عليه السلام): تقولون: «صلوات الله وصلوات ملائكته وأنبيائه ورسله وجميع خلقه على محمّد وآل محمّد، والسلام عليه وعليهم ورحمة الله وبركاته»، فقلت: فما ثواب من صلّى على النبيّ وآله بهذه الصلاة؟ قال (عليه السلام): الخروج من الذنوب ـ والله ـ كهيئة يوم ولدته أمّه.",
  "قال عبد السلام بن نعيم: قلت للصادق (عليه السلام): إنّي دخلت البيت فلم يحضرني شيء من الدعاء إلّا الصلاة على النبيّ (صلى الله عليه وآله وسلم)، فقال (عليه السلام): لم يخرج أحد بأفضل ممّا خرجت.",
  "قال أمير المؤمنين (عليه السلام): كلّ دعاء محجوب عن السماء حتّى يصلّى على محمّد وآله.",
  "قال الصبّاح بن سيابة: قال الصادق (عليه السلام): أ لا أعلّمك شيئاً يقي الله به وجهك من حرّ جهنم؟ قلت: بلى، قال (عليه السلام): قل بعد الفجر: «اللّهمّ صلّ على محمّد وآل محمّد» مائة مرّة، يقي الله به وجهك من حرّ جهنّم.",
  "قال أبو المغيرة: قال أبو الحسن (عليه السلام): من قال في دبر صلاة الصبح وصلاة المغرب قبل أن يثني رجليه أو يكلّم أحداً: «﴿إِنَّ اللّهَ وَمَلائِكَتَهُ يُصَلُّونَ عَلَى النَّبِيِّ يا أَيُّهَا الَّذينَ آمَنُوا صَلُّوا عَلَيْهِ وَسَلِّمُوا تَسْليماً﴾ اللّهمّ صلّ على محمّد وذرّيّته» قضى الله له مائة حاجة، سبعين في الدنيا وثلاثين في الآخرة. قلت: ما معنى صلاة الله وصلاة ملائكته وصلاة المؤمنين؟ قال (عليه السلام): صلاة الله رحمة من الله، وصلاة ملائكته تزكية منهم له، وصلاة المؤمنين دعاء منهم له. ومن سرّ آل محمّد في الصلاة على النبيّ وآله: «اللّهمّ صلّ على محمّد وآل محمّد في الأوّلين، وصلّ على محمّد وآل محمّد في الآخرين، وصلّ على محمّد وآل محمّد في الملأ الأعلى، وصلّ على محمّد وآل محمّد في المرسلين، اللّهمّ أعط محمّداً الوسيلة والشرف والفضيلة والدرجة الكبيرة، اللّهــمّ إنّي آمنت بمحمّد ولم أره، فلا تحرمني يوم القيامة رؤيته، وارزقني صحبته، وتوفّني على ملّته، واسقني من حوضه مشرباً سائغاً هنيئاً لا أظمأ بعده أبداً، إنّك على كلّ شيء قدير، اللّهــمّ كما آمنت بمحمّد ولم أره، فعرّفني في الجنان وجهه، اللّهمّ بلّغ روح محمّد عنّي تحيّة كثيرة وسلاماً». فإنّ من صلّى على النبيّ (صلى الله عليه وآله وسلم) بهذه الصلوات هدمت ذنوبه، ومحيت خطاياه، ودام سروره، واستجيب دعاؤه، وأعطي أمله، وبسط له في رزقه، وأعين على عدوّه، وهي له سبب أنواع الخير، ويجعل من رفقاء نبيّه في الجنان الأعلى، يقولهنّ ثلاث مرّات غدوة، وثلاث مرّات عشيّة. (١) وبما أنّ أبا المغيرة غير معروف لم يمكن تعيين الإمام (عليه السلام).",
  "قال رجل عند الصادق (عليه السلام): اللّهمّ صلّ على محمّد وأهل بيت محمّد (عليهم السلام)، فقال الصادق (عليه السلام): يا هذا، لقد ضيّقت علينا، أ ما علمت أنّ أهل البيت خمسة أصحاب الكساء؟ فقال الرجل: كيف أقول؟ قال (عليه السلام): قل: «اللّهمّ صلّ على محمّد وآل محمّد» فنكون نحن وشيعتنا قد دخلنا فيه.",
  "قال رسول الله (صلى الله عليه وآله وسلم): ارفعوا أصواتكم بالصلاة عليّ، فإنّها تذهب بالنفاق.",
  "قال رسول الله (صلى الله عليه وآله وسلم): من صلّى عليّ يوم الجمعة مائة مرّة قضى الله له ستّين حاجة: منها للدنيا ثلاثون حاجة، وثلاثون للآخرة.",
  "قال رسول الله (صلى الله عليه وآله وسلم): من صلّى عليّ مرة صلّى الله عليه عشراً، ومن صلّى عليّ عشراً صلّى الله عليه مائة مرّة، ومن صلّى عليّ مائة مرّة صلّى الله عليه ألف مرّة، ومن صلّى عليّ ألف مرّة لا يعذّبه الله في النار أبداً.",
  "قال النبيّ (صلى الله عليه وآله وسلم): من صلّى عليّ مرّة لم يبق من ذنوبه ذرّة.",
  "قال الرضا (عليه السلام): من لم يقدر على ما يكفّر به ذنوبه، فليكثر من الصلاة على محمّد وآله، فإنّها تهدم الذنوب هدماً.",
  "قال النبيّ (صلى الله عليه وآله وسلم): من ذكرني فلم يصلّ عليّ فقد شقي، ومن أدرك رمضان فلم تصبه الرحمة فقد شقي، ومن أدرك أبواه أو أحدهما فلم يبرّ فقد شقي.",
  "قال النبيّ (صلى الله عليه وآله وسلم): ما من دعاء إلّا بينه وبين السماء حجاب حتّى يصلّى على محمّد وآل محمّد، وإذا فعل ذلك انخرق الحجاب فدخل الدعاء، وإذا لم يفعل ذلك لم يرفع الدعاء.",
  "قال رسول الله (صلى الله عليه وآله وسلم): إنّ الله أعطى ملكاً من الملائكة أسماء الخلائق كلّهم، وأسماء آبائهم، فهو قائم على قبري إذا متّ إلى يوم القيامة، فليس أحد يصلّي عليّ صلاة إلّا قال: يا محمّد، صلّى عليك فلان بن فلان بكذا وكذا، وإنّ ربّي كفّل لي أن يصلّي على ذلك العبد بكلّ واحدة عشراً.",
  "قال رسول الله (صلى الله عليه وآله وسلم): ذكر الله عزّ وجلّ عبادة، وذكري عبادة، وذكر عليّ عبادة، وذكر الأئمّة من ولده عبادة.",
  "قال النبيّ (صلى الله عليه وآله وسلم): من صلّى عليّ كلّ يوم ثلاث مرّات، وفي كلّ ليلة ثلاث مرّات حبّاً لي وشوقاً إليّ، كان حقّاً على الله عزّ وجلّ أن يغفر له ذنوبه تلك الليلة وذلك اليوم.",
  "قال النبيّ (صلى الله عليه وآله وسلم): رأيت في ما يرى النائم عمّي حمزة بن عبد المطّلب وأخي جعفر بن أبي طالب، وبين يديهما طبق من نبق فأكلا ساعة، فتحوّل النبق عنباً فأكلا ساعة، فتحوّل العنب لهما رطباً فأكلا ساعة، فدنوت منهما، وقلت: بأبي أنتما، أيّ الأعمال وجدتما أفضل؟ قالا: فديناك بالآباء والأمّهات، وجدنا أفضل الأعمال الصلاة عليك، وسقي الماء، وحبّ عليّ بن أبي طالب (عليه السلام). (النبق: ثمر السدر).",
  "قال النبيّ (صلى الله عليه وآله وسلم): من صلّى عليّ في كتاب، لم تزل الملائكة تستغفر له ما دام اسمي في ذلك الكتاب."
];
const List<String> tasbeehHadithOriginalSources = [
  "عيون أخبار الرضا (عليه السلام)؛ الأمالي للصدوق",
  "الأمالي للصدوق",
  "قرب الإسناد",
  "قرب الإسناد",
  "الخصال",
  "الأمالي للصدوق",
  "علل الشرائع",
  "معاني الأخبار",
  "ثواب الأعمال",
  "ثواب الأعمال",
  "ثواب الأعمال",
  "ثواب الأعمال",
  "ثواب الأعمال",
  "ثواب الأعمال",
  "ثواب الأعمال",
  "جامع الأخبار",
  "جامع الأخبار",
  "جامع الأخبار",
  "جامع الأخبار",
  "جامع الأخبار",
  "جمال الأسبوع",
  "الاختصاص",
  "الدعوات",
  "الدعوات",
  "منية المريد"
];
const List<String> tasbeehHadithPages = [
  "٤٧-٤٨",
  "٤٨",
  "٤٩",
  "٤٩",
  "٥٠",
  "٥٢",
  "٥٤",
  "٥٥",
  "٥٧",
  "٥٨",
  "٥٨",
  "٥٨-٥٩",
  "٥٩",
  "٥٩-٦٠",
  "٦٠",
  "٦٣",
  "٦٣",
  "٦٣",
  "٦٣",
  "٦٤",
  "٦٨",
  "٦٩",
  "٧٠",
  "٧٠",
  "٧١"
];

class _TasbeehPageState extends State<TasbeehPage> {
  int count = 0, target = 1000000, dailyCount = 0, dailyTarget = 100;
  Color backgroundColor = const Color(0xFF121212);
  bool loaded = false;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final today = '${now.year}-${now.month}-${now.day}';
    if (prefs.getString('tasbeeh_daily_date') != today) {
      await prefs.setString('tasbeeh_daily_date', today);
      await prefs.setInt('tasbeeh_daily_count', 0);
    }
    if (!mounted) return;
    setState(() {
      count = prefs.getInt('tasbeeh_salawat_count') ?? 0;
      target = 1000000;
      dailyCount = prefs.getInt('tasbeeh_daily_count') ?? 0;
      dailyTarget = prefs.getInt('tasbeeh_daily_target') ?? 100;
      backgroundColor = Color(prefs.getInt('tasbeeh_background_color') ?? 0xFF121212);
      loaded = true;
    });
  }
  Future<void> _increment() async {
    if (!loaded) return;
    unawaited(tapFeedback());
    setState(() { count++; dailyCount++; });
    final p = await SharedPreferences.getInstance();
    await p.setInt('tasbeeh_salawat_count', count);
    await p.setInt('tasbeeh_daily_count', dailyCount);
    if (count == target && mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أحسنت، أتممت العدد المحدد')));
  }
  Future<void> _reset() async {
    final ok = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('إعادة العداد'), content: const Text('هل تريد تصفير العدد الكلي؟'),
      actions: [
        TextButton(onPressed: () { unawaited(tapFeedback()); Navigator.pop(context, false); }, child: const Text('إلغاء')),
        ElevatedButton(onPressed: () { unawaited(tapFeedback()); Navigator.pop(context, true); }, child: const Text('تصفير')),
      ]));
    if (ok != true) return;
    setState(() { count = 0; dailyCount = 0; });
    final p = await SharedPreferences.getInstance();
    await p.setInt('tasbeeh_salawat_count', 0);
    await p.setInt('tasbeeh_daily_count', 0);
  }
  Future<void> _setTarget(int v) async {
    if (v < 1) return;
    setState(() => target = v);
    final p = await SharedPreferences.getInstance();
    await p.setInt('tasbeeh_target', v);
    await tapFeedback();
  }
  Future<void> _customTarget() async {
    final controller = TextEditingController(text: target.toString());
    final v = await showDialog<int>(context: context, builder: (context) => AlertDialog(
      title: const Text('تحديد عدد الصلاة'),
      content: TextField(controller: controller, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'العدد المطلوب')),
      actions: [
        TextButton(onPressed: () { unawaited(tapFeedback()); Navigator.pop(context); }, child: const Text('إلغاء')),
        ElevatedButton(onPressed: () {
          unawaited(tapFeedback());
          final n = int.tryParse(controller.text.trim());
          if (n != null && n > 0) Navigator.pop(context, n);
        }, child: const Text('حفظ')),
      ]));
    if (v != null) await _setTarget(v);
  }
  Future<void> _customDailyTarget() async {
    final controller = TextEditingController(text: dailyTarget.toString());
    final value = await showDialog<int>(context: context, builder: (context) => AlertDialog(
      title: const Text('تحديد الورد اليومي'),
      content: TextField(controller: controller, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'عدد الصلوات اليومي')),
      actions: [
        TextButton(onPressed: () { unawaited(tapFeedback()); Navigator.pop(context); }, child: const Text('إلغاء')),
        ElevatedButton(onPressed: () { unawaited(tapFeedback()); final parsed = int.tryParse(controller.text.trim()); if (parsed != null && parsed > 0) Navigator.pop(context, parsed); }, child: const Text('حفظ')),
      ],
    ));
    if (value == null) return;
    setState(() => dailyTarget = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('tasbeeh_daily_target', value);
  }

  Future<void> _chooseBackground() async {
    const colors = <Color>[Color(0xFF121212),Color(0xFF1B4332),Color(0xFF172554),Color(0xFF3B1024),Color(0xFF173D3D),Color(0xFF30234A)];
    final chosen = await showDialog<Color>(context: context, builder: (context) => AlertDialog(
      title: const Text('خلفية المسبحة'),
      content: Wrap(spacing: 12, runSpacing: 12, children: colors.map((color) => InkWell(
        onTap: () { unawaited(tapFeedback()); Navigator.pop(context, color); },
        child: CircleAvatar(backgroundColor: color, radius: 22, child: const Icon(Icons.check, color: Colors.white)),
      )).toList())));
    if (chosen == null) return;
    setState(() => backgroundColor = chosen);
    final p = await SharedPreferences.getInstance();
    await p.setInt('tasbeeh_background_color', chosen.value);
  }
  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final progress = (count / target).clamp(0.0, 1.0).toDouble();
    final dailyProgress = (dailyCount / dailyTarget).clamp(0.0, 1.0).toDouble();
    return Column(children: [
      Container(width: double.infinity, color: backgroundColor, padding: const EdgeInsets.fromLTRB(12,5,12,8),
        child: Column(children: [
          Align(alignment: Alignment.centerRight, child: IconButton(onPressed: () { unawaited(tapFeedback()); _chooseBackground(); }, icon: const Icon(Icons.palette_outlined, color: gold, size: 22), tooltip: 'تغيير خلفية المسبحة')),
          const SizedBox(height: 4),
          Text.rich(highlightImamHussein('﴿إِنَّ اللَّهَ وَمَلَائِكَتَهُ يُصَلُّونَ عَلَى النَّبِيِّ يَا أَيُّهَا الَّذِينَ آمَنُوا صَلُّوا عَلَيْهِ وَسَلِّمُوا تَسْلِيمًا﴾ — سورة الأحزاب، الآية ٥٦',
            const TextStyle(color: Colors.white, fontSize: 22, height: 1.55, fontFamily: 'AmiriQuran')), textAlign: TextAlign.center),
          const SizedBox(height: 4),
          const Text('المسبحة الإلكترونية', textAlign: TextAlign.center,
            style: TextStyle(color: gold, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          InkWell(onTap: _increment, customBorder: const CircleBorder(), splashFactory: InkRipple.splashFactory, child: AnimatedContainer(duration: const Duration(milliseconds: 200),
            width: 154, height: 154,
            decoration: BoxDecoration(shape: BoxShape.circle,
              gradient: RadialGradient(colors: [accent.withValues(alpha: 0.88), backgroundColor]),
              border: Border.all(color: accent, width: 5),
              boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.3), blurRadius: 16, spreadRadius: 2)]),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('$count', style: const TextStyle(color: gold, fontSize: 35, fontWeight: FontWeight.bold)),
              const Text('اضغط للتسبيح', style: TextStyle(color: Colors.white, fontSize: 12)),
            ]))),
          const SizedBox(height: 6),
          Text('الهدف: $target  •  المتبقي: ' + (target-count).clamp(0,target).toString(), style: const TextStyle(color: Colors.white, fontSize: 14)),
          Text('الورد اليومي: $dailyCount من $dailyTarget', style: const TextStyle(color: gold, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          SizedBox(width: 230, child: ClipRRect(borderRadius: BorderRadius.circular(20), child: LinearProgressIndicator(value: dailyProgress, minHeight: 5, backgroundColor: Colors.white24, valueColor: AlwaysStoppedAnimation<Color>(gold)))),
          const SizedBox(height: 5),
          SizedBox(width: 230, child: ClipRRect(borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(value: progress, minHeight: 6, backgroundColor: Colors.white24, valueColor: AlwaysStoppedAnimation<Color>(accent)))),
          const SizedBox(height: 7),
          Wrap(alignment: WrapAlignment.center, spacing: 7, runSpacing: 5, children: [
            ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.white), onPressed: () { unawaited(tapFeedback()); _setTarget(1000000); }, child: const Text('تحدي المليون')),
            OutlinedButton(style: OutlinedButton.styleFrom(foregroundColor: accent, side: BorderSide(color: accent)), onPressed: () { unawaited(tapFeedback()); _customDailyTarget(); }, child: const Text('تحديد الورد اليومي')),
            IconButton(onPressed: () { unawaited(tapFeedback()); _reset(); }, icon: Icon(Icons.refresh, color: accent), tooltip: 'تصفير العداد'),
          ]),
        ])),
      Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(12,14,12,24), children: [
        const SizedBox(height: 8),
        const Text('أحاديث في فضل الصلاة على محمّد وآل محمّد', textAlign: TextAlign.center, style: TextStyle(color: gold, fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('أحاديث في فضل الصلاة على محمّد وآل محمّد، وأنّ الصلاة عليهم تكفّر الذنوب وتثقّل الميزان، وفي ما يقال عند ذكر الأنبياء، وعلّة اتّخاذ الله إبراهيم خليلاً. هذه النصوص من مجموعة «جواهر البحار» المقتبسة من «بحار الأنوار» للعلامة المجلسي، مع إبقاء أرقامها ومصادرها كما وردت في النص المرسل.', textAlign: TextAlign.justify, style: TextStyle(height: 1.8)),
        const SizedBox(height: 10),
        ...List.generate(tasbeehHadithTexts.length, (index) => Card(
          margin: const EdgeInsets.symmetric(vertical: 7), elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: accent.withValues(alpha: 0.8), width: 1.2)),
          child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('الحديث: ' + (index+1).toString() + '  |  ترتيب جواهر البحار: ' + (9455+index).toString(),
              textAlign: TextAlign.right, style: TextStyle(color: accent, fontWeight: FontWeight.bold, fontSize: 16)),
            const Divider(),
            SelectableText(tasbeehHadithTexts[index], textAlign: TextAlign.justify, style: TextStyle(fontSize: widget.fontSize-2, height: 1.9)),
            const SizedBox(height: 9),
            Text('المصدر الأصلي: ' + tasbeehHadithOriginalSources[index], style: const TextStyle(color: Colors.grey, height: 1.6)),
            Text('المصدر من بحار الأنوار: ج ٩١، ص ' + tasbeehHadithPages[index], style: const TextStyle(color: Colors.grey, height: 1.6)),
          ])),
        )),
      ])),
    ]);
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
  late double localFontSize;

  @override
  void initState() {
    super.initState();
    localFont = widget.selectedFont;
    localColor = widget.selectedColor;
    localFontSize = widget.fontSize;
  }

  @override
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedFont != widget.selectedFont) localFont = widget.selectedFont;
    if (oldWidget.selectedColor != widget.selectedColor) localColor = widget.selectedColor;
    if (oldWidget.fontSize != widget.fontSize) localFontSize = widget.fontSize;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.alarm, color: gold),
              title: const Text('المنبه'),
              subtitle: const Text('منبّهات زيارة عاشوراء والصلاة على محمد وآل محمد'),
              trailing: const Icon(Icons.chevron_left),
              onTap: () { unawaited(tapFeedback()); Navigator.push(context, MaterialPageRoute(builder: (_) => const ReminderManagerPage())); },
            ),
          ),
          Card(
            child: SwitchListTile(
              secondary: const Icon(Icons.dark_mode, color: gold),
              title: const Text('الوضع الليلي'),
              subtitle: Text(widget.isDarkMode ? 'مفعّل' : 'غير مفعّل'),
              value: widget.isDarkMode,
              onChanged: (_) { unawaited(tapFeedback()); widget.onToggleTheme(); },
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
                      unawaited(tapFeedback());
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
                      unawaited(tapFeedback());
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
              subtitle: Text('الحجم الحالي: ${localFontSize.toInt()}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(onPressed: localFontSize <= 16 ? null : () {
                    unawaited(tapFeedback());
                    setState(() => localFontSize = (localFontSize - 2).clamp(16.0, 36.0).toDouble());
                    widget.onChangeFontSize(-2);
                  }, icon: const Icon(Icons.remove)),
                  IconButton(onPressed: localFontSize >= 36 ? null : () {
                    unawaited(tapFeedback());
                    setState(() => localFontSize = (localFontSize + 2).clamp(16.0, 36.0).toDouble());
                    widget.onChangeFontSize(2);
                  }, icon: const Icon(Icons.add)),
                ],
              ),
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
    var saved = await loadSavedReminders();
    // اطلب صلاحية عرض الإشعارات عند فتح صفحة المنبّه، حتى للأوقات المحفوظة سابقاً.
    final canSchedule = await ensurePermissions();
    if (!canSchedule && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('فعّل إشعارات التطبيق من إعدادات الهاتف حتى تظهر التنبيهات.'),
      ));
    }
    if (saved.isEmpty) {
      saved = [
        AshuraReminder(id: 2001, hour: 8, minute: 0, weekdays: const [1,2,3,4,5,6,7], enabled: canSchedule),
        AshuraReminder(id: 2002, hour: 14, minute: 0, weekdays: const [1,2,3,4,5,6,7], enabled: canSchedule),
        AshuraReminder(id: 2003, hour: 20, minute: 0, weekdays: const [1,2,3,4,5,6,7], enabled: canSchedule),
      ];
      await saveReminders(saved);
    }
    if (canSchedule) {
      for (final reminder in saved.where((item) => item.enabled)) {
        await scheduleReminder(reminder);
      }
    }
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
    final granted = await ensureNotificationPermissions();
    if (!granted) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يرجى السماح بإشعارات التطبيق من إعدادات الهاتف.')));
      return false;
    }
    if (!exactAlarmsAllowed && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لم يُفعّل التوقيت الدقيق؛ ستعمل الإشعارات بالتوقيت المتاح وقد تتأخر قليلاً.')));
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
    if (reminders.length >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يمكنك إضافة خمسة أوقات كحد أقصى لزيارة عاشوراء.')),
      );
      return;
    }
    final nextId = (reminders.isEmpty ? 2000 : reminders.map((r) => r.id).reduce((a, b) => a > b ? a : b)) + 1;
    const defaultHours = [8, 14, 20, 11, 17];
    final defaultHour = defaultHours[reminders.length.clamp(0, 4).toInt()];
    final draft = AshuraReminder(id: nextId, hour: defaultHour, minute: 0, weekdays: const [1,2,3,4,5,6,7], enabled: true);
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
      appBar: AppBar(title: const Text('المنبه')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: reminders.length >= 5 ? null : () { unawaited(tapFeedback()); addReminder(); },
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
                  child: ListTile(
                    leading: const Icon(Icons.notifications_active, color: gold),
                    title: const Text('اختبار الإشعار المنبثق'),
                    subtitle: const Text('أرسل إشعاراً تجريبياً الآن للتحقق من الصلاحيات'),
                    onTap: () async {
                      unawaited(tapFeedback());
                      if (!await ensurePermissions()) return;
                      final fullScreenAllowed = true;
                      if (!fullScreenAllowed && mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لم تُمنح صلاحية التنبيه بملء الشاشة. فعّلها من: إعدادات الهاتف ← التطبيقات ← زيارة عاشوراء ← وصول خاص للتطبيقات ← التنبيهات بملء الشاشة.')));
                      }
                      await showReminderTestNotification();
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أُرسل الاختبار. إذا لم يظهر منبثقاً، فعّل صلاحية التنبيهات بملء الشاشة وإشعارات شاشة القفل من إعدادات الهاتف.')));
                    },
                  ),
                ),
                Card(
                  child: Column(
                    children: [
                      SwitchListTile(
                        secondary: const Icon(Icons.volunteer_activism, color: gold),
                        title: const Text('منبه الصلاة على محمد وآل محمد'),
                        subtitle: const Text('هل صليت على محمد وآل محمد هذا اليوم؟'),
                        value: salawatEnabled,
                        onChanged: (value) { unawaited(tapFeedback()); updateSalawatReminder(enabled: value); },
                      ),
                      ListTile(
                        leading: const Icon(Icons.access_time, color: gold),
                        title: const Text('وقت منبّه الصلاة على محمد وآل محمد'),
                        subtitle: Text(TimeOfDay(hour: salawatHour, minute: salawatMinute).format(context)),
                        trailing: const Icon(Icons.edit, color: gold),
                        onTap: () { unawaited(tapFeedback()); chooseSalawatTime(); },
                      ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('منبّهات زيارة عاشوراء (حتى خمسة أوقات)',
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
                      leading: const Icon(Icons.alarm, color: gold, size: 22),
                      title: Text(time, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
                      subtitle: Text(daySummary(reminder.weekdays)),
                      onTap: () { unawaited(tapFeedback()); editReminder(reminder); },
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Switch(value: reminder.enabled, onChanged: (value) { unawaited(tapFeedback()); toggleReminder(reminder, value); }),
                          PopupMenuButton<String>(
                            onSelected: (value) {
                              unawaited(tapFeedback());
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
                unawaited(tapFeedback());
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
              onChanged: (checked) {
                unawaited(tapFeedback());
                setState(() {
                if (checked == true) { if (!days.contains(index + 1)) days.add(index + 1); }
                else { days.remove(index + 1); }
                days.sort();
                });
              },
            )),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () { unawaited(tapFeedback()); Navigator.pop(context); }, child: const Text('إلغاء')),
        ElevatedButton(
          onPressed: days.isEmpty ? null : () { unawaited(tapFeedback()); Navigator.pop(context, widget.reminder.copyWith(hour: hour, minute: minute, weekdays: days)); },
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
          const Icon(Icons.mosque, color: gold, size: 22),
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
