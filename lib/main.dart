import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:io';
import 'package:flutter/services.dart';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:vibration/vibration.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'firebase_options.dart';
import 'messaging_page.dart';
import 'app_localization.dart';

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
const String reminderChannelKey = 'ashura_reminders_sound_v2';
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
    await _player.setAudioSource(AudioSource.asset(assetPath), preload: true);
    unawaited(_player.play().catchError((Object error, StackTrace stackTrace) {
      debugPrint('Audio playback failed for $assetPath: $error');
    }));
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
  final android = notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  await android?.createNotificationChannel(const AndroidNotificationChannel(
    'app_updates_v1',
    'تحديثات تطبيق زيارة عاشوراء',
    description: 'إشعارات الإصدارات الجديدة للتطبيق',
    importance: Importance.high,
    playSound: true,
  ));
  exactAlarmsAllowed = await canScheduleExactAlarms();
}

Future<void> initUpdateMessaging() async {
  try {
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);
    await messaging.subscribeToTopic('app_updates');
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      final notice = message.notification;
      if (notice == null) return;
      await notifications.show(
        message.hashCode,
        notice.title ?? 'تحديثات زيارة عاشوراء',
        notice.body ?? 'يتوفر تحديث جديد للتطبيق.',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'app_updates_v1',
            'تحديثات تطبيق زيارة عاشوراء',
            channelDescription: 'إشعارات الإصدارات الجديدة للتطبيق',
            importance: Importance.high,
            priority: Priority.high,
            playSound: true,
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );
    });
  } catch (error) {
    debugPrint('تعذر تفعيل إشعارات التحديثات: $error');
  }
}
const NotificationDetails reminderNotificationDetails = NotificationDetails(
  android: AndroidNotificationDetails(reminderChannelKey, 'منبّهات زيارة عاشوراء',
    channelDescription: 'تذكيرات الزيارة والصلاة على محمد وآل محمد',
    importance: Importance.max, priority: Priority.high, playSound: true,
    enableVibration: true, category: AndroidNotificationCategory.reminder),
  iOS: DarwinNotificationDetails(),
);
const NotificationDetails salawatNotificationDetails = NotificationDetails(
  android: AndroidNotificationDetails(
    'salawat_daily_reminder_v1',
    'منبّه الصلاة على محمد وآل محمد',
    channelDescription: 'تذكير يومي بالصلاة على محمد وآل محمد',
    importance: Importance.max,
    priority: Priority.high,
    playSound: true,
    enableVibration: true,
    category: AndroidNotificationCategory.reminder,
  ),
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
  await notifications.show(90999, tr('زيارة عاشوراء'),
    tr('هل زرت الإمام الحسين عليه السلام هذا اليوم؟'), reminderNotificationDetails);
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
String get reminderMessage => tr('عندما يتّسع يومك لزيارة عاشوراء رغم ضيق الوقت، فهذا التوفيق بعينه');
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
    await notifications.zonedSchedule(_notificationId(reminder.id, weekday), tr('زيارة عاشوراء'),
      reminderMessage, _nextWeekdayTime(weekday, reminder.hour, reminder.minute),
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
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
    throw ArgumentError('وقت منبّه الصلاة غير صالح');
  }
  final now = tz.TZDateTime.now(tz.local);
  var next = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
  if (!next.isAfter(now)) {
    next = tz.TZDateTime(tz.local, now.year, now.month, now.day + 1, hour, minute);
  }
  await notifications.zonedSchedule(
    salawatReminderNotificationId,
    'تذكير الصلاة على محمد وآل محمد',
    'حان وقت الصلاة على محمد وآل محمد؛ لا تنسَ وردك اليومي.',
    next,
    salawatNotificationDetails,
    androidScheduleMode: _scheduleMode,
    uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    matchDateTimeComponents: DateTimeComponents.time,
  );
}
Future<void> restoreSalawatReminder() async {
  final prefs = await SharedPreferences.getInstance();
  await scheduleSalawatReminder(enabled: prefs.getBool('salawat_reminder_enabled') ?? false,
    hour: prefs.getInt('salawat_reminder_hour') ?? 9, minute: prefs.getInt('salawat_reminder_minute') ?? 0);
}
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
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
    await initUpdateMessaging();
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
  String selectedLanguage = 'ar';

  @override
  void initState() {
    super.initState();
    loadSettings();
  }

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      isDarkMode = prefs.getBool('ashura_dark') ?? false;
      fontSize = (prefs.getDouble('ashura_font') ?? 20).clamp(16.0, 36.0).toDouble();
      entered = false; // شاشة البداية تظهر عند كل تشغيل للتطبيق.
      final savedFont = prefs.getString('ashura_font_family') ?? 'Amiri';
      selectedFont = const ['Amiri', 'AmiriQuran', 'NotoNaskhArabic', 'Cairo', 'ArefRuqaa', 'Tajawal', 'NotoKufiArabic'].contains(savedFont) ? savedFont : 'Amiri';
      final savedColor = prefs.getString('ashura_theme_color') ?? 'أخضر';
      selectedLanguage = ['ar', 'fa', 'en'].contains(prefs.getString('ashura_language')) ? prefs.getString('ashura_language')! : 'ar';
      appLanguage.value = selectedLanguage;
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

  Future<void> changeLanguage(String value) async {
    if (!const ['ar', 'fa', 'en'].contains(value)) return;
    appLanguage.value = value;
    setState(() => selectedLanguage = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ashura_language', value);
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
    if (!const ['Amiri', 'AmiriQuran', 'NotoNaskhArabic', 'Cairo', 'ArefRuqaa', 'Tajawal', 'NotoKufiArabic'].contains(value)) return;
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
      title: tr('زيارة عاشوراء'),
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
        textDirection: selectedLanguage == 'en' ? TextDirection.ltr : TextDirection.rtl,
        child: entered
            ? HomeScreen(
                isDarkMode: isDarkMode,
                fontSize: fontSize,
                selectedFont: selectedFont,
                selectedColor: selectedColor,
                selectedLanguage: selectedLanguage,
                onChangeLanguage: changeLanguage,
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

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  bool pressed = false;
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> enter() async {
    if (pressed) return;
    setState(() => pressed = true);
    unawaited(tapFeedback());
    await Future.delayed(const Duration(milliseconds: 180));
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (mounted) widget.onEnter();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080808),
      body: SizedBox.expand(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'assets/intro_background.png',
              fit: BoxFit.cover,
              alignment: Alignment.center,
              filterQuality: FilterQuality.high,
              errorBuilder: (_, __, ___) =>
                  const ColoredBox(color: Color(0xFF080808)),
            ),
            Center(
              child: AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  final progress = _pulseController.value;
                  return Transform.translate(
                    offset: Offset(0, -12 * math.sin(progress * math.pi)),
                    child: Transform.scale(
                      scale: 1 + (0.035 * progress),
                      child: child,
                    ),
                  );
                },
                child: Material(
                  color: Colors.transparent,
                  shape: const CircleBorder(),
                  child: InkWell(
                    onTap: pressed ? null : enter,
                    customBorder: const CircleBorder(),
                    child: Ink(
                      width: 158,
                      height: 158,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const RadialGradient(
                          center: Alignment(-0.35, -0.45),
                          radius: 1.15,
                          colors: [
                            Color(0xFFFFE6A6),
                            Color(0xFFD9A441),
                            Color(0xFF8D1515),
                            Color(0xFF4A0808),
                          ],
                          stops: [0.0, 0.36, 0.72, 1.0],
                        ),
                        border: Border.all(
                          color: const Color(0xFFFFE7AD),
                          width: 3,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFFC65C).withValues(alpha: 0.58),
                            blurRadius: 28,
                            spreadRadius: 2,
                            offset: const Offset(0, 7),
                          ),
                          const BoxShadow(
                            color: Colors.black54,
                            blurRadius: 12,
                            offset: Offset(0, 5),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Padding(
                          padding: EdgeInsets.all(14),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              'تَفَضَّلْ بِالدُّخُولِ',
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              style: TextStyle(
                                color: Colors.white,
                                fontFamily: 'Amiri',
                                fontSize: 23,
                                fontWeight: FontWeight.bold,
                                shadows: [
                                  Shadow(
                                    color: Colors.black87,
                                    blurRadius: 6,
                                    offset: Offset(1, 2),
                                  ),
                                ],
                              ),
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
      ),
    );
  }
}
class _WelcomeOrnament extends StatelessWidget {
  final String text;
  final double size;
  const _WelcomeOrnament({required this.text, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF080808),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white,
          fontSize: size,
          height: 1,
          shadows: const [
            Shadow(color: Color(0xFFAAAAAA), blurRadius: 5),
          ],
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  final bool isDarkMode;
  final double fontSize;
  final String selectedFont;
  final String selectedColor;
  final String selectedLanguage;
  final Function(String) onChangeLanguage;
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
    required this.selectedLanguage,
    required this.onChangeLanguage,
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
    final labels = [
      tr('زِيَارَةُ عَاشُورَاءَ'),
      tr('فَضْلُ زِيَارَةِ عَاشُورَاءَ'),
      tr('اِسْتِمَاعُ الزِّيَارَةِ'),
      tr('زِيَارَةُ الإِمَامِ العَبَّاسِ (ع)'),
      tr('إِنَّ الْحَسَنَاتِ يُذْهِبْنَ السَّيِّئَاتِ'),
    ];
    return Scaffold(
      appBar: AppBar(
        backgroundColor: appPrimary,
        title: Text(tr('زيارة عاشوراء'),
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            onPressed: () {
              unawaited(tapFeedback());
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MessagingEntryPage()),
              );
            },
            icon: const Icon(Icons.forum_outlined),
            tooltip: tr('المراسلة الخاصة'),
          ),
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
                  selectedLanguage: widget.selectedLanguage,
                  onChangeLanguage: widget.onChangeLanguage,
                  onToggleTheme: widget.onToggleTheme,
                  onChangeFontSize: widget.onChangeFontSize,
                  onChangeFontFamily: widget.onChangeFontFamily,
                  onChangeThemeColor: widget.onChangeThemeColor,
                ),
              ),
            );
            },
            icon: const Icon(Icons.settings),
            tooltip: tr('الإعدادات'),
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
            SelectableText.rich(highlightImamHussein(content, TextStyle(fontSize: fontSize, height: 1.85, fontFamily: 'AmiriQuran'))),
          ],
        ),
      ),
    );
  }
}

