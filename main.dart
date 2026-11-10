import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'state/roads_view_model.dart';
import 'app.dart';
import 'core/api.dart';
import 'core/config.dart';
import 'core/notifier.dart';
import 'state/account_controller.dart';
import 'state/missions_controller.dart';
import 'state/proposals_controller.dart';
import 'state/quota_controller.dart';
import 'state/recorder_controller.dart';
import 'state/reviews_controller.dart';
import 'state/session_controller.dart';
import 'state/tomtom_view_model.dart';
import 'state/view_models.dart';
import 'state/data_hub.dart';
import 'state/studies_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('fr_FR');
  final prefs = await SharedPreferences.getInstance();
  final notifier = Notifier();
  await notifier.init();

  final api = ApiClient(prefs.getString('server_url') ?? AppConfig.defaultApiBase);
  await api.tokens.load();
  final session = SessionController(api, prefs);

  final recorder = RecorderController(api, session, notifier);
  final proposals = ProposalsController(api, session, notifier);
  final mapVm = MapViewModel(api, session);
  final history = HistoryViewModel(api, session);
  final tomtom = TomTomViewModel(api, session);
  final quota = QuotaController(api, session);
  final roads = RoadsViewModel(api, session);
  final missions = MissionsController(api, session, notifier);
  final account = AccountController(api, session);
  final reviews = ReviewsController(api, session, notifier, account);
  final dataHub = DataHub(api, session);
  final studies = StudiesController(api, session, notifier);

  runApp(MultiProvider(
    providers: [
      Provider<ApiClient>.value(value: api),
      Provider<Notifier>.value(value: notifier),
      ChangeNotifierProvider<SessionController>.value(value: session),
      ChangeNotifierProvider<RecorderController>.value(value: recorder),
      ChangeNotifierProvider<ProposalsController>.value(value: proposals),
      ChangeNotifierProvider<MapViewModel>.value(value: mapVm),
      ChangeNotifierProvider<HistoryViewModel>.value(value: history),
      ChangeNotifierProvider<TomTomViewModel>.value(value: tomtom),
      ChangeNotifierProvider<QuotaController>.value(value: quota),
      ChangeNotifierProvider<MissionsController>.value(value: missions),
      ChangeNotifierProvider<RoadsViewModel>.value(value: roads),
      ChangeNotifierProvider<AccountController>.value(value: account),
      ChangeNotifierProvider<ReviewsController>.value(value: reviews),
      ChangeNotifierProvider<DataHub>.value(value: dataHub),
      ChangeNotifierProvider<StudiesController>.value(value: studies),

    ],
    child: const SunuApp(),
  ));
}