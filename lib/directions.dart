import 'dart:math' as math;

import 'map_data.dart';
import 'map_models.dart';
import 'path_finder.dart';

enum StepKind { start, straight, left, right, back, end, floor }

/// Một bước chỉ dẫn. Chữ đặt giữa **...** sẽ được in đậm.
class DirectionStep {
  final StepKind kind;
  final String text;
  const DirectionStep(this.kind, this.text);
}

class Directions {
  final List<DirectionStep> steps;
  final double meters;
  const Directions(this.steps, this.meters);

  int get minutes => math.max(1, (meters / walkingSpeed / 60).round());
}

String formatMeters(double m) => '${math.max(5, (m / 5).round() * 5)} m';

/// Hướng của đoạn a→b trên sơ đồ, theo độ (0 = lên trên, 90 = sang phải).
double _bearing(MapNode a, MapNode b) => math.atan2(b.x - a.x, -(b.y - a.y)) * 180 / math.pi;

double _wrap180(double d) {
  var x = d;
  while (x <= -180) {
    x += 360;
  }
  while (x > 180) {
    x -= 360;
  }
  return x;
}

/// Cùng quy ước với bản cũ: trục y hướng xuống, góc lệch dương = rẽ phải, ngưỡng 25°.
StepKind? _turnAt(MapNode a, MapNode b, MapNode c) {
  final a1 = math.atan2(b.y - a.y, b.x - a.x);
  final a2 = math.atan2(c.y - b.y, c.x - b.x);
  final d = _wrap180((a2 - a1) * 180 / math.pi);
  if (d > 25 && d < 155) return StepKind.right;
  if (d < -25 && d > -155) return StepKind.left;
  if (d.abs() >= 155) return StepKind.back;
  return null;
}

/// Tạo các bước chỉ dẫn.
/// [facing]: hướng người đang nhìn trên sơ đồ (độ), lấy từ tấm biển QR hoặc la bàn.
Directions buildDirections(RouteResult route, Department? dept, {double? facing, bool fromCompass = false}) {
  final ids = route.nodes;
  final steps = <DirectionStep>[DirectionStep(StepKind.start, 'Bạn đang ở **${ids.first.name}**')];

  if (route.edges.isEmpty) {
    steps.add(DirectionStep(StepKind.end, 'Bạn đang đứng ngay **${ids.first.name}**'));
  } else if (facing != null) {
    // Câu đầu tiên tính theo hướng người đang nhìn
    final a = ids[0], b = ids[1];
    final d = _wrap180(_bearing(a, b) - facing);
    final target = b.spokenName;
    if (d.abs() > 145) {
      steps.add(DirectionStep(StepKind.back,
          '**${fromCompass ? 'Quay người ra phía sau' : 'Quay lưng lại tấm biển QR'}**, hướng về $target'));
    } else if (d >= 35) {
      steps.add(DirectionStep(StepKind.right, '**Quay người sang phải**, hướng về $target'));
    } else if (d <= -35) {
      steps.add(DirectionStep(StepKind.left, '**Quay người sang trái**, hướng về $target'));
    } else {
      steps.add(DirectionStep(StepKind.straight, '**Đi thẳng về phía trước**, hướng về $target'));
    }
  }

  String kindOf(MapEdge e) => e.indoor != null ? 'in' : (e.covered ? 'cov' : 'out');
  var acc = 0.0;
  for (var k = 0; k < route.edges.length; k++) {
    final e = route.edges[k];
    acc += e.weight * metersPerPixel;
    final String lead;
    switch (kindOf(e)) {
      case 'in':
        lead = 'Đi xuyên qua ${e.indoor} khoảng **${formatMeters(acc)}**';
      case 'cov':
        lead = 'Đi theo hành lang có mái che khoảng **${formatMeters(acc)}**';
      default:
        lead = 'Đi thẳng khoảng **${formatMeters(acc)}**';
    }
    final at = ids[k + 1];
    if (k == route.edges.length - 1) {
      steps.add(DirectionStep(StepKind.end, '$lead là tới **${at.name}**'));
      break;
    }
    final t = _turnAt(ids[k], at, ids[k + 2]);
    if (t != null) {
      final word = t == StepKind.right ? 'rẽ phải' : (t == StepKind.left ? 'rẽ trái' : 'quay ngược lại');
      steps.add(DirectionStep(t, '$lead, rồi **$word** ở ${at.landmark}'));
      acc = 0;
    } else if (kindOf(route.edges[k + 1]) != kindOf(e)) {
      final where = at.type == NodeType.junction ? at.landmark : '**${at.name}**';
      steps.add(DirectionStep(StepKind.straight, '$lead tới $where'));
      acc = 0;
    }
  }

  if (dept != null) {
    if (dept.floor == 1) {
      steps.add(DirectionStep(StepKind.floor, '**${dept.name}** ở ngay **Tầng 1**, vào cửa là tới'));
    } else if (dept.floor != null) {
      steps.add(DirectionStep(StepKind.floor,
          'Vào tòa, lên **Tầng ${dept.floor}** bằng thang máy hoặc cầu thang bộ để tới **${dept.name}**'));
    } else {
      steps.add(DirectionStep(StepKind.floor, 'Vào tòa, hỏi quầy hướng dẫn để tới **${dept.name}**'));
    }
  }
  return Directions(steps, route.lengthMeters);
}