class NajahPoemCard extends StatelessWidget {
  final double fontSize;
  const NajahPoemCard({super.key, required this.fontSize});

  static const String poem =
      'إِذَا شِئْتَ النَّجَاةَ فَزُرْ حُسَيْنًا    لِكَيْ تَلْقَى الإِلَهَ قَرِيرَ عَيْنِ\n'
      'فَإِنَّ النَّارَ لَيْسَ تَمَسُّ جِسْمًا     عَلَيْهِ غُبَارُ زُوَّارِ الْحُسَيْنِ';

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: gold, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'النَّجَاةُ بِزِيَارَةِ الإِمَامِ الحُسَيْنِ (عَلَيْهِ السَّلَامُ)',
              textAlign: TextAlign.center,
              style: const TextStyle(color: gold, fontSize: 18, fontWeight: FontWeight.bold, height: 1.7),
            ),
            const Divider(height: 22),
            Text.rich(
              highlightImamHussein(
                poem,
                TextStyle(fontSize: fontSize.clamp(18.0, 28.0), height: 1.9, fontFamily: 'AmiriQuran'),
              ),
              textAlign: TextAlign.center,
              textDirection: TextDirection.rtl,
            ),
            const SizedBox(height: 10),
            const Text(
              'للشاعر جمال الدين علي بن عبدالعزيز الخليعي الموصلي (المتوفى سنة ٥٨٠ للهجرة)',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey, height: 1.6),
            ),
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
        NajahPoemCard(fontSize: fontSize),
        const SizedBox(height: 12),
        SectionCard(title: tr('نية الزيارة'), content: intentionText,
            fontSize: fontSize, highlight: true),
        const SizedBox(height: 12),
        SectionCard(title: tr('نص زيارة عاشوراء كاملاً'), content: visitText,
            fontSize: fontSize),
        const SizedBox(height: 12),
        CounterWidget(
          storageKey: 'ashura_lعن_counter',
          title: tr('ثم تقول (100 مرّة) - اللعن'),
          phrase: cursePhrase,
          fontSize: fontSize,
        ),
        const SizedBox(height: 12),
        CounterWidget(
          storageKey: 'ashura_salam_counter',
          title: tr('ثم تقول (100 مرّة) - السلام'),
          phrase: salamPhrase,
          fontSize: fontSize,
        ),
        const SizedBox(height: 12),
        SectionCard(title: tr('بعد المئة'), content: afterHundred,
            fontSize: fontSize, highlight: true),
        const SizedBox(height: 12),
        SectionCard(title: tr('سجدة الزيارة'), content: 'ثم تسجد وتقول:\n\n$sajda',
            fontSize: fontSize, highlight: true),
        const SizedBox(height: 12),
        CompletedVisitCounter(),
        const SizedBox(height: 20),
        Text(tr('المصدر: مفاتيح الجنان، زيارة عاشوراء.'),
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
      const SnackBar(content: Text(tr('تقبّل الله زيارتكم، تم تسجيل القراءة'))),
    );
  }

  Future<void> resetCount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr('إعادة العداد')),
        content: Text(tr('هل تريد تصفير عدد الزيارات المكتملة؟')),
        actions: [
          TextButton(
            onPressed: () { unawaited(tapFeedback()); Navigator.pop(dialogContext, false); },
            child: Text(tr('إلغاء')),
          ),
          TextButton(
            onPressed: () { unawaited(tapFeedback()); Navigator.pop(dialogContext, true); },
            child: Text(tr('تصفير')),
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
                label: Text(tr('أتممت قراءة الزيارة كاملة')),
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
                label: Text(tr('تصفير العداد')),
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
                  label: Text(tr('العدد: $count')),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary, foregroundColor: Colors.white),
                ),
                IconButton(onPressed: () { unawaited(tapFeedback()); reset(); }, icon: const Icon(Icons.refresh),
                    tooltip: tr('إعادة العداد')),
              ],
            ),
            if (count == 100)
              Text(tr('أحسنت، اكتمل العدد'),
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
      Text.rich(highlightImamHussein('أَحَادِيثٌ فِي فَضْلِ زِيَارَةِ الْإِمَامِ الْحُسَيْنِ (عَلَيْهِ السَّلَامُ) فِي يَوْمِ عَاشُورَاءَ', const TextStyle(color: gold, fontSize: 22, fontWeight: FontWeight.bold, height: 1.6)), textAlign: TextAlign.center),
      const SizedBox(height: 14),
      SectionCard(title: tr('الحديث: ١ — ترتيب جواهر البحار: ١٠٢٦٨'), fontSize: fontSize, highlight: true,
        content: r'''قَالَ الرَّيَّانُ بْنُ شَبِيبٍ: دَخَلْتُ عَلَى الرِّضَا (عَلَيْهِ السَّلَامُ) فِي أَوَّلِ يَوْمٍ مِنْ مُحَرَّمٍ، فَقَالَ (عَلَيْهِ السَّلَامُ) لِي: يَا ابْنَ شَبِيبٍ، أَصَائِمٌ أَنْتَ؟ فَقُلْتُ: لَا، فَقَالَ: إِنَّ هَذَا الْيَوْمَ هُوَ الْيَوْمُ الَّذِي دَعَا فِيهِ زَكَرِيَّا (عَلَيْهِ السَّلَامُ) رَبَّهُ عَزَّ وَجَلَّ فَقَالَ: ﴿رَبِّ هَبْ لِي مِنْ لَدُنْكَ ذُرِّيَّةً طَيِّبَةً إِنَّكَ سَمِيعُ الدُّعَاءِ﴾، فَاسْتَجَابَ اللَّهُ لَهُ، وَأَمَرَ الْمَلَائِكَةَ فَنَادَتْ زَكَرِيَّا (عَلَيْهِ السَّلَامُ): ﴿وَهُوَ قَائِمٌ يُصَلِّي فِي الْمِحْرَابِ أَنَّ اللَّهَ يُبَشِّرُكَ بِيَحْيَى﴾، فَمَنْ صَامَ هَذَا الْيَوْمَ، ثُمَّ دَعَا اللَّهَ عَزَّ وَجَلَّ، اسْتَجَابَ اللَّهُ لَهُ كَمَا اسْتَجَابَ لِزَكَرِيَّا (عَلَيْهِ السَّلَامُ).

ثُمَّ قَالَ (عَلَيْهِ السَّلَامُ): يَا ابْنَ شَبِيبٍ، إِنَّ الْمُحَرَّمَ هُوَ الشَّهْرُ الَّذِي كَانَ أَهْلُ الْجَاهِلِيَّةِ فِيمَا مَضَى يُحَرِّمُونَ فِيهِ الظُّلْمَ وَالْقِتَالَ لِحُرْمَتِهِ، فَمَا عَرَفَتْ هَذِهِ الْأُمَّةُ حُرْمَةَ شَهْرِهَا وَلَا حُرْمَةَ نَبِيِّهَا (صَلَّى اللَّهُ عَلَيْهِ وَآلِهِ وَسَلَّمَ)، لَقَدْ قَتَلُوا فِي هَذَا الشَّهْرِ ذُرِّيَّتَهُ، وَسَبَوْا نِسَاءَهُ، وَانْتَهَبُوا ثَقَلَهُ، فَلَا غَفَرَ اللَّهُ لَهُمْ ذَلِكَ أَبَدًا.

يَا ابْنَ شَبِيبٍ، إِنْ كُنْتَ بَاكِيًا لِشَيْءٍ فَابْكِ لِلْحُسَيْنِ بْنِ عَلِيِّ بْنِ أَبِي طَالِبٍ (عَلَيْهِ السَّلَامُ)، فَإِنَّهُ قُتِلَ مَظْلُومًا، وَقُتِلَ مَعَهُ مِنْ أَهْلِ بَيْتِهِ ثَمَانِيَةَ عَشَرَ رَجُلًا مَا لَهُمْ فِي الْأَرْضِ شَبِيهٌ، وَلَقَدْ بَكَتِ السَّمَاوَاتُ السَّبْعُ وَالْأَرَضُونَ لِقَتْلِهِ، وَلَقَدْ نَزَلَ إِلَى الْأَرْضِ مِنَ الْمَلَائِكَةِ أَرْبَعَةُ آلَافٍ لِنَصْرِهِ، فَوَجَدُوهُ قَدْ قُتِلَ، فَهُمْ عِنْدَ قَبْرِهِ شُعْثٌ غُبْرٌ إِلَى أَنْ يَقُومَ الْقَائِمُ، فَيَكُونُونَ مِنْ أَنْصَارِهِ، وَشِعَارُهُمْ: «يَا لَثَارَاتِ الْحُسَيْنِ (عَلَيْهِ السَّلَامُ)».

يَا ابْنَ شَبِيبٍ، لَقَدْ حَدَّثَنِي أَبِي عَنْ أَبِيهِ، عَنْ جَدِّهِ (عَلَيْهِ السَّلَامُ)، أَنَّهُ لَمَّا قُتِلَ جَدِّي الْحُسَيْنُ (عَلَيْهِ السَّلَامُ) أَمْطَرَتِ السَّمَاءُ دَمًا وَتُرَابًا أَحْمَرَ.

يَا ابْنَ شَبِيبٍ، إِنْ بَكَيْتَ عَلَى الْحُسَيْنِ (عَلَيْهِ السَّلَامُ) حَتَّى تَصِيرَ دُمُوعُكَ عَلَى خَدَّيْكَ، غَفَرَ اللَّهُ لَكَ كُلَّ ذَنْبٍ أَذْنَبْتَهُ، صَغِيرًا كَانَ أَوْ كَبِيرًا، قَلِيلًا كَانَ أَوْ كَثِيرًا.

يَا ابْنَ شَبِيبٍ، إِنْ سَرَّكَ أَنْ تَلْقَى اللَّهَ عَزَّ وَجَلَّ وَلَا ذَنْبَ عَلَيْكَ، فَزُرِ الْحُسَيْنَ (عَلَيْهِ السَّلَامُ).

يَا ابْنَ شَبِيبٍ، إِنْ سَرَّكَ أَنْ تَسْكُنَ الْغُرَفَ الْمَبْنِيَّةَ فِي الْجَنَّةِ مَعَ النَّبِيِّ (صَلَّى اللَّهُ عَلَيْهِ وَآلِهِ وَسَلَّمَ)، فَالْعَنْ قَتَلَةَ الْحُسَيْنِ (عَلَيْهِ السَّلَامُ).

يَا ابْنَ شَبِيبٍ، إِنْ سَرَّكَ أَنْ يَكُونَ لَكَ مِنَ الثَّوَابِ مِثْلُ مَا لِمَنِ اسْتُشْهِدَ مَعَ الْحُسَيْنِ (عَلَيْهِ السَّلَامُ)، فَقُلْ مَتَى مَا ذَكَرْتَهُ: يَا لَيْتَنِي كُنْتُ مَعَهُمْ فَأَفُوزَ فَوْزًا عَظِيمًا.

يَا ابْنَ شَبِيبٍ، إِنْ سَرَّكَ أَنْ تَكُونَ مَعَنَا فِي الدَّرَجَاتِ الْعُلَى مِنَ الْجِنَانِ، فَاحْزَنْ لِحُزْنِنَا، وَافْرَحْ لِفَرَحِنَا، وَعَلَيْكَ بِوَلَايَتِنَا، فَلَوْ أَنَّ رَجُلًا تَوَلَّى حَجَرًا لَحَشَرَهُ اللَّهُ مَعَهُ يَوْمَ الْقِيَامَةِ.

الْمَصْدَرُ الْأَصْلِيُّ: عُيُونُ أَخْبَارِ الرِّضَا (عَلَيْهِ السَّلَامُ)، وَالْأَمَالِي لِلصَّدُوقِ.
الْمَصْدَرُ مِنْ بِحَارِ الْأَنْوَارِ: الْجُزْءُ ٩٨، الصَّفْحَتَانِ ١٠٢-١٠٣.'''),
      const SizedBox(height: 12),
      SectionCard(title: tr('الحديث: ٢ — ترتيب جواهر البحار: ١٠٢٦٩'), fontSize: fontSize, highlight: true,
        content: r'''قَالَ الصَّادِقُ (عَلَيْهِ السَّلَامُ): مَنْ بَاتَ عِنْدَ قَبْرِ الْحُسَيْنِ (عَلَيْهِ السَّلَامُ) لَيْلَةَ عَاشُورَاءَ، لَقِيَ اللَّهَ يَوْمَ الْقِيَامَةِ مُلَطَّخًا بِدَمِهِ، وَكَأَنَّمَا قُتِلَ مَعَهُ فِي عَرْصَةِ كَرْبَلَاءَ.

الْمَصْدَرُ الْأَصْلِيُّ: مِصْبَاحُ الْمُتَهَجِّدِ، وَإِقْبَالُ الْأَعْمَالِ.
الْمَصْدَرُ مِنْ بِحَارِ الْأَنْوَارِ: الْجُزْءُ ٩٨، الصَّفْحَةُ ١٠٣.'''),
      const SizedBox(height: 12),
      SectionCard(title: tr('أَحَادِيثُ فِي فَضْلِ زِيَارَةِ الْإِمَامِ الْحُسَيْنِ (عَلَيْهِ السَّلَامُ) عُمُومًا'), fontSize: fontSize, highlight: true,
        content: r'''الْحَدِيثُ: ٣
قَالَ الْإِمَامُ الصَّادِقُ (عَلَيْهِ السَّلَامُ): «مَنْ زَارَ الْحُسَيْنَ (عَلَيْهِ السَّلَامُ) عَارِفًا بِحَقِّهِ، يَأْتَمُّ بِهِ، غَفَرَ اللَّهُ لَهُ مَا تَقَدَّمَ مِنْ ذَنْبِهِ وَمَا تَأَخَّرَ».
الْمَصْدَرُ: كَامِلُ الزِّيَارَاتِ، الْبَابُ ٥٤؛ وَنُقِلَ فِي بِحَارِ الْأَنْوَارِ، الْجُزْءُ ١٠١، الصَّفْحَتَانِ ٢١-٢٢.

الْحَدِيثُ: ٤
قَالَ الْإِمَامُ الصَّادِقُ (عَلَيْهِ السَّلَامُ): «أَيُّمَا مُؤْمِنٍ زَارَ الْحُسَيْنَ (عَلَيْهِ السَّلَامُ) عَارِفًا بِحَقِّهِ فِي غَيْرِ عِيدٍ وَلَا عَرَفَةَ، كَتَبَ اللَّهُ لَهُ عِشْرِينَ حَجَّةً وَعِشْرِينَ عُمْرَةً مَبْرُورَاتٍ مُتَقَبَّلَاتٍ وَعِشْرِينَ غَزْوَةً مَعَ نَبِيٍّ مُرْسَلٍ أَوْ إِمَامِ عَدْلٍ».
الْمَصْدَرُ: كَامِلُ الزِّيَارَاتِ، الْبَابُ ٧٤، الْحَدِيثُ ١.

الْحَدِيثُ: ٥
قَالَ الْإِمَامُ الصَّادِقُ (عَلَيْهِ السَّلَامُ): «مَنْ أَتَى قَبْرَ الْحُسَيْنِ (عَلَيْهِ السَّلَامُ) عَارِفًا بِحَقِّهِ، كَانَ كَمَنْ حَجَّ ثَلَاثَ حِجَجٍ مَعَ رَسُولِ اللَّهِ (صَلَّى اللَّهُ عَلَيْهِ وَآلِهِ وَسَلَّمَ)».
الْمَصْدَرُ: كَامِلُ الزِّيَارَاتِ، الصَّفْحَةُ ١٤٠.

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
          title: tr('زيارة الإمام العباس (عليه السلام)'),
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
                Text(tr('القارئ: الشيخ شبر معله'), textAlign: TextAlign.center),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
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
                                const SnackBar(content: Text(tr('جاري تشغيل زيارة أبي الفضل العباس بصوت الشيخ شبر معله'))),
                              );
                            }
                          } catch (error) {
                            debugPrint('Abbas audio error: $error');
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text(tr('تعذر تشغيل التسجيل؛ تحقق من وجود الملف assets/shibr_maalla_abbas.mp3'))),
                              );
                            }
                          }
                        },
                        icon: const Icon(Icons.play_arrow, size: 22),
                        label: Text(tr('تشغيل الزيارة')),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          unawaited(tapFeedback());
                          await (audioHandler as AshuraAudioHandler).stop();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text(tr('تم إيقاف التشغيل'))),
                            );
                          }
                        },
                        icon: const Icon(Icons.stop_circle_outlined, size: 22),
                        label: Text(tr('إيقاف التشغيل')),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Theme.of(context).colorScheme.primary,
                          padding: const EdgeInsets.symmetric(vertical: 14),
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
    );
  }
}

class ListeningPage extends StatefulWidget {
  final double fontSize;
  const ListeningPage({super.key, required this.fontSize});

  static const List<Map<String, String>> readers = [
    {'name': 'الشيخ شـــــــبّر معلّــــــه', 'file': 'shibr_maalla.mp3'},
    {'name': 'الشيخ بـاقر المقـــــدسي', 'file': 'baqir_almaqdisi.mp3'},
    {'name': 'الرادود باسم الكربلائي', 'file': 'basim_alkarbalaei.mp3'},
    {'name': 'الرادود أحمد الفتلاوي', 'file': 'ahmed_alftlawi.mp3'},
    {'name': 'الرادود محمدباقر الخاقاني', 'file': 'mohammed_baqir_alkhaqani.mp3'},
    {'name': 'الرادود أبا ذر الحلواجي', 'file': 'aba_thar_alhelwachi.mp3'},
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
          SnackBar(content: Text(tr('تعذر تشغيل ${reader[')name']}؛ تحقق من وجود الملف في assets.')),
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
                        fontWeight: FontWeight.bold, fontSize: snapshot.data == null ? 24 : 16,
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
                            tooltip: tr('تأخير 10 ثوانٍ'),
                            onPressed: duration == Duration.zero ? null : () { unawaited(tapFeedback()); handler.seekRelative(const Duration(seconds: -10)); },
                            icon: const Icon(Icons.replay_10, color: Colors.white, size: 22),
                          ),
                          IconButton(
                            tooltip: playing ? tr('إيقاف مؤقت') : tr('تشغيل'),
                            onPressed: duration == Duration.zero ? null : () { unawaited(tapFeedback()); playing ? handler.pause() : handler.play(); },
                            icon: Icon(playing ? Icons.pause_circle_filled : Icons.play_circle_fill, color: gold, size: 22),
                          ),
                          IconButton(
                            tooltip: tr('تقديم 10 ثوانٍ'),
                            onPressed: duration == Duration.zero ? null : () { unawaited(tapFeedback()); handler.seekRelative(const Duration(seconds: 10)); },
                            icon: const Icon(Icons.forward_10, color: Colors.white, size: 22),
                          ),
                          IconButton(
                            tooltip: tr('إيقاف التسجيل'),
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

String vocalizeHadithText(String source) {
  const replacements = <String, String>{
    'قال الباقر (عليه السلام) أو الصادق (عليه السلام):': 'قَالَ الْبَاقِرُ (عَلَيْهِ السَّلَامُ) أَوِ الصَّادِقُ (عَلَيْهِ السَّلَامُ):',
    'قال بعض الأصحاب عند الصادق (عليه السلام):': 'قَالَ بَعْضُ الْأَصْحَابِ عِنْدَ الصَّادِقِ (عَلَيْهِ السَّلَامُ):',
    'قال أمير المؤمنين (عليه السلام):': 'قَالَ أَمِيرُ الْمُؤْمِنِينَ (عَلَيْهِ السَّلَامُ):',
    'قال عبد السلام بن نعيم:': 'قَالَ عَبْدُ السَّلَامِ بْنُ نُعَيْمٍ:',
    'قال أبو حمزة الثمالي:': 'قَالَ أَبُو حَمْزَةَ الثُّمَالِيُّ:',
    'قال الصبّاح بن سيابة:': 'قَالَ الصَّبَّاحُ بْنُ سَيَابَةَ:',
    'قال أبو المغيرة:': 'قَالَ أَبُو الْمُغِيرَةِ:',
    'قال رجل عند الصادق (عليه السلام):': 'قَالَ رَجُلٌ عِنْدَ الصَّادِقِ (عَلَيْهِ السَّلَامُ):',
    'قال الرضا (عليه السلام):': 'قَالَ الرِّضَا (عَلَيْهِ السَّلَامُ):',
    'قال الصادق (عليه السلام):': 'قَالَ الصَّادِقُ (عَلَيْهِ السَّلَامُ):',
    'قال العسكري (عليه السلام):': 'قَالَ الْعَسْكَرِيُّ (عَلَيْهِ السَّلَامُ):',
    'قال أبو الحسن (عليه السلام):': 'قَالَ أَبُو الْحَسَنِ (عَلَيْهِ السَّلَامُ):',
    'قال (عليه السلام):': 'قَالَ (عَلَيْهِ السَّلَامُ):',
    'إذا ذكر أحد من الأنبياء فابدأ بالصلاة على محمّد ثمّ عليه': 'إِذَا ذُكِرَ أَحَدٌ مِنَ الْأَنْبِيَاءِ فَابْدَأْ بِالصَّلَاةِ عَلَى مُحَمَّدٍ ثُمَّ عَلَيْهِ',
    'وعلى جميع الأنبياء': 'وَعَلَى جَمِيعِ الْأَنْبِيَاءِ',
    'الصلاة على محمّد وعلى أهل بيته': 'الصَّلَاةُ عَلَى مُحَمَّدٍ وَعَلَى أَهْلِ بَيْتِهِ',
    'إنّما اتّخذ الله إبراهيم خليلاً': 'إِنَّمَا اتَّخَذَ اللَّهُ إِبْرَاهِيمَ خَلِيلًا',
    'لكثرة صلاته على محمّد وأهل بيته': 'لِكَثْرَةِ صَلَاتِهِ عَلَى مُحَمَّدٍ وَأَهْلِ بَيْتِهِ',
    'ارفعوا أصواتكم بالصلاة عليّ': 'ارْفَعُوا أَصْوَاتَكُمْ بِالصَّلَاةِ عَلَيَّ',
    'فإنّها تذهب بالنفاق': 'فَإِنَّهَا تَذْهَبُ بِالنِّفَاقِ',
    'من صلّى عليّ يوم الجمعة مائة مرّة': 'مَنْ صَلَّى عَلَيَّ يَوْمَ الْجُمُعَةِ مِائَةَ مَرَّةٍ',
    'قضى الله له ستّين حاجة': 'قَضَى اللَّهُ لَهُ سِتِّينَ حَاجَةً',
    'من صلّى عليّ مرة صلّى الله عليه عشراً': 'مَنْ صَلَّى عَلَيَّ مَرَّةً صَلَّى اللَّهُ عَلَيْهِ عَشْرًا',
    'من ذكرني فلم يصلّ عليّ فقد شقي': 'مَنْ ذَكَرَنِي فَلَمْ يُصَلِّ عَلَيَّ فَقَدْ شَقِيَ',
    'ما من دعاء إلّا بينه وبين السماء حجاب': 'مَا مِنْ دُعَاءٍ إِلَّا بَيْنَهُ وَبَيْنَ السَّمَاءِ حِجَابٌ',
    'ذكر الله عزّ وجلّ عبادة، وذكري عبادة': 'ذِكْرُ اللَّهِ عَزَّ وَجَلَّ عِبَادَةٌ، وَذِكْرِي عِبَادَةٌ',
    'من صلّى عليّ كلّ يوم ثلاث مرّات': 'مَنْ صَلَّى عَلَيَّ كُلَّ يَوْمٍ ثَلَاثَ مَرَّاتٍ',
    'من صلّى عليّ في كتاب': 'مَنْ صَلَّى عَلَيَّ فِي كِتَابٍ',
    'لم تزل الملائكة تستغفر له': 'لَمْ تَزَلِ الْمَلَائِكَةُ تَسْتَغْفِرُ لَهُ',

    'قال النبيّ (صلى الله عليه وآله وسلم):': 'قَالَ النَّبِيُّ (صَلَّى اللَّهُ عَلَيْهِ وَآلِهِ وَسَلَّمَ):',
    'قال رسول الله (صلى الله عليه وآله وسلم):': 'قَالَ رَسُولُ اللَّهِ (صَلَّى اللَّهُ عَلَيْهِ وَآلِهِ وَسَلَّمَ):',
    'قال النبيّ (صلى الله عليه وآله وسلم) في فضل شهر رمضان:': 'قَالَ النَّبِيُّ (صَلَّى اللَّهُ عَلَيْهِ وَآلِهِ وَسَلَّمَ) فِي فَضْلِ شَهْرِ رَمَضَانَ:',
    'من لم يقدر على ما يكفّر به ذنوبه': 'مَنْ لَمْ يَقْدِرْ عَلَى مَا يُكَفِّرُ بِهِ ذُنُوبَهُ',
    'فليكثر من الصلاة على محمّد وآله': 'فَلْيُكْثِرْ مِنَ الصَّلَاةِ عَلَى مُحَمَّدٍ وَآلِهِ',
    'فإنّها تهدم الذنوب هدماً': 'فَإِنَّهَا تَهْدِمُ الذُّنُوبَ هَدْمًا',
    'الصلاة على محمّد وآله تعدل': 'الصَّلَاةُ عَلَى مُحَمَّدٍ وَآلِهِ تَعْدِلُ',
    'أثقل ما يوضع في الميزان يوم القيامة': 'أَثْقَلُ مَا يُوضَعُ فِي الْمِيزَانِ يَوْمَ الْقِيَامَةِ',
    'كلّ دعاء محجوب عن السماء': 'كُلُّ دُعَاءٍ مَحْجُوبٌ عَنِ السَّمَاءِ',
    'حتّى يصلّى على محمّد وآله': 'حَتَّى يُصَلَّى عَلَى مُحَمَّدٍ وَآلِهِ',
    'من ذكرني فلم يصلّ عليّ': 'مَنْ ذَكَرَنِي فَلَمْ يُصَلِّ عَلَيَّ',
    'من أكثر فيه من الصلاة عليّ': 'مَنْ أَكْثَرَ فِيهِ مِنَ الصَّلَاةِ عَلَيَّ',
    'ذكر الله عزّ وجلّ عبادة': 'ذِكْرُ اللَّهِ عَزَّ وَجَلَّ عِبَادَةٌ',
    'الصلاة من الله عزّ وجلّ رحمة': 'الصَّلَاةُ مِنَ اللَّهِ عَزَّ وَجَلَّ رَحْمَةٌ',
    'ومن الملائكة تزكية': 'وَمِنَ الْمَلَائِكَةِ تَزْكِيَةٌ',
    'ومن الناس دعاء': 'وَمِنَ النَّاسِ دُعَاءٌ',
    'اللّهمّ صلّ على محمّد وآل محمّد': 'اللَّهُمَّ صَلِّ عَلَى مُحَمَّدٍ وَآلِ مُحَمَّدٍ',
    'صلّى الله على محمّد وآله': 'صَلَّى اللَّهُ عَلَى مُحَمَّدٍ وَآلِهِ',
  };
  var result = source;
  for (final entry in replacements.entries) {
    result = result.replaceAll(entry.key, entry.value);
  }
  return result;
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

class _TasbeehPageState extends State<TasbeehPage> with SingleTickerProviderStateMixin {
  static const List<String> zahraPhrases = [
    'اللَّهُ أَكْبَرُ',
    'الْحَمْدُ لِلَّهِ',
    'سُبْحَانَ اللَّهِ',
  ];
  static const List<int> zahraTargets = [34, 33, 33];

  int count = 0, target = 1000000, dailyCount = 0, dailyTarget = 100;
  int zahraCount = 0, zahraStageIndex = 0;
  bool zahraStageDone = false;
  bool loaded = false;
  bool isMillionMode = false;

  late final AnimationController _tapPulseController;
  late final Animation<double> _tapPulse;

  @override
  void initState() {
    super.initState();
    _tapPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 190),
    );
    _tapPulse = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.91),
        weight: 45,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.91, end: 1.0),
        weight: 55,
      ),
    ]).animate(CurvedAnimation(
      parent: _tapPulseController,
      curve: Curves.easeInOut,
    ));
    _load();
  }

  @override
  void dispose() {
    _tapPulseController.dispose();
    super.dispose();
  }

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
      zahraCount = prefs.getInt('zahra_tasbeeh_count') ?? 0;
      zahraStageIndex = (prefs.getInt('zahra_tasbeeh_stage') ?? 0)
          .clamp(0, zahraTargets.length - 1)
          .toInt();
      zahraStageDone = prefs.getBool('zahra_tasbeeh_stage_done') ?? false;
      loaded = true;
    });
  }

  Future<void> _incrementZahra() async {
    if (!loaded) return;
    if (zahraStageDone) {
      await _advanceZahraStage();
      return;
    }
    final stageTarget = zahraTargets[zahraStageIndex];
    setState(() {
      zahraCount++;
      if (zahraCount >= stageTarget) {
        zahraCount = stageTarget;
        zahraStageDone = true;
      }
    });
    if (zahraStageDone) {
      await HapticFeedback.heavyImpact();
    } else {
      await HapticFeedback.lightImpact();
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('zahra_tasbeeh_count', zahraCount);
    await prefs.setInt('zahra_tasbeeh_stage', zahraStageIndex);
    await prefs.setBool('zahra_tasbeeh_stage_done', zahraStageDone);
  }

  Future<void> _advanceZahraStage() async {
    if (!zahraStageDone) return;
    final finishedAll = zahraStageIndex == zahraTargets.length - 1;
    setState(() {
      zahraCount = 0;
      zahraStageDone = false;
      zahraStageIndex = finishedAll ? 0 : zahraStageIndex + 1;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('zahra_tasbeeh_count', 0);
    await prefs.setInt('zahra_tasbeeh_stage', zahraStageIndex);
    await prefs.setBool('zahra_tasbeeh_stage_done', false);
    if (finishedAll && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(tr('أتممت تسبيح الزهراء (ع)، تقبّل الله أعمالكم.'))),
      );
    }
  }

  Future<void> _resetZahra() async {
    setState(() {
      zahraCount = 0;
      zahraStageIndex = 0;
      zahraStageDone = false;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('zahra_tasbeeh_count', 0);
    await prefs.setInt('zahra_tasbeeh_stage', 0);
    await prefs.setBool('zahra_tasbeeh_stage_done', false);
    await HapticFeedback.mediumImpact();
  }

  Future<void> _increment() async {
    if (!loaded) return;
    unawaited(tapFeedback());
    setState(() {
      count++;
      dailyCount++;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('tasbeeh_salawat_count', count);
    await prefs.setInt('tasbeeh_daily_count', dailyCount);
  }

  String _millionChallengeTitle() {
    final milestone = (count ~/ 1000000) + 1;
    if (milestone == 1) return 'تَحَدِّي الْمِلْيُونِ صَلَاةً عَلَى مُحَمَّدٍ وَآلِ مُحَمَّدٍ';
    if (milestone == 2) return 'تَحَدِّي الْمِلْيُونَيْنِ صَلَاةً عَلَى مُحَمَّدٍ وَآلِ مُحَمَّدٍ';
    if (milestone == 3) return 'تَحَدِّي ثَلَاثَةِ مَلَايِينَ صَلَاةً عَلَى مُحَمَّدٍ وَآلِ مُحَمَّدٍ';
    if (milestone >= 1000) return 'تَحَدِّي الْمِلْيَارِ صَلَاةً عَلَى مُحَمَّدٍ وَآلِ مُحَمَّدٍ';
    return 'تَحَدِّي $milestone مِلْيُونٍ صَلَاةً عَلَى مُحَمَّدٍ وَآلِ مُحَمَّدٍ';
  }

  String _formatCount(int value) => value.toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (match) => ',',
  );

  Future<void> _reset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('إعادة عدّاد الصلاة')),
        content: Text(tr('هل تريد تصفير العدد الكلي والورد اليومي للصلاة؟')),
        actions: [
          TextButton(
            onPressed: () {
              unawaited(tapFeedback());
              Navigator.pop(context, false);
            },
            child: Text(tr('إلغاء')),
          ),
          ElevatedButton(
            onPressed: () {
              unawaited(tapFeedback());
              Navigator.pop(context, true);
            },
            child: Text(tr('تصفير')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      count = 0;
      dailyCount = 0;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('tasbeeh_salawat_count', 0);
    await prefs.setInt('tasbeeh_daily_count', 0);
  }

  Future<void> _customDailyTarget() async {
    final controller = TextEditingController(text: dailyTarget.toString());
    final value = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('تحديد الورد اليومي')),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'عدد الصلوات اليومي'),
        ),
        actions: [
          TextButton(
            onPressed: () {
              unawaited(tapFeedback());
              Navigator.pop(context);
            },
            child: Text(tr('إلغاء')),
          ),
          ElevatedButton(
            onPressed: () {
              unawaited(tapFeedback());
              final parsed = int.tryParse(controller.text.trim());
              if (parsed != null && parsed > 0) Navigator.pop(context, parsed);
            },
            child: Text(tr('حفظ')),
          ),
        ],
      ),
    );
    if (value == null) return;
    setState(() => dailyTarget = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('tasbeeh_daily_target', value);
  }

  Widget _buildTasbeehControl(Color accent, Color textColor, Color pageColor) {
    final isMillion = isMillionMode;
    final stageTarget = zahraTargets[zahraStageIndex];
    final millionProgressCount = count % 1000000;
    final currentProgress = isMillion
        ? (millionProgressCount / 1000000).clamp(0.0, 1.0).toDouble()
        : (zahraCount / stageTarget).clamp(0.0, 1.0).toDouble();
    final currentCount = isMillion ? millionProgressCount : zahraCount;
    final formattedCount = _formatCount(currentCount);
    final totalFormattedCount = _formatCount(count);
    final mutedText = textColor.withValues(alpha: 0.68);

    Widget modeButton(String label, bool selected, VoidCallback onTap) {
      return Expanded(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            constraints: const BoxConstraints(minHeight: 34),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
            decoration: BoxDecoration(
              color: selected ? accent.withValues(alpha: 0.18) : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: accent.withValues(alpha: selected ? 0.85 : 0.30), width: selected ? 1.4 : 1),
            ),
            alignment: Alignment.center,
            child: Text(label, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: selected ? accent : textColor, fontSize: 11, fontWeight: FontWeight.bold, height: 1.15)),
          ),
        ),
      );
    }

    return Container(
      color: pageColor,
      padding: const EdgeInsets.fromLTRB(10, 5, 10, 5),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(tr('أَفْضَلُ الْأَعْمَالِ تَسْبِيحُ السَّيِّدَةِ فَاطِمَةَ الزَّهْرَاءِ (عَلَيْهَا السَّلَامُ) وَالصَّلَاةُ عَلَى مُحَمَّدٍ وَآلِ مُحَمَّدٍ'),
            textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.bold, height: 1.25)),
          const SizedBox(height: 5),
          ScaleTransition(
            scale: _tapPulse,
            child: InkWell(
              onTap: () {
                unawaited(_tapPulseController.forward(from: 0));
                if (isMillion) {
                  _increment();
                } else {
                  _incrementZahra();
                }
              },
              customBorder: const CircleBorder(),
              child: SizedBox(
                width: 116, height: 116,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CircularProgressIndicator(value: currentProgress, strokeWidth: 7,
                    backgroundColor: textColor.withValues(alpha: 0.12),
                    valueColor: AlwaysStoppedAnimation<Color>(accent)),
                  Center(
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      FittedBox(fit: BoxFit.scaleDown,
                        child: Text(formattedCount, style: TextStyle(color: textColor, fontSize: 27, fontWeight: FontWeight.bold))),
                      Text(isMillion ? 'مِنْ مِلْيُونٍ' : 'مِنْ $stageTarget', style: TextStyle(color: mutedText, fontSize: 10)),
                      if (!isMillion) Text(zahraPhrases[zahraStageIndex], style: TextStyle(color: accent, fontSize: 10, fontWeight: FontWeight.bold)),
                    ]),
                  ),
                ],
              ),
              ),
            ),
          ),
          if (isMillion)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(tr('الْعَدَدُ الْكُلِّيُّ: $totalFormattedCount'),
                textAlign: TextAlign.center,
                style: TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          const SizedBox(height: 6),
          if (isMillion)
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(tr('الوِرْدُ اليَوْمِيُّ: ${dailyCount} / ${dailyTarget}'), style: TextStyle(color: mutedText, fontSize: 11, fontWeight: FontWeight.bold)),
              IconButton(visualDensity: VisualDensity.compact, constraints: const BoxConstraints.tightFor(width: 28, height: 25),
                padding: EdgeInsets.zero, tooltip: tr('تحديد الورد اليومي'), onPressed: _customDailyTarget,
                icon: Icon(Icons.flag_outlined, color: accent, size: 17)),
            ]),
          Row(children: [
            modeButton('تَسْبِيحُ السَّيِّدَةِ فَاطِمَةَ الزَّهْرَاءِ (عَلَيْهَا السَّلَامُ)', !isMillion, () => setState(() => isMillionMode = false)),
            const SizedBox(width: 7),
            modeButton(_millionChallengeTitle(), isMillion, () => setState(() => isMillionMode = true)),
          ]),
          const SizedBox(height: 2),
          if (!isMillion)
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(zahraStageDone
                  ? 'اِسْتَمِرَّ بِالضَّغْطِ لِلِانْتِقَالِ إِلَى التَّسْبِيحِ التَّالِي'
                  : 'الْمَرْحَلَةُ ${zahraStageIndex + 1} مِنْ 3',
                textAlign: TextAlign.center,
                style: TextStyle(color: mutedText, fontSize: 10)),
            ]),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pageColor = isDark ? Colors.black : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black;
    final accent = Theme.of(context).colorScheme.primary;

    if (!loaded) {
      return Container(
        color: pageColor,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    return Container(
      color: pageColor,
      child: Column(
        children: [
          Expanded(
            flex: 1,
            child: _buildTasbeehControl(accent, textColor, pageColor),
          ),
          Expanded(
            flex: 2,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
              children: [
                const SizedBox(height: 5),
                const Text(
                  'أَحَادِيثٌ فِي فَضْلِ الصَّلَاةِ عَلَى مُحَمَّدٍ وَآلِ مُحَمَّدٍ',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: gold, fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'أَحَادِيثٌ فِي فَضْلِ الصَّلَاةِ عَلَى مُحَمَّدٍ وَآلِ مُحَمَّدٍ، وَأَنَّ الصَّلَاةَ عَلَيْهِمْ تُكَفِّرُ الذُّنُوبَ وَتُثَقِّلُ الْمِيزَانَ، وَفِيمَا يُقَالُ عِنْدَ ذِكْرِ الْأَنْبِيَاءِ، وَعِلَّةِ اتِّخَاذِ اللَّهِ إِبْرَاهِيمَ خَلِيلًا. هَذِهِ النُّصُوصُ مِنْ مَجْمُوعَةِ «جَوَاهِرِ الْبِحَارِ» الْمُقْتَبَسَةِ مِنْ «بِحَارِ الْأَنْوَارِ» لِلْعَلَّامَةِ الْمَجْلِسِيِّ، مَعَ إِبْقَاءِ أَرْقَامِهَا وَمَصَادِرِهَا كَمَا وَرَدَتْ فِي النَّصِّ الْمُرْسَلِ.',
                  textAlign: TextAlign.justify,
                  style: TextStyle(height: 1.8),
                ),
                const SizedBox(height: 10),
                ...List.generate(
                  tasbeehHadithTexts.length,
                  (index) => Card(
                    margin: const EdgeInsets.symmetric(vertical: 7),
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(color: accent.withValues(alpha: 0.8), width: 1.2),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'الحديث: ${index + 1}  |  ترتيب جواهر البحار: ${9455 + index}',
                            textAlign: TextAlign.right,
                            style: TextStyle(color: accent, fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const Divider(),
                          SelectableText(
                            vocalizeHadithText(tasbeehHadithTexts[index]),
                            textAlign: TextAlign.justify,
                            style: TextStyle(fontSize: widget.fontSize - 2, height: 1.8, fontFamily: 'AmiriQuran'),
                          ),
                          const SizedBox(height: 9),
                          Text(
                            'المصدر الأصلي: ${tasbeehHadithOriginalSources[index]}',
                            style: const TextStyle(color: Colors.grey, height: 1.6),
                          ),
                          Text(
                            'المصدر من بحار الأنوار: ج ٩١، ص ${tasbeehHadithPages[index]}',
                            style: const TextStyle(color: Colors.grey, height: 1.6),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsPage extends StatefulWidget {
  final bool isDarkMode;
  final double fontSize;
  final String selectedFont;
  final String selectedColor;
  final String selectedLanguage;
  final Function(String) onChangeLanguage;
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
    required this.selectedLanguage,
    required this.onChangeLanguage,
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
  late String localLanguage;

  @override
  void initState() {
    super.initState();
    localFont = widget.selectedFont;
    localColor = widget.selectedColor;
    localFontSize = widget.fontSize;
    localLanguage = widget.selectedLanguage;
  }

  @override
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedFont != widget.selectedFont) localFont = widget.selectedFont;
    if (oldWidget.selectedColor != widget.selectedColor) localColor = widget.selectedColor;
    if (oldWidget.fontSize != widget.fontSize) localFontSize = widget.fontSize;
    if (oldWidget.selectedLanguage != widget.selectedLanguage) localLanguage = widget.selectedLanguage;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('الإعدادات'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.language, color: gold),
                    title: Text(tr('لغة التطبيق')),
                    subtitle: Text(languageName(localLanguage)),
                  ),
                  DropdownButtonFormField<String>(
                    value: localLanguage,
                    isExpanded: true,
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'ar', child: Text(tr('العربية'))),
                      DropdownMenuItem(value: 'fa', child: Text(tr('فارسی'))),
                      DropdownMenuItem(value: 'en', child: Text('English')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      unawaited(tapFeedback());
                      setState(() => localLanguage = value);
                      widget.onChangeLanguage(value);
                    },
                  ),
                ],
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.alarm, color: gold),
              title: Text(tr('المنبهات')),
              subtitle: Text(tr('تنبيه الزيارة: هل زرت الإمام الحسين؟ وتنبيه الصلاة: هل صليت على محمد وآل محمد؟')),
              trailing: const Icon(Icons.chevron_left),
              onTap: () { unawaited(tapFeedback()); Navigator.push(context, MaterialPageRoute(builder: (_) => const ReminderManagerPage())); },
            ),
          ),
          Card(
            child: SwitchListTile(
              secondary: const Icon(Icons.dark_mode, color: gold),
              title: Text(tr('الوضع الليلي')),
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
                    title: Text(tr('تغيير لون التطبيق')),
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
                    title: Text(tr('نوع الخط')),
                  ),
                  DropdownButtonFormField<String>(
                    value: localFont,
                    isExpanded: true,
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem<String>(value: 'Amiri', child: Text(tr('Amiri - خط النسخ'))),
                      DropdownMenuItem<String>(value: 'AmiriQuran', child: Text(tr('Amiri Quran - الخط القرآني'))),
                      DropdownMenuItem<String>(value: 'NotoNaskhArabic', child: Text(tr('Noto Naskh Arabic - النسخ العربي'))),
                      DropdownMenuItem<String>(value: 'Cairo', child: Text(tr('Cairo - خط كايرو'))),
                      DropdownMenuItem<String>(value: 'ArefRuqaa', child: Text(tr('Aref Ruqaa - خط الرقعة'))),
                      DropdownMenuItem<String>(value: 'Tajawal', child: Text(tr('Tajawal - خط تجوال الواضح'))),
                      DropdownMenuItem<String>(value: 'NotoKufiArabic', child: Text(tr('Noto Kufi Arabic - الخط الكوفي الواضح'))),
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
              title: Text(tr('حجم الخط')),
              subtitle: Text(tr('الحجم الحالي: ${localFontSize.toInt()}')),
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
              title: Text(tr('حول التطبيق')),
              subtitle: Text(tr('معلومات التطبيق والإهداء وحقوق التصميم')),
              trailing: const Icon(Icons.chevron_left),
              onTap: () { unawaited(tapFeedback()); Navigator.push(context, MaterialPageRoute(builder: (_) => const AboutAppPage())); },
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.campaign_outlined, color: gold),
              title: Text(tr('التحديثات')),
              subtitle: Text(tr('آخر الأخبار والتنبيهات والإضافات الجديدة للتطبيق')),
              trailing: const Icon(Icons.chevron_left),
              onTap: () {
                unawaited(tapFeedback());
                Navigator.push(context, MaterialPageRoute(builder: (_) => const AppUpdatesPage()));
              },
            ),
          ),
        ],
      ),
    );
  }
}

class AppUpdatesPage extends StatefulWidget {
  const AppUpdatesPage({super.key});
  @override
  State<AppUpdatesPage> createState() => _AppUpdatesPageState();
}

class _AppUpdatesPageState extends State<AppUpdatesPage> {
  bool loading = true;
  String? error;
  String currentVersion = '...';
  String? latestVersion;
  String? releaseTitle;
  String? releaseNotes;
  String? apkUrl;
  String? releaseUrl;
  DateTime? publishedAt;

  @override
  void initState() {
    super.initState();
    checkForUpdates();
  }

  Future<void> checkForUpdates() async {
    if (mounted) setState(() { loading = true; error = null; });
    HttpClient? client;
    try {
      final info = await PackageInfo.fromPlatform();
      currentVersion = '${info.version}+${info.buildNumber}';
      client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
      final request = await client.getUrl(Uri.parse(
        'https://api.github.com/repos/akaml7143-source/ziyarat-ashura/releases/latest',
      ));
      request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      request.headers.set(HttpHeaders.userAgentHeader, 'Ziyarat-Ashura-App');
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode == 404) {
        throw Exception('لم يُنشر إصدار رسمي على GitHub Releases حتى الآن.');
      }
      if (response.statusCode != 200) {
        throw Exception('تعذر فحص التحديثات (HTTP ${response.statusCode}).');
      }
      final data = jsonDecode(body) as Map<String, dynamic>;
      final tag = (data['tag_name'] as String? ?? '').trim();
      final assets = (data['assets'] as List<dynamic>? ?? const []);
      final apk = assets.cast<Map<String, dynamic>>().where((item) {
        final name = (item['name'] as String? ?? '').toLowerCase();
        return name.endsWith('.apk');
      }).firstOrNull;
      latestVersion = tag.isEmpty ? null : tag.replaceFirst(RegExp(r'^v'), '');
      releaseTitle = (data['name'] as String?)?.trim();
      releaseNotes = (data['body'] as String?)?.trim();
      final dateValue = data['published_at'] as String?;
      publishedAt = dateValue == null ? null : DateTime.tryParse(dateValue)?.toLocal();
      apkUrl = apk?['browser_download_url'] as String?;
      releaseUrl = data['html_url'] as String?;
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      client?.close(force: true);
      if (mounted) setState(() => loading = false);
    }
  }

  List<int> _versionParts(String value) => value
      .split('+').first.split('.')
      .map((part) => int.tryParse(part.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
      .toList();

  bool get hasUpdate {
    if (latestVersion == null) return false;
    final current = _versionParts(currentVersion);
    final latest = _versionParts(latestVersion!);
    for (var i = 0; i < (current.length > latest.length ? current.length : latest.length); i++) {
      final a = i < current.length ? current[i] : 0;
      final b = i < latest.length ? latest[i] : 0;
      if (b != a) return b > a;
    }
    return false;
  }

  Future<void> openDownload() async {
    final url = apkUrl ?? releaseUrl;
    if (url == null) return;
    final uri = Uri.tryParse(url);
    if (uri == null || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(tr('تعذر فتح رابط تنزيل التحديث.'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateText = publishedAt == null ? '' :
      '${publishedAt!.year}/${publishedAt!.month.toString().padLeft(2, '0')}/${publishedAt!.day.toString().padLeft(2, '0')}';
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('التحديثات')),
        actions: [IconButton(
          tooltip: tr('فحص التحديثات'),
          onPressed: loading ? null : checkForUpdates,
          icon: const Icon(Icons.refresh),
        )],
      ),
      body: loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text(tr('حالة التطبيق'), style: TextStyle(color: gold, fontSize: 19, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    Text(tr('الإصدار المثبّت: $currentVersion'), textAlign: TextAlign.right),
                    if (latestVersion != null) ...[
                      const SizedBox(height: 6),
                      Text(tr('أحدث إصدار: $latestVersion'), textAlign: TextAlign.right),
                    ],
                    const SizedBox(height: 12),
                    if (error != null)
                      Text(error!, textAlign: TextAlign.right, style: const TextStyle(color: Colors.orangeAccent))
                    else if (hasUpdate)
                      Text(tr('يتوفر تحديث جديد للتطبيق.'), textAlign: TextAlign.right,
                        style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold))
                    else
                      Text(tr('أنت تستخدم أحدث إصدار منشور.'), textAlign: TextAlign.right),
                    const SizedBox(height: 12),
                    if (hasUpdate && (apkUrl != null || releaseUrl != null))
                      ElevatedButton.icon(
                        onPressed: openDownload,
                        icon: const Icon(Icons.download),
                        label: Text(tr('تنزيل التحديث')),
                      ),
                    if (releaseUrl != null && !hasUpdate)
                      TextButton(onPressed: openDownload, child: Text(tr('فتح صفحة الإصدار على GitHub'))),
                  ]),
                ),
              ),
              if (releaseTitle != null || releaseNotes != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Text(releaseTitle?.isNotEmpty == true ? releaseTitle! : 'تفاصيل آخر تحديث',
                        textAlign: TextAlign.right,
                        style: const TextStyle(color: gold, fontSize: 18, fontWeight: FontWeight.bold)),
                      if (dateText.isNotEmpty) Text(dateText, textAlign: TextAlign.right,
                        style: const TextStyle(color: Colors.grey, fontSize: 12)),
                      const Divider(),
                      Text(releaseNotes?.isNotEmpty == true ? releaseNotes! : 'لا توجد تفاصيل مضافة لهذا الإصدار.',
                        textAlign: TextAlign.right, style: const TextStyle(height: 1.7)),
                    ]),
                  ),
                ),
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text(
                  'يتم تنزيل ملف APK من صفحة الإصدار الرسمية. بعد اكتمال التنزيل، افتح الملف ووافق على التثبيت من Android. لن تُحذف بيانات التطبيق عند تثبيت تحديث موقّع بالمفتاح نفسه.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey, height: 1.6),
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
        content: Text(tr('فعّل إشعارات التطبيق من إعدادات الهاتف حتى تظهر التنبيهات.')),
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
    final prefs = await SharedPreferences.getInstance();
    final savedSalawatEnabled = prefs.getBool('salawat_reminder_enabled') ?? false;
    final savedSalawatHour = prefs.getInt('salawat_reminder_hour') ?? 9;
    final savedSalawatMinute = prefs.getInt('salawat_reminder_minute') ?? 0;
    if (canSchedule) {
      for (final reminder in saved.where((item) => item.enabled)) {
        await scheduleReminder(reminder);
      }
      await scheduleSalawatReminder(enabled: savedSalawatEnabled,
        hour: savedSalawatHour, minute: savedSalawatMinute);
    }
    if (!mounted) return;
    setState(() {
      reminders = saved;
      salawatEnabled = savedSalawatEnabled;
      salawatHour = savedSalawatHour;
      salawatMinute = savedSalawatMinute;
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
    try {
      await scheduleSalawatReminder(enabled: nextEnabled, hour: nextHour, minute: nextMinute);
    } catch (error) {
      await prefs.setBool('salawat_reminder_enabled', salawatEnabled);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('تعذرت جدولة منبّه الصلاة: $error'))));
      return;
    }
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(tr('يرجى السماح بإشعارات التطبيق من إعدادات الهاتف.'))));
      return false;
    }
    if (!exactAlarmsAllowed && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(tr('لم يُفعّل التوقيت الدقيق؛ ستعمل الإشعارات بالتوقيت المتاح وقد تتأخر قليلاً.'))));
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
        const SnackBar(content: Text(tr('يمكنك إضافة خمسة أوقات كحد أقصى لزيارة عاشوراء.'))),
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
      appBar: AppBar(title: Text(tr('المنبهات'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: reminders.length >= 5 ? null : () { unawaited(tapFeedback()); addReminder(); },
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_alarm),
        label: Text(tr('إضافة منبّه')),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
              children: [
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.notifications_active, color: gold),
                    title: Text(tr('اختبار الإشعار المنبثق')),
                    subtitle: Text(tr('أرسل إشعاراً تجريبياً الآن للتحقق من الصلاحيات')),
                    onTap: () async {
                      unawaited(tapFeedback());
                      if (!await ensurePermissions()) return;
                      await showReminderTestNotification();
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(tr('أُرسل الاختبار. إذا لم يظهر كنافذة منبثقة، فعّل الإشعارات المنبثقة وإشعارات شاشة القفل من إعدادات الهاتف.'))));
                    },
                  ),
                ),
                Card(
                  child: Column(
                    children: [
                      SwitchListTile(
                        secondary: const Icon(Icons.volunteer_activism, color: gold),
                        title: Text(tr('منبه الصلاة على محمد وآل محمد')),
                        subtitle: Text(tr('هل صليت على محمد وآل محمد هذا اليوم؟')),
                        value: salawatEnabled,
                        onChanged: (value) { unawaited(tapFeedback()); updateSalawatReminder(enabled: value); },
                      ),
                      ListTile(
                        leading: const Icon(Icons.access_time, color: gold),
                        title: Text(tr('وقت منبّه الصلاة على محمد وآل محمد')),
                        subtitle: Text(TimeOfDay(hour: salawatHour, minute: salawatMinute).format(context)),
                        trailing: const Icon(Icons.edit, color: gold),
                        onTap: () { unawaited(tapFeedback()); chooseSalawatTime(); },
                      ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(tr('منبّهات زيارة عاشوراء (حتى خمسة أوقات)'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: gold, fontWeight: FontWeight.bold)),
                ),
                if (reminders.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(tr('لا توجد منبّهات للزيارة حالياً. أضف منبّهاً وحدد وقته وأيام تكراره.'),
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
                              PopupMenuItem(value: 'edit', child: Text(tr('تعديل'))),
                              PopupMenuItem(value: 'delete', child: Text(tr('حذف'))),
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
      title: Text(tr('إعداد المنبّه')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.access_time, color: gold),
              title: Text(tr('وقت التنبيه')),
              subtitle: Text(time.format(context)),
              onTap: () async {
                unawaited(tapFeedback());
                final picked = await showTimePicker(context: context, initialTime: time);
                if (picked != null) setState(() { hour = picked.hour; minute = picked.minute; });
              },
            ),
            const Divider(),
            const Align(alignment: Alignment.centerRight, child: Text(tr('أيام التكرار'), style: TextStyle(fontWeight: FontWeight.bold))),
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
        TextButton(onPressed: () { unawaited(tapFeedback()); Navigator.pop(context); }, child: Text(tr('إلغاء'))),
        ElevatedButton(
          onPressed: days.isEmpty ? null : () { unawaited(tapFeedback()); Navigator.pop(context, widget.reminder.copyWith(hour: hour, minute: minute, weekdays: days)); },
          child: Text(tr('حفظ')),
        ),
      ],
    );
  }
}

class AboutAppPage extends StatelessWidget {
  const AboutAppPage({super.key});

  static const String aboutText = '''زِيَارَةُ عَاشُورَاءَ

تَطْبِيقٌ إِسْلَامِيٌّ يَهْدِفُ إِلَى إِحْيَاءِ ذِكْرَى الْإِمَامِ الْحُسَيْنِ بْنِ عَلِيٍّ (عَلَيْهِ السَّلَامُ)، وَنَشْرِ فَضَائِلِ زِيَارَةِ عَاشُورَاءَ، وَتَعْزِيزِ الِارْتِبَاطِ بِسَيِّدِ الشُّهَدَاءِ وَأَهْلِ بَيْتِهِ (عَلَيْهِمُ السَّلَامُ).

يَضُمُّ التَّطْبِيقُ نَصَّ زِيَارَةِ عَاشُورَاءَ وَفَضْلَهَا، وَزِيَارَةَ الْإِمَامِ الْعَبَّاسِ (عَلَيْهِ السَّلَامُ)، بِالْإِضَافَةِ إِلَى الِاسْتِمَاعِ لِلزِّيَارَةِ بِأَصْوَاتِ عَدَدٍ مِنَ الْقُرَّاءِ، مَعَ مَجْمُوعَةٍ مِنَ الْخَصَائِصِ الَّتِي تُسَهِّلُ الْقِرَاءَةَ وَالِاسْتِمَاعَ وَالتَّذْكِيرَ الْيَوْمِيَّ بِالزِّيَارَةِ.

● الإِهْدَاءُ ●

إِلَى الْإِمَامِ الْحُسَيْنِ بْنِ عَلِيٍّ (عَلَيْهِ السَّلَامُ)، وَإِلَى أَهْلِ بَيْتِهِ الْأَطْهَارِ (عَلَيْهِمُ السَّلَامُ)، وَمُحِبِّيهِ وَمُوَالِيهِ، نُهْدِي هَذَا الْعَمَلَ الْمُتَوَاضِعَ، رَاجِينَ مِنَ اللهِ تَعَالَى الْقَبُولَ وَالتَّوْفِيقَ لِخِدْمَةِ مُحَمَّدٍ وَآلِ مُحَمَّدٍ.

نَسْأَلُكُمْ
كَامِلُ الْكُمَيْتِيُّ
11/11/2026
جَمِيعُ الْحُقُوقِ مَحْفُوظَةٌ''';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('حَوْلَ التَّطْبِيقِ'))),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              child: SizedBox(
                width: constraints.maxWidth,
                height: constraints.maxHeight,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.center,
                  child: SizedBox(
                    width: constraints.maxWidth - 36,
                    child: Directionality(
                      textDirection: TextDirection.rtl,
                      child: Text(
                        aboutText,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 17,
                          height: 1.48,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'AmiriQuran',
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
