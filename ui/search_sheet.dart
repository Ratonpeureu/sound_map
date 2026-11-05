import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../core/util.dart';

/// Retourne (lieu, démarrerItinéraire) ou null.
class SearchSheet extends StatefulWidget {
  const SearchSheet({super.key, required this.near});
  final LatLng near;
  @override
  State<SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<SearchSheet> {
  final _ctl = TextEditingController();
  Timer? _debounce;
  List<PlaceResult> _results = [];
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctl.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    if (v.trim().length < 3) {
      setState(() => _results = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 450), () => _search(v.trim()));
  }

  Future<void> _search(String q) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await context
          .read<ApiClient>()
          .searchPlaces(q, lat: widget.near.latitude, lon: widget.near.longitude);
      if (mounted) setState(() => _results = r);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: _ctl,
                autofocus: true,
                onChanged: _onChanged,
                textInputAction: TextInputAction.search,
                decoration: fieldDecoration(context, 'Rechercher un lieu, une adresse', Icons.search_rounded),
              ),
              if (_loading) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator(minHeight: 3)),
              if (_error != null)
                Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_error!, style: TextStyle(color: cs.error))),
              Flexible(
                child: ListView(shrinkWrap: true, children: [
                  for (final p in _results)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.place_outlined, color: cs.primary),
                      title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: p.address == null ? null : Text(p.address!, maxLines: 2, overflow: TextOverflow.ellipsis),
                      trailing: IconButton(
                        tooltip: 'Itinéraire',
                        icon: const Icon(Icons.directions_rounded),
                        onPressed: () => Navigator.pop(context, (p, true)),
                      ),
                      onTap: () => Navigator.pop(context, (p, false)),
                    ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}