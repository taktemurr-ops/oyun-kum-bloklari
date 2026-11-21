import 'dart:convert';

import 'package:studio_core/core/level_plan.dart';
import 'package:studio_core/core/rng.dart';

/// Kum Blokları: bırakılan parça kum tanelerine dönüşür ve akar. Aynı renk
/// kum soldan sağa kesintisiz bir köprü kurarsa silinir.

const int kCellsW = 10;
const int kCellsH = 16;
const int kG = 3; // bir karede kaç tane (kenar)
const int kSW = kCellsW * kG; // 30
const int kSH = kCellsH * kG; // 48
const int kDanger = kG * 2; // en üst iki kare: taşma bölgesi

const List<List<List<int>>> kSandShapes = [
  [[0, 0], [1, 0], [0, 1], [1, 1]],
  [[0, 0], [1, 0], [2, 0], [3, 0]],
  [[0, 0], [0, 1], [0, 2], [0, 3]],
  [[0, 0], [1, 0], [2, 0], [1, 1]],
  [[0, 0], [0, 1], [0, 2], [1, 2]],
  [[1, 0], [1, 1], [1, 2], [0, 2]],
  [[1, 0], [2, 0], [0, 1], [1, 1]],
  [[0, 0], [1, 0], [1, 1], [2, 1]],
  [[0, 0], [1, 0], [2, 0]],
  [[0, 0], [0, 1], [0, 2]],
];

class SandPiece {
  final int shape, color;
  const SandPiece(this.shape, this.color);
  List<List<int>> get cells => kSandShapes[shape];
  int get w => cells.map((c) => c[0]).reduce((a, b) => a > b ? a : b) + 1;
  int get h => cells.map((c) => c[1]).reduce((a, b) => a > b ? a : b) + 1;
}

class SandLevel {
  final int colors;
  final int target; // köprü sayısı; 0 = hedefsiz
  final int seed, difficulty;
  final bool zen;
  final int moveLimit;
  const SandLevel({required this.colors, required this.target, required this.seed, required this.difficulty, required this.zen, this.moveLimit = 0});
  SandLevel withLimit(int l) => SandLevel(colors: colors, target: target, seed: seed, difficulty: difficulty, zen: zen, moveLimit: l);
}

SandLevel generateSandLevel(LevelSpec spec) {
  final d = spec.difficulty.clamp(1, 10);
  final zen = spec.mode == GameModeId.zen;
  final endless = zen || spec.mode == GameModeId.endless || spec.mode == GameModeId.timeAttack;
  return SandLevel(
    colors: d >= 7 ? 4 : 3,
    target: endless ? 0 : 1 + d ~/ 3,
    seed: mixSeed([spec.seed, 7070]),
    difficulty: d,
    zen: zen,
  );
}

class SandGame {
  final SandLevel level;
  List<int> g = List<int>.filled(kSW * kSH, 0);
  final List<SandPiece?> tray = [null, null, null];
  late SeededRandom _rng;
  int score = 0, bridges = 0, moves = 0, grainsCleared = 0;
  bool lost = false;
  int _pass = 0;

  /// Son silinen taneler (boyama için).
  Set<int> flash = {};

  SandGame(this.level) {
    _rng = SeededRandom(level.seed);
    _refill();
  }

  void _refill() {
    for (var i = 0; i < 3; i++) {
      tray[i] = SandPiece(_rng.nextInt(kSandShapes.length), 1 + _rng.nextInt(level.colors));
    }
  }

  bool get won => level.target > 0 && bridges >= level.target;
  bool get outOfMoves => level.moveLimit > 0 && moves >= level.moveLimit;
  bool get over => lost || won || outOfMoves;

  bool canDrop(int t, int cx) {
    final p = tray[t];
    if (p == null || over || cx < 0 || cx + p.w > kCellsW) return false;
    for (final c in p.cells) {
      for (var yy = 0; yy < kG; yy++) {
        for (var xx = 0; xx < kG; xx++) {
          if (g[(c[1] * kG + yy) * kSW + (cx + c[0]) * kG + xx] != 0) return false;
        }
      }
    }
    return true;
  }

  /// Parçayı en üste koyar (kum hemen akmaya başlar). Akış [stepSand] ile.
  bool drop(int t, int cx) {
    if (!canDrop(t, cx)) return false;
    final p = tray[t]!;
    for (final c in p.cells) {
      for (var yy = 0; yy < kG; yy++) {
        for (var xx = 0; xx < kG; xx++) {
          g[(c[1] * kG + yy) * kSW + (cx + c[0]) * kG + xx] = p.color;
        }
      }
    }
    tray[t] = null;
    moves++;
    if (tray.every((e) => e == null)) _refill();
    return true;
  }

  /// Bir akış adımı; hareket eden tane sayısı.
  int stepSand() {
    var moved = 0;
    _pass++;
    final ltr = _pass.isEven;
    for (var y = kSH - 2; y >= 0; y--) {
      for (var k = 0; k < kSW; k++) {
        final x = ltr ? k : kSW - 1 - k;
        final i = y * kSW + x;
        final v = g[i];
        if (v == 0) continue;
        final below = i + kSW;
        if (g[below] == 0) {
          g[below] = v;
          g[i] = 0;
          moved++;
          continue;
        }
        final first = ((x + y + _pass) & 1) == 0 ? -1 : 1;
        for (final dx in [first, -first]) {
          final nx = x + dx;
          if (nx < 0 || nx >= kSW) continue;
          if (g[below + dx] == 0 && g[i + dx] == 0) {
            g[below + dx] = v;
            g[i] = 0;
            moved++;
            break;
          }
        }
      }
    }
    return moved;
  }

