import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:studio_core/core/strings.dart';
import 'package:studio_core/app/game_api.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/game_rules.dart';
import 'package:studio_core/app/studio_ui.dart';

import 'sand_engine.dart';
import 'sand_rules.dart';

final Map<StudioLook, ThemeData> _studioThemes = {};

class SandView extends StatefulWidget {
  final PlayContext ctx;
  const SandView({super.key, required this.ctx});

  @override
  State<SandView> createState() => _SandViewState();
}

class _SandViewState extends State<SandView> with SingleTickerProviderStateMixin {
  late SandLevel level;
  late SandGame game;
  late final Ticker _ticker;
  int? _selected;
  int? _hoverX;
  bool _flowing = false;
  int _flashLeft = 0;
  int _seconds = 0, _hints = 0;
  Timer? _timer;
  bool _ended = false;
  double _grain = 6;
  (int, int)? _hint;

  PlayContext get ctx => widget.ctx;

  @override
  void initState() {
    super.initState();
    level = SandRules().finalize(ctx.generated as GeneratedLevel<SandLevel>);
    final snap = ctx.resume['snap'];
    game = snap is String ? SandGame.restore(level, snap) : SandGame(level);
    _seconds = (ctx.resume['secs'] as num?)?.toInt() ?? 0;
    _hints = (ctx.resume['hints'] as num?)?.toInt() ?? 0;
    _ticker = createTicker(_frame);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_ended && mounted) setState(() => _seconds++);
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _persist() => ctx.saveResume({'snap': game.serialize(), 'secs': _seconds, 'hints': _hints});

  // Kum akışını kare kare göster.
  void _frame(Duration _) {
    if (_flashLeft > 0) {
      _flashLeft--;
      setState(() {});
      return;
    }
    var moved = 0;
    for (var k = 0; k < 2; k++) {
      moved += game.stepSand();
    }
    if (moved == 0) {
      final c = game.clearBridges();
      if (c > 0) {
        ctx.sfx(Sfx.combo);
        _flashLeft = 14;
        setState(() {});
        return;
      }
      _ticker.stop();
      _flowing = false;
      game.flash = {};
      game.afterSettle();
      _persist();
      if (game.over) _end();
    }
    setState(() {});
  }

  void _drop(int t, int cx) {
    if (_flowing || _ended) return;
    if (!game.drop(t, cx)) {
      ctx.sfx(Sfx.error);
      return;
    }
    ctx.sfx(Sfx.place);
    setState(() {
      _selected = null;
      _hint = null;
      _flowing = true;
    });
    _ticker.start();
  }

  void _end() {
    if (_ended) return;
    _ended = true;
    _timer?.cancel();
    final goal = level.target > 0;
    final won = goal ? game.won : game.score > 0;
    ctx.sfx(won ? Sfx.win : Sfx.lose);
    ctx.finish(RoundResult(
      won: won,
      score: game.score,
      stars: goal ? SandRules.stars(game) : (game.bridges >= 6 ? 3 : game.bridges >= 3 ? 2 : game.bridges > 0 ? 1 : 0),
      seconds: _seconds,
      moves: game.moves,
      hintsUsed: _hints,
      undosUsed: 0,
      gameStats: {'bridges': game.bridges, 'grains': game.grainsCleared},
    ));
  }

  Future<void> _useHint() async {
    if (!await ctx.requestHint()) return;
    _hints++;
    setState(() {
      _hint = game.bestMove();
      _selected = _hint?.$1;
    });
    _persist();
  }

  int _cellX(double dx, int w) => ((dx / (_grain * kG)) - w / 2).round().clamp(0, kCellsW - w);

  /// Oyun içi düğmeler, çipler ve yazılar onaylı koyu tasarımda (merkezin
  /// paleti); tahta çizimi kendi renklerini korur.
  @override
  Widget build(BuildContext context) {
    final look = StudioLook.of(context);
    return Theme(data: _studioThemes[look] ??= buildStudioTheme(look), child: Builder(builder: _build));
  }

