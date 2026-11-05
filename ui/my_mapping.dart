import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/api_ext.dart';
import '../core/config.dart';
import '../core/models_field.dart';
import '../core/util.dart';
import '../state/recorder_controller.dart';
import 'map_screen.dart' show noiseBandColor;
import 'widgets.dart';

MapOptions _fit(List<LatLng> ll, {required bool interactive}) {
  final b = LatLngBounds.fromPoints(ll);
  final tiny = (b.north - b.south) < 1e-4 && (b.east - b.west) < 1e-4;
  final flags = interactive ? InteractiveFlag.all & ~InteractiveFlag.rotate : InteractiveFlag.none;
  if (tiny) {
    return MapOptions(
        initialCenter: ll.first,
        initialZoom: 16,
        minZoom: 3,
        maxZoom: 19,
        interactionOptions: InteractionOptions(flags: flags));
  }
  return MapOptions(
      initialCameraFit: CameraFit.bounds(bounds: b, padding: const EdgeInsets.all(44), maxZoom: 16),
      minZoom: 3,
      maxZoom: 19,
      interactionOptions: InteractionOptions(flags: flags));
}

TileLayer _tiles() => TileLayer(
      urlTemplate: AppConfig.tileLight,
      subdomains: const ['a', 'b', 'c', 'd'],
      userAgentPackageName: AppConfig.packageName,
      maxNativeZoom: 19,
    );

PolygonLayer _cellLayer(List<ImpactCell> cells) => PolygonLayer(polygons: [
      for (final c in cells)
        Polygon(
          points: c.polygon,
          color: c.visible && c.mapLaeq != null
              ? noiseBandColor(c.mapLaeq!).withValues(alpha: 0.72)
              : Colors.grey.withValues(alpha: 0.22),
          borderColor: c.visible && c.mapLaeq != null ? noiseBandColor(c.mapLaeq!) : Colors.grey,
          borderStrokeWidth: 1.6,
        ),
    ]);

class _Dot extends StatelessWidget {
  const _Dot(this.p, {this.size = 24, this.selected = false});
  final ImpactPoint p;
  final double size;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final col = noiseBandColor(p.laeq);
    final txt = col.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: col,
        shape: BoxShape.circle,
        border: Border.all(color: selected ? Colors.black : qualityColor(p.status), width: selected ? 3 : 2.5),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4)],
      ),
      child: Text('${p.laeq.round()}',
          style: TextStyle(fontSize: size * 0.38, fontWeight: FontWeight.w800, color: txt)),
    );
  }
}

// ============================================================================
// Carte de profil
// ============================================================================
class MyMappingCard extends StatefulWidget {
  const MyMappingCard({super.key});
  @override
  State<MyMappingCard> createState() => _MyMappingCardState();
}

class _MyMappingCardState extends State<MyMappingCard> {
  Impact? _impact;
  String? _error;
  bool _loading = true;
  int _seen = -1;

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await context.read<ApiClient>().myImpact();
      if (mounted) setState(() {
        _impact = r;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final version = context.select<RecorderController, int>((r) => r.completedVersion);
    if (version != _seen) {
      _seen = version;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }
    final im = _impact;
    if (im == null) {
      return SoftCard(
        child: _loading
            ? const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
            : Row(children: [
                Icon(Icons.cloud_off_rounded, color: cs.error),
                const SizedBox(width: 12),
                Expanded(child: Text(_error ?? 'Indisponible', style: TextStyle(color: cs.error))),
                TextButton(onPressed: _load, child: const Text('Réessayer')),
              ]),
      );
    }
    if (im.points.isEmpty) {
      return SoftCard(
        child: Row(children: [
          Icon(Icons.map_outlined, color: cs.primary, size: 32),
          const SizedBox(width: 14),
          Expanded(
            child: Text('Aucune mesure sur les 30 derniers jours. Vos mesures apparaîtront ici avec leur effet sur la carte générale.',
                style: TextStyle(color: cs.onSurfaceVariant)),
          ),
        ]),
      );
    }
    final ll = [for (final p in im.points) LatLng(p.lat, p.lon)];
    final deltas = [for (final c in im.cells) if (c.delta != null) c.delta!];
    final avgDelta = deltas.isEmpty ? null : deltas.reduce((a, b) => a + b) / deltas.length;
    return SoftCard(
      padding: EdgeInsets.zero,
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => MyMappingScreen(impact: im))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: SizedBox(
            height: 210,
            child: Stack(children: [
              IgnorePointer(
                child: FlutterMap(
                  key: ValueKey('${im.total}_${im.onMap}'),
                  options: _fit(ll, interactive: false),
                  children: [
                    _tiles(),
                    _cellLayer(im.cells),
                    MarkerLayer(markers: [
                      for (final p in im.points.take(120))
                        Marker(point: LatLng(p.lat, p.lon), width: 20, height: 20, child: _Dot(p, size: 20)),
                    ]),
                  ],
                ),
              ),
              Positioned(right: 10, top: 10, child: StatusChip('Détails', cs.primary, icon: Icons.open_in_full_rounded)),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            StatusChip('${im.total} mesure(s) · 30 j', cs.primary, icon: Icons.place_rounded),
            StatusChip('${im.count('validated')} validée(s)', qualityColor('validated')),
            if (im.count('pending') > 0) StatusChip('${im.count('pending')} en évaluation', qualityColor('pending')),
            StatusChip('${im.visibleCells} zone(s) visibles sur la carte', const Color(0xFF0E9F9A), icon: Icons.layers_rounded),
            if (avgDelta != null)
              StatusChip('Effet moyen ${avgDelta >= 0 ? '+' : ''}${avgDelta.toStringAsFixed(1)} dB', cs.onSurfaceVariant),
          ]),
        ),
      ]),
    );
  }
}

