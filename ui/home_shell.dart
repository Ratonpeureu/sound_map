import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/notifier.dart';
import '../state/proposals_controller.dart';
import '../state/recorder_controller.dart';
import 'data_home_screen.dart';
import 'history_screen.dart';
import 'map_screen.dart';
import 'profile_screen.dart';
import 'record_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _i = 0;
  StreamSubscription<List<ConnectivityResult>>? _conn;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<Notifier>().requestPermission();
      final rec = context.read<RecorderController>();
      rec.refreshPending();
      rec.flushPending();
      context.read<ProposalsController>().startPolling();
    });
    _conn = Connectivity().onConnectivityChanged.listen((r) {
      if (!r.contains(ConnectivityResult.none) && mounted) {
        context.read<RecorderController>().flushPending();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      context.read<RecorderController>().flushPending();
      context.read<ProposalsController>().poll();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _conn?.cancel();
    super.dispose();
  }

  void _openRecord() {
    Navigator.of(context).push(PageRouteBuilder(
      pageBuilder: (_, __, ___) => const RecordScreen(),
      transitionsBuilder: (_, a, __, child) => FadeTransition(
          opacity: a,
          child: SlideTransition(
              position: Tween(begin: const Offset(0, 0.06), end: Offset.zero)
                  .animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
              child: child)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _i, children: const [MapScreen(), HistoryScreen(), DataHomeScreen(), ProfileScreen()]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openRecord,
        icon: const Icon(Icons.graphic_eq_rounded),
        label: const Text('Mesurer'),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _i,
        onDestinationSelected: (v) => setState(() => _i = v),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map_rounded), label: 'Carte'),
          NavigationDestination(icon: Icon(Icons.history_rounded), selectedIcon: Icon(Icons.history_toggle_off_rounded), label: 'Mesures'),
          NavigationDestination(icon: Icon(Icons.dataset_outlined), selectedIcon: Icon(Icons.dataset_rounded), label: 'Données'),
          NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: 'Moi'),
        ],
      ),
    );
  }
}