  /// Soldan sağa uzanan aynı renk bölgeleri siler; silinen tane sayısı.
  int clearBridges() {
    final seen = List<bool>.filled(g.length, false);
    var total = 0;
    final cleared = <int>{};
    for (var y = 0; y < kSH; y++) {
      final start = y * kSW;
      if (g[start] == 0 || seen[start]) continue;
      final col = g[start];
      final comp = <int>[];
      var right = false;
      final st = [start];
      seen[start] = true;
      while (st.isNotEmpty) {
        final i = st.removeLast();
        comp.add(i);
        final x = i % kSW;
        if (x == kSW - 1) right = true;
        for (final n in [if (x > 0) i - 1, if (x < kSW - 1) i + 1, if (i >= kSW) i - kSW, if (i + kSW < g.length) i + kSW]) {
          if (!seen[n] && g[n] == col) {
            seen[n] = true;
            st.add(n);
          }
        }
      }
      if (right) {
        for (final i in comp) {
          g[i] = 0;
        }
        cleared.addAll(comp);
        total += comp.length;
        bridges++;
        score += comp.length * 2 + 100;
      }
    }
    if (total > 0) {
      grainsCleared += total;
      flash = cleared;
    }
    return total;
  }

  /// Kum durana dek akıt, köprüleri sil, tekrarla; ardından taşma kontrolü.
  void settle() {
    while (true) {
      var guard = 0;
      while (stepSand() > 0 && guard++ < 400) {}
      if (clearBridges() == 0) break;
    }
    afterSettle();
  }

  void afterSettle() {
    for (var i = 0; i < kDanger * kSW; i++) {
      if (g[i] != 0) {
        if (level.zen) {
          for (var k = 0; k < g.length ~/ 2; k++) {
            g[k] = 0;
          }
        } else {
          lost = true;
        }
        break;
      }
    }
    if (!lost && !won && ![for (var t = 0; t < 3; t++) for (var x = 0; x < kCellsW; x++) canDrop(t, x)].any((e) => e)) {
      lost = true;
    }
  }

  /// Sütun yüksekliği (kare cinsinden kaba).
  int heightAt(int gx) {
    for (var y = 0; y < kSH; y++) {
      if (g[y * kSW + gx] != 0) return kSH - y;
    }
    return 0;
  }

  /// Basit bot: alçak yere, aynı rengin çok olduğu yere bırak.
  (int, int)? bestMove() {
    (int, int)? best;
    var bestV = -1e18;
    for (var t = 0; t < 3; t++) {
      final p = tray[t];
      if (p == null) continue;
      for (var cx = 0; cx + p.w <= kCellsW; cx++) {
        if (!canDrop(t, cx)) continue;
        var hMax = 0;
        for (var gx = cx * kG; gx < (cx + p.w) * kG; gx++) {
          final h = heightAt(gx);
          if (h > hMax) hMax = h;
        }
        final surface = kSH - hMax;
        var same = 0, other = 0;
        for (var y = surface; y < (surface + kG * 3).clamp(0, kSH); y++) {
          for (var gx = (cx * kG - kG).clamp(0, kSW); gx < ((cx + p.w) * kG + kG).clamp(0, kSW); gx++) {
            final v = g[y * kSW + gx];
            if (v == p.color) same++;
            if (v != 0 && v != p.color) other++;
          }
        }
        // Sol ya da sağ duvara değen aynı renk de değerli: köprü uçları.
        final edge = (cx == 0 || cx + p.w == kCellsW) ? 8.0 : 0.0;
        final v = same * 1.0 - other * 0.4 - hMax * 1.6 + edge - t * 0.01;
        if (v > bestV) {
          bestV = v;
          best = (t, cx);
        }
      }
    }
    return best;
  }

  String serialize() => jsonEncode({
        'g': g,
        't': [for (final p in tray) p == null ? null : [p.shape, p.color]],
        'r': _rng.state,
        's': [score, bridges, moves, grainsCleared, lost ? 1 : 0, _pass],
      });

  static SandGame restore(SandLevel l, String snap) {
    final j = jsonDecode(snap) as Map<String, dynamic>;
    final game = SandGame(l);
    game.g = [for (final v in j['g'] as List) (v as num).toInt()];
    final t = j['t'] as List;
    for (var i = 0; i < 3; i++) {
      final e = t[i] as List?;
      game.tray[i] = e == null ? null : SandPiece((e[0] as num).toInt(), (e[1] as num).toInt());
    }
    game._rng = SeededRandom((j['r'] as num).toInt());
    final s = [for (final v in j['s'] as List) (v as num).toInt()];
    game
      ..score = s[0]
      ..bridges = s[1]
      ..moves = s[2]
      ..grainsCleared = s[3]
      ..lost = s[4] == 1
      .._pass = s[5];
    return game;
  }
}

int simulateSandLevel(SandLevel l, {int maxMoves = 160}) {
  final g = SandGame(l);
  while (!g.over && g.moves < maxMoves) {
    final m = g.bestMove();
    if (m == null) return -1;
    g.drop(m.$1, m.$2);
    g.settle();
  }
  return g.won ? g.moves : -1;
}