// ============================================================================
// Écran détaillé
// ============================================================================
class MyMappingScreen extends StatefulWidget {
  const MyMappingScreen({super.key, required this.impact});
  final Impact impact;
  @override
  State<MyMappingScreen> createState() => _MyMappingScreenState();
}

class _MyMappingScreenState extends State<MyMappingScreen> {
  final MapController _ctl = MapController();
  String? _sel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final im = widget.impact;
    final ll = [for (final p in im.points) LatLng(p.lat, p.lon)];

    return Scaffold(
      appBar: AppBar(title: const Text('Ma cartographie')),
      body: Column(children: [
        Expanded(
          flex: 5,
          child: Stack(children: [
            FlutterMap(
              mapController: _ctl,
              options: _fit(ll, interactive: true),
              children: [
                _tiles(),
                _cellLayer(im.cells),
                MarkerLayer(markers: [
                  for (final p in im.points)
                    Marker(
                      point: LatLng(p.lat, p.lon),
                      width: _sel == p.id ? 36 : 26,
                      height: _sel == p.id ? 36 : 26,
                      child: GestureDetector(
                        onTap: () => setState(() => _sel = p.id),
                        child: _Dot(p, size: _sel == p.id ? 36 : 26, selected: _sel == p.id),
                      ),
                    ),
                ]),
              ],
            ),
            Positioned(
              left: 12,
              bottom: 12,
              child: SoftCard(
                glass: true,
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 12, height: 12, color: const Color(0xFFE8884F)),
                    const SizedBox(width: 6),
                    const Text('Zone visible sur la carte', style: TextStyle(fontSize: 10)),
                  ]),
                  const SizedBox(height: 3),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 12, height: 12, color: Colors.grey.withValues(alpha: 0.4)),
                    const SizedBox(width: 6),
                    const Text('Pas encore visible', style: TextStyle(fontSize: 10)),
                  ]),
                  const SizedBox(height: 3),
                  Text('Contour du point : statut de validation', style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant)),
                ]),
              ),
            ),
          ]),
        ),
        Expanded(
          flex: 4,
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
            Text(
              'La carte générale est la même pour tous : elle est calculée par le serveur à partir des mesures validées de tous les contributeurs. Voici la part de vos mesures.',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12, height: 1.35),
            ),
            const SectionTitle('Impact par zone'),
            for (final c in im.cells) _cellTile(cs, c, im),
            const SectionTitle('Mes mesures'),
            for (final p in im.points) _pointTile(cs, p),
          ]),
        ),
      ]),
    );
  }

  Widget _cellTile(ColorScheme cs, ImpactCell c, Impact im) {
    final String line1, line2;
    if (c.visible && c.mapLaeq != null) {
      line1 = 'Carte : ${c.mapLaeq!.toStringAsFixed(1)} dB(A) · ${c.mapCount} mesure(s) · ${c.mapDevices} contributeur(s)';
      final share = c.share == null ? '' : 'Votre part ${(c.share! * 100).round()} %';
      final d = c.delta == null ? '' : ' · effet de vos mesures ${c.delta! >= 0 ? '+' : ''}${c.delta!.toStringAsFixed(1)} dB';
      line2 = '$share$d';
    } else if (c.myValidated == 0) {
      line1 = 'Pas encore sur la carte';
      line2 = 'Vos ${c.myCount} mesure(s) attendent la validation.';
    } else {
      line1 = 'Pas encore sur la carte';
      line2 = 'Au moins ${im.minDevices} contributeurs sont nécessaires pour afficher cette zone.';
    }
    final col = c.visible && c.mapLaeq != null ? noiseBandColor(c.mapLaeq!) : Colors.grey;
    return SoftCard(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      onTap: () => _ctl.move(c.center, 16.5),
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: col.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(14)),
          child: Text(c.mapLaeq == null ? '–' : c.mapLaeq!.round().toString(),
              style: TextStyle(fontWeight: FontWeight.w800, color: col.computeLuminance() > 0.5 ? Colors.black87 : Colors.white)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(line1, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            if (line2.isNotEmpty) Text(line2, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
            Text('${c.myCount} mesure(s) de vous · ${c.myLaeq.toStringAsFixed(1)} dB(A) en moyenne énergétique',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11)),
          ]),
        ),
      ]),
    );
  }

  Widget _pointTile(ColorScheme cs, ImpactPoint p) {
    return SoftCard(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      onTap: () {
        setState(() => _sel = p.id);
        _ctl.move(LatLng(p.lat, p.lon), 17);
      },
      child: Row(children: [
        _Dot(p, size: 38, selected: _sel == p.id),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(fmtDateTime(p.measuredAt), style: const TextStyle(fontWeight: FontWeight.w700)),
            Text('${noiseLabel(p.laeq)} · ${fmtAgo(p.measuredAt)}', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
          ]),
        ),
        StatusChip(qualityLabel(p.status), qualityColor(p.status)),
      ]),
    );
  }
}