import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load .env — Gemini key lives here, never in source code
  await dotenv.load(fileName: '.env');

  // Firebase init (required for Google + Facebook auth)
  await Firebase.initializeApp();

  // Timezone: use real device timezone (UTC+8 for Philippines)
  tz.initializeTimeZones();
  try {
    final String tzName = (await FlutterTimezone.getLocalTimezone()).identifier;
    tz.setLocalLocation(tz.getLocation(tzName));
  } catch (_) {
    tz.setLocalLocation(tz.UTC);
  }

  await _initNotifications();
  runApp(const ZamApp());
}

Future<void> _initNotifications() async {
  const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  await flutterLocalNotificationsPlugin.initialize(
    const InitializationSettings(android: androidSettings),
    onDidReceiveNotificationResponse: (NotificationResponse r) {
      debugPrint('Notification tapped: ${r.payload}');
    },
  );

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'zam_medicine_channel',
    'Medicine Reminders',
    description: 'Reminders to take your medicine on time',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
    enableLights: true,
  );

  final AndroidFlutterLocalNotificationsPlugin? androidPlugin =
      flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  await androidPlugin?.createNotificationChannel(channel);
  await androidPlugin?.requestNotificationsPermission();
  await androidPlugin?.requestExactAlarmsPermission();
}

class ZamApp extends StatelessWidget {
  const ZamApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zam',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF534AB7),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF534AB7),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      // Auth gate: show login if not signed in, home if signed in
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _SplashScreen();
          }
          if (snapshot.hasData) {
            return const HomeScreen();
          }
          return const LoginScreen();
        },
      ),
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Z',
              style: TextStyle(
                  fontSize: 56,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF534AB7))),
          SizedBox(height: 16),
          CircularProgressIndicator(
            color: Color(0xFF534AB7),
            strokeWidth: 2,
          ),
        ]),
      ),
    );
  }
}
