
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';

const Color gold = Color(0xFFFFD700);
const Color green = Color(0xFF1B4332);
const Color darkBackground = Color(0xFF121212);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
    });
  }

  Future<void> toggleTheme() async {
    setState(() => isDarkMode = !isDarkMode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('ashura_dark', isDarkMode);
  }

  Future<void> changeFontSize(double delta) async {
    setState(() {
      fontSize = (fontSize + delta).clamp(16.0, 32.0);
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('ashura_font', fontSize);
  }

  @override
  Widget build(BuildContext context) {
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
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Color(0xFF1F1F1F),
        ),
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
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Colors.white,
        ),
      ),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: HomeScreen(
          isDarkMode: isDarkMode,
          fontSize: fontSize,
          onToggleTheme: toggleTheme,
          onChangeFontSize: changeFontSize,
        ),
      ),
    );
  }
}

// الصفحة الرئيسية والتنقل

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
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'زيارة عاشوراء وفضلها',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            onPressed: () => widget.onChangeFontSize(-2),
            icon: const Icon(Icons.remove),
            tooltip: 'تصغير الخط',
          ),
          IconButton(
            onPressed: () => widget.onChangeFontSize(2),
            icon: const Icon(Icons.add),
            tooltip: 'تكبير الخط',
          ),
          IconButton(
            onPressed: widget.onToggleTheme,
            icon: Icon(
              widget.isDarkMode ? Icons.wb_sunny : Icons.nights_stay,
            ),
            tooltip: 'تغيير المظهر',
          ),
        ],
      ),
      body: IndexedStack(
        index: selectedIndex,
        children: pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: selectedIndex,
        onTap: (index) => setState(() => selectedIndex = index),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: gold,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.menu_book),
            label: 'الزيارة المباركة',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.auto_awesome),
            label: 'فضل الزيارة',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.place),
            label: 'الزيارة من بعيد',
          ),
        ],
      ),
    );
  }
}

// بطاقة النصوص

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
        side: highlight
            ? const BorderSide(color: gold, width: 1)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.bold,
                color: gold,
              ),
            ),
            const Divider(),
            SelectableText(
              content,
              style: TextStyle(
                fontSize: fontSize,
                height: 1.9,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// الزيارة المباركة

class ZiyaratPage extends StatelessWidget {
  final double fontSize;

  const ZiyaratPage({super.key, required this.fontSize});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SectionCard(
          title: '🌼 نية الزيارة 🌼',
          fontSize: fontSize,
          highlight: true,
          content:
              'بسم الله الرحمن الرحيم\n'
              'اللهم صل على محمد وآل محمد\n\n'
              'أزور سيدي ومولاي أبا عبد الله الحسين (عليه السلام) بالأصالة عن نفسي وبالنيابة عن صاحب العصر والزمان وعن والدي ووالد والدي وولدي وأخواتي وإخواني وجيراني وأقاربي وأعزائي وعن من قلدني الدعاء والزيارة، وجميع المؤمنين والمؤمنات الأحياء منهم والأموات قربة إلى الله تعالى.',
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'نص الزيارة الشريفة',
          fontSize: fontSize,
          content:
              'اللهم صل على محمد وآل محمد\n\n'
              'اَلسَّلامُ عَلَيْكَ يا أَبا عَبْدِاللهِ، اَلسَّلامُ عَلَيْكَ يَا بْنَ رَسُولِ اللهِ، اَلسَّلامُ عَلَيْكَ يَا بْنَ أَميرِ الْمُؤْمِنِينَ وَابْنَ سَيِّدِ الْوَصِيِّينَ، اَلسَّلامُ عَلَيْكَ يَا بْنَ فاطِمَةَ سَيِّدَةِ نِسَاءِ الْعَالَمِينَ، اَلسَّلامُ عَلَيْكَ يَا ثَارَ اللهِ وَابْنَ ثَأْرِهِ وَالْوِتْرَ الْمَوْتُورَ، اَلسَّلامُ عَلَيْكَ وَعَلَى الْأَرْواحِ الَّتِي حَلَّتْ بِفِنائِكَ، عَلَيْكُمْ مِنِّي جَمِيعاً سَلامُ اللهِ أَبَداً مَا بَقِيتُ وَبَقِيَ اللَّيْلُ وَالنَّهارُ...\n\n'
              '(لعن الله أمة أسست أساس الظلم والجور عليكم أهل البيت...)',
        ),
        const SizedBox(height: 16),
        CounterWidget(
          storageKey: 'ashura_lعن_counter',
          title: 'ثم تقول (100 مرّة):',
          phrase:
              'اَللّـهُمَّ الْعَنْ أَوَّلَ ظَالِمٍ ظَلَمَ حَقَّ مُحَمَّدٍ وَآلِ مُحَمَّدٍ وَآخِرَ تَابِعٍ لَهُ عَلَى ذلِكَ، اَللّـهُمَّ الْعَنِ الْعِصَابَةَ الَّتي جَاهَدَتِ الْحُسَيْنَ (عليه السلام) وَشايَعَتْ وَبايَعَتْ وَتابَعَتْ عَلى قَتْلِهِ، اَللّـهُمَّ الْعَنْهُمْ جَمِيعاً.',
          fontSize: fontSize,
        ),
        const SizedBox(height: 16),
        CounterWidget(
          storageKey: 'ashura_salam_counter',
          title: 'ثم تقول (100 مرّة):',
          phrase:
              'اَلسَّلامُ عَلَيْكَ يا أَبا عَبْدِاللهِ وَعَلَى الْأَرْواحِ الَّتي حَلَّتْ بِفِنائِكَ، عَلَيْكَ مِنّي سَلامُ اللهِ أَبَداً مَا بَقيتُ وَبَقِيَ اللَّيْلُ وَالنَّهَارُ وَلا جَعَلَهُ اللهُ آخِرَ الْعَهْدِ مِنّي لِزِيارَتِكُمْ، اَلسَّلامُ عَلَى الْحُسَيْنِ وَعَلَى عَلِيِّ بْنِ الْحُسَيْنِ وَعَلَى أَوْلادِ الْحُسَيْنِ وَعَلَى أَصْحابِ الْحُسَيْنِ.',
          fontSize: fontSize,
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'سجدة الزيارة',
          fontSize: fontSize,
          highlight: true,
          content:
              'ثم تسجد وتقُول:\n\n'
              'اَللّـهُمَّ لَكَ الْحَمْدُ حَمْدَ الشّاكِرينَ لَكَ عَلَى مُصَابِهِمْ، اَلْحَمْدُ للهِ عَلَى عَظيمِ رَزِيَّتي، اَللّـهُمَّ ارْزُقْني شَفاعَةَ الْحُسَيْنِ يَوْمَ الْوُرُودِ، وَثَبِّتْ لِي قَدَمَ صِدْقٍ عِنْدَكَ مَعَ الْحُسَيْنِ وَاَصْحابِ الْحُسَيْنِ اَلَّذينَ بَذَلُوا مُهَجَهُمْ دُونَ الْحُسَيْنِ (عليه السلام).',
        ),
      ],
    );
  }
}

