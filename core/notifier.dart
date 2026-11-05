import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class Notifier {
  final FlutterLocalNotificationsPlugin _p = FlutterLocalNotificationsPlugin();
  static const _idRecording = 1;
  int _seq = 100;

  Future<void> init() async {
    const android = AndroidInitializationSettings('ic_stat_sunusound');

    // ⚠️ v20+ : le paramètre est maintenant nommé `settings:`
    await _p.initialize(settings: const InitializationSettings(android: android));

    final impl =
        _p.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

    await impl?.createNotificationChannel(const AndroidNotificationChannel(
        'recording', 'Mesure en cours',
        description: "Progression d'une mesure sonore", importance: Importance.low));

    await impl?.createNotificationChannel(const AndroidNotificationChannel(
        'results', 'Résultats des mesures',
        description: "Envoi et validation de vos mesures", importance: Importance.defaultImportance));

    await impl?.createNotificationChannel(const AndroidNotificationChannel(
        'proposals', 'Propositions de mesure',
        description: 'Zones où une mesure vous est proposée', importance: Importance.high));
  }

  Future<void> requestPermission() async {
    final impl =
        _p.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await impl?.requestNotificationsPermission();
  }

  // ⚠️ v20+ : show(id:, title:, body:, notificationDetails:)
  Future<void> recordingProgress(int elapsed, int total, double db) => _p.show(
        id: _idRecording,
        title: 'Mesure en cours',
        body: '${db.toStringAsFixed(0)} dB(A) · $elapsed/$total s',
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            'recording',
            'Mesure en cours',
            channelDescription: "Progression d'une mesure sonore",
            importance: Importance.low,
            priority: Priority.low,
            ongoing: true,
            onlyAlertOnce: true,
            showProgress: true,
            maxProgress: total,
            progress: elapsed.clamp(0, total),
            autoCancel: false,
            icon: 'ic_stat_sunusound',
          ),
        ),
      );

  // ⚠️ v20+ : cancel(id: ...)
  Future<void> cancelProgress() => _p.cancel(id: _idRecording);

  Future<void> result(String title, String body) => _p.show(
        id: _seq++,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'results',
            'Résultats des mesures',
            channelDescription: 'Envoi et validation de vos mesures',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            icon: 'ic_stat_sunusound',
          ),
        ),
      );

  Future<void> proposal(String title, String body) => _p.show(
        id: _seq++,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'proposals',
            'Propositions de mesure',
            channelDescription: 'Zones où une mesure vous est proposée',
            importance: Importance.high,
            priority: Priority.high,
            icon: 'ic_stat_sunusound',
          ),
        ),
      );
}