  Widget _build(BuildContext context) {
    return LayoutBuilder(builder: (context, cons) {
      _grain = math.max(3.0, math.min((cons.maxWidth - 24) / kSW, cons.maxHeight * 0.62 / kSH));
      final w = _grain * kSW, h = _grain * kSH;
      final goal = level.target;
      final left = level.moveLimit > 0 ? level.moveLimit - game.moves : null;
      return Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(children: [
            Expanded(
              child: Text(
                  goal == 0
                      ? (Strings.tx(ctx.lang, 'Köprü: {0} · Puan: {1}', 'Bridges: {0} · Score: {1}', [game.bridges, game.score]))
                      : (Strings.tx(ctx.lang, 'Köprü: {0} / {1}', 'Bridges: {0} / {1}', [game.bridges, goal])),
                  style: Theme.of(context).textTheme.titleSmall),
            ),
            if (left != null) ...[const Icon(Icons.layers_outlined, size: 18), Text(' $left  ')],
            const Icon(Icons.timer_outlined, size: 18),
            Text(' ${_seconds ~/ 60}:${(_seconds % 60).toString().padLeft(2, '0')}'),
          ]),
        ),
        Center(
          child: DragTarget<int>(
            onMove: (d) {
              final box = context.findRenderObject() as RenderBox?;
              if (box == null) return;
              final p = game.tray[d.data];
              if (p == null) return;
              final local = d.offset.dx - (box.size.width - w) / 2;
              setState(() => _hoverX = _cellX(local, p.w));
            },
            onLeave: (_) => setState(() => _hoverX = null),
            onAcceptWithDetails: (d) {
              final x = _hoverX;
              setState(() => _hoverX = null);
              if (x != null) _drop(d.data, x);
            },
            builder: (context, cand, _) => GestureDetector(
              onTapUp: (d) {
                final s = _selected;
                final p = s == null ? null : game.tray[s];
                if (s == null || p == null) return;
                _drop(s, _cellX(d.localPosition.dx, p.w));
              },
              child: Semantics(
                label: 'board',
                child: SizedBox(width: w, height: h, child: CustomPaint(painter: _Painter(this, cand.isNotEmpty ? cand.first : null))),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            for (var t = 0; t < 3; t++) _trayPiece(t),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: IconButton.filledTonal(onPressed: _ended ? null : _useHint, icon: const Icon(Icons.lightbulb), tooltip: ctx.t('hint')),
        ),
      ]);
    });
  }

  Color colorOf(int c) => ctx.pieceColors[(c - 1) % ctx.pieceColors.length];

  Widget _trayPiece(int t) {
    final p = game.tray[t];
    const s = 16.0;
    if (p == null) return const SizedBox(width: s * 4, height: s * 4);
    final piece = Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _selected == t ? Theme.of(context).colorScheme.primary : Colors.transparent, width: 3),
      ),
      child: SizedBox(
        width: p.w * s,
        height: p.h * s,
        child: Stack(children: [
          for (final c in p.cells)
            Positioned(
              left: c[0] * s,
              top: c[1] * s,
              child: Container(
                width: s - 2,
                height: s - 2,
                decoration: BoxDecoration(color: colorOf(p.color), borderRadius: BorderRadius.circular(3)),
                alignment: Alignment.center,
                child: ctx.colorBlind ? Text(ctx.symbol(p.color - 1), style: const TextStyle(fontSize: 9)) : null,
              ),
            ),
        ]),
      ),
    );
    return Semantics(
      button: true,
      label: 'piece',
      child: GestureDetector(
        onTap: () => setState(() => _selected = _selected == t ? null : t),
        child: Draggable<int>(
          data: t,
          maxSimultaneousDrags: _flowing ? 0 : 1,
          feedback: Opacity(opacity: 0.8, child: piece),
          childWhenDragging: Opacity(opacity: 0.3, child: piece),
          child: piece,
        ),
      ),
    );
  }
}

class _Painter extends CustomPainter {
  final _SandViewState v;
  final int? dragging;
  _Painter(this.v, this.dragging);

  @override
  void paint(Canvas canvas, Size size) {
    final s = v._grain;
    final g = v.game;
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(10)),
        Paint()..color = Colors.black.withValues(alpha: 0.14));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, kDanger * s), Paint()..color = Colors.red.withValues(alpha: 0.07));
    final paints = <int, Paint>{};
    for (var i = 0; i < g.g.length; i++) {
      final c = g.g[i];
      if (c == 0) continue;
      final x = i % kSW, y = i ~/ kSW;
      // Taneye göre hafif ton farkı: kum dokusu.
      final shade = ((x * 7 + y * 13) % 5) * 0.035;
      final key = c * 10 + ((x * 7 + y * 13) % 5);
      final p = paints.putIfAbsent(key, () => Paint()..color = Color.lerp(v.colorOf(c), Colors.black, shade)!);
      canvas.drawRect(Rect.fromLTWH(x * s, y * s, s + 0.5, s + 0.5), p);
    }
    if (g.flash.isNotEmpty && v._flashLeft > 0) {
      final p = Paint()..color = Colors.white.withValues(alpha: v._flashLeft / 14 * 0.8);
      for (final i in g.flash) {
        canvas.drawRect(Rect.fromLTWH((i % kSW) * s, (i ~/ kSW) * s, s + 0.5, s + 0.5), p);
      }
    }
    final t = dragging ?? v._selected;
    final hx = v._hoverX ?? v._hint?.$2;
    if (t != null && hx != null && g.tray[t] != null) {
      final p = g.tray[t]!;
      canvas.drawRect(Rect.fromLTWH(hx * kG * s, 0, p.w * kG * s, size.height),
          Paint()..color = v.colorOf(p.color).withValues(alpha: 0.18));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