// العداد التفاعلي

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
    if (!mounted) return;
    setState(() {
      count = prefs.getInt(widget.storageKey) ?? 0;
    });
  }

  Future<void> increment() async {
    if (count >= 100) return;

    setState(() => count++);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(widget.storageKey, count);

    if (count == 100) {
      try {
        final hasVibrator = await Vibration.hasVibrator();
        if (hasVibrator == true) {
          await Vibration.vibrate(duration: 500);
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
            Text(
              widget.title,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.bold,
                color: gold,
              ),
            ),
            const SizedBox(height: 12),
            SelectableText(
              widget.phrase,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: widget.fontSize,
                height: 1.8,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              '$count / 100',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: gold,
              ),
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: count / 100,
              minHeight: 8,
              borderRadius: BorderRadius.circular(10),
              color: count == 100 ? Colors.green : gold,
              backgroundColor: Colors.grey.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: count < 100 ? increment : null,
                  icon: const Icon(Icons.touch_app),
                  label: Text('العدد: $count'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        count == 100 ? Colors.green : green,
                    foregroundColor: Colors.white,
                  ),
                ),
                IconButton(
                  onPressed: reset,
                  icon: const Icon(Icons.refresh),
                  tooltip: 'إعادة العداد',
                ),
              ],
            ),
            if (count == 100)
              const Text(
                'أحسنت، اكتمل العدد',
                style: TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// فضل الزيارة

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
          content:
              'قال الإمام أبي جعفر (عليه السلام) لعلقمة:\n\n'
              '«يا علقمة إنك إذا قلت ذلك (أي زيارة عاشوراء) فقد دعوت بما يدعو به من زاره من الملائكة، وكتب الله لك بها ألف ألف حسنة ومحى عنك ألف ألف سيئة ورفع لك مائة ألف ألف درجة، وكنت كمن استشهد مع الحسين بن علي حتى تشاركهم في درجاتهم...»\n\n'
              '📚 المصدر: كامل الزيارات - ص 327',
          highlight: true,
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'أجر وثواب زائر الحسين (ع)',
          fontSize: fontSize,
          content:
              'روي عن الإمام الصادق (عليه السلام) إنه قال:\n\n'
              '«لو يعلم زائر الحسين عليه السلام ما يدخل على رسول الله [ص] وما يصل إليه من الفرح وإلى أمير المؤمنين وإلى فاطمة والأئمة والشهداء منا أهل البيت... فينصرف وما عليه ذنب وقد رفع له من الدرجات ما لا يناله المتشحط بدمه في سبيل الله...»\n\n'
              '📚 المصدر: كامل الزيارات / بحار الأنوار ج 98',
        ),
      ],
    );
  }
}

// الزيارة من بعيد

class FarVisitPage extends StatelessWidget {
  final double fontSize;

  const FarVisitPage({super.key, required this.fontSize});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SectionCard(
          title: 'فضل زيارة الحسين (ع) من بعيد',
          fontSize: fontSize,
          highlight: true,
          content:
              'عن الإمام جعفر الصادق (عليه السلام) أنه قال لسدير الصيرفي:\n\n'
              '«وما عليك يا سدير أن تزور قبر الحسين عليه السلام في كل جمعة خمس مرات أو في كل يوم مرة، قلت: جعلت فداك بيننا وبينه فراسخ كثيرة، فقال لي: اصعد فوق سطحك ثم التفت يمنة ويسرة، ثم ارفع رأسك إلى السماء ثم تنحو نحو القبر فتقول:\n\n'
              'السلام عليك يا أبا عبد الله، السلام عليك ورحمة الله وبركاته\n\n'
              'تكتب لك بذلك زَوْرَة، الزورة حجة وعمرة».\n\n'
              '📚 المصدر: من لا يحضره الفقيه ج 2 ص 599',
        ),
      ],
    );
  }
}

