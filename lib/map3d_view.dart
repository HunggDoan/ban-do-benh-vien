import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'map_data.dart';
import 'map_models.dart';

// =====================================================================
// BẢN ĐỒ 3D VẼ BẰNG DART THUẦN (CustomPainter), KHÔNG CẦN THƯ VIỆN NGOÀI.
// Chạy được trên web, Android, iOS. Tòa nhà là các khối hộp, vẽ theo
// thuật toán "người họa sĩ" (vẽ vật ở xa trước, vật ở gần sau).
// =====================================================================

const double kFloorHeight = 1.8;

/// Đổi tọa độ pixel sơ đồ sang tọa độ 3D (10 pixel = 1 đơn vị).
double wx(double px) => (px - 1100) / 10;
double wz(double py) => (py - 900) / 10;

class V3 {
  final double x, y, z;
  const V3(this.x, this.y, this.z);
  V3 operator +(V3 o) => V3(x + o.x, y + o.y, z + o.z);
  V3 operator -(V3 o) => V3(x - o.x, y - o.y, z - o.z);
  V3 operator *(double s) => V3(x * s, y * s, z * s);
  double dot(V3 o) => x * o.x + y * o.y + z * o.z;
  V3 cross(V3 o) => V3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
  double get length => math.sqrt(x * x + y * y + z * z);
  V3 normalized() {
    final l = length;
    return l == 0 ? this : this * (1 / l);
  }
}

// ---------------------------------------------------------------------
// BẢNG MÀU (sáng / tối)
// ---------------------------------------------------------------------
class MapPalette {
  final Color ground, road, roadLine, path, clinic, emergency, support, park, roof;
  final Color accent, door, route, start, labelBg, labelFg, muted, line;
  const MapPalette({
    required this.ground,
    required this.road,
    required this.roadLine,
    required this.path,
    required this.clinic,
    required this.emergency,
    required this.support,
    required this.park,
    required this.roof,
    required this.accent,
    required this.door,
    required this.route,
    required this.start,
    required this.labelBg,
    required this.labelFg,
    required this.muted,
    required this.line,
  });

  static const light = MapPalette(
    ground: Color(0xFFD3DFD0),
    road: Color(0xFFA7A4A0),
    roadLine: Color(0xFFEFE9DF),
    path: Color(0xFFEFE9DF),
    clinic: Color(0xFFD9BFC1),
    emergency: Color(0xFFC6453C),
    support: Color(0xFFCFC9C2),
    park: Color(0xFFBFCFC4),
    roof: Color(0xFFEFE7E4),
    accent: Color(0xFF2F6F73),
    door: Color(0xFFD2342A),
    route: Color(0xFFD4372C),
    start: Color(0xFF1F63B0),
    labelBg: Color(0xFFFBFBF8),
    labelFg: Color(0xFF24252A),
    muted: Color(0xFF62606A),
    line: Color(0xFFD9D6CF),
  );

  static const dark = MapPalette(
    ground: Color(0xFF202327),
    road: Color(0xFF3A3D42),
    roadLine: Color(0xFF5B5F66),
    path: Color(0xFF2F3338),
    clinic: Color(0xFF8F6F73),
    emergency: Color(0xFFD0584E),
    support: Color(0xFF6E6A66),
    park: Color(0xFF5D7364),
    roof: Color(0xFFA88D90),
    accent: Color(0xFF6FB3B7),
    door: Color(0xFFFF6A5C),
    route: Color(0xFFFF6B5E),
    start: Color(0xFF6EAEFF),
    labelBg: Color(0xFF1F2226),
    labelFg: Color(0xFFECE8E6),
    muted: Color(0xFFA6A2A6),
    line: Color(0xFF363A40),
  );

  Color forKind(BuildingKind k) {
    switch (k) {
      case BuildingKind.clinic:
        return clinic;
      case BuildingKind.emergency:
        return emergency;
      case BuildingKind.support:
        return support;
      case BuildingKind.parking:
        return park;
    }
  }
}

Color _shade(Color c, double f) =>
    f < 1 ? Color.lerp(c, const Color(0xFF000000), 1 - f)! : Color.lerp(c, const Color(0xFFFFFFFF), f - 1)!;

// ---------------------------------------------------------------------
// CAMERA
// ---------------------------------------------------------------------
class CameraState {
  final double tx, tz; // điểm nhìn trên mặt đất
  final double yaw; // góc quay quanh trục đứng
  final double pitch; // góc ngẩng (0 = ngang, pi/2 = nhìn thẳng xuống)
  final double dist; // khoảng cách tới điểm nhìn
  const CameraState(this.tx, this.tz, this.yaw, this.pitch, this.dist);

  static double _angLerp(double a, double b, double t) {
    var d = (b - a) % (2 * math.pi);
    if (d > math.pi) d -= 2 * math.pi;
    return a + d * t;
  }

  CameraState lerp(CameraState o, double t) => CameraState(
        tx + (o.tx - tx) * t,
        tz + (o.tz - tz) * t,
        _angLerp(yaw, o.yaw, t),
        pitch + (o.pitch - pitch) * t,
        dist + (o.dist - dist) * t,
      );

  CameraState copyWith({double? tx, double? tz, double? yaw, double? pitch, double? dist}) =>
      CameraState(tx ?? this.tx, tz ?? this.tz, yaw ?? this.yaw, pitch ?? this.pitch, dist ?? this.dist);

  V3 get target => V3(tx, 0, tz);
  V3 get position => V3(
        tx + math.sin(yaw) * math.cos(pitch) * dist,
        math.sin(pitch) * dist,
        tz + math.cos(yaw) * math.cos(pitch) * dist,
      );
}

/// Điều khiển camera từ bên ngoài (màn hình chính gọi fit, đổi góc nhìn...).
class Map3DController extends ChangeNotifier {
  bool topView = false;
  _FitSpec _lastFit = const _FitSpec([Offset(1150, 1000)], 0, 150);
  CameraState? _request;
  double _pendingRotate = 0;
  double _pendingZoom = 1;

  /// Đưa các điểm (pixel sơ đồ) vào khung nhìn; [facingDeg] là hướng sẽ nằm ở phía trên màn hình.
  void fit(List<Offset> mapPoints, double facingDeg, {double minSize = 25}) {
    _lastFit = _FitSpec(mapPoints, facingDeg, minSize);
    _request = _lastFit.compute(topView);
    notifyListeners();
  }

  void overview() => fit(const [Offset(1150, 1000)], _lastFit.facing, minSize: 150);

  void setTopView(bool top) {
    topView = top;
    _request = _lastFit.compute(topView);
    notifyListeners();
  }

  void rotateBy(double radians) {
    _pendingRotate += radians;
    notifyListeners();
  }

  void zoomBy(double factor) {
    _pendingZoom *= factor;
    notifyListeners();
  }
}

class _FitSpec {
  final List<Offset> points;
  final double facing;
  final double minSize;
  const _FitSpec(this.points, this.facing, this.minSize);

  CameraState compute(bool top) {
    var minX = double.infinity, maxX = -double.infinity, minZ = double.infinity, maxZ = -double.infinity;
    for (final p in points) {
      final x = wx(p.dx), z = wz(p.dy);
      minX = math.min(minX, x);
      maxX = math.max(maxX, x);
      minZ = math.min(minZ, z);
      maxZ = math.max(maxZ, z);
    }
    final size = math.max(minSize, math.max(maxX - minX, maxZ - minZ));
    final d0 = size * 1.05 + 22;
    final f = facing * math.pi / 180;
    final dx = math.sin(f), dz = -math.cos(f);
    // Camera đứng sau lưng người, nhìn theo hướng (dx, dz)
    final yaw = math.atan2(-dx, -dz);
    return top
        ? CameraState((minX + maxX) / 2, (minZ + maxZ) / 2, yaw, 1.42, d0 * 1.5)
        : CameraState((minX + maxX) / 2, (minZ + maxZ) / 2, yaw, 0.848, d0 * 1.134);
  }
}

// ---------------------------------------------------------------------
// WIDGET
// ---------------------------------------------------------------------
class Map3DView extends StatefulWidget {
  final Map3DController controller;
  final String? startNodeId;
  final double facingDeg;
  final List<String> routeNodeIds;
  final String? destNodeId;
  final String? destLabel;
  final String? highlightBuildingId;

  /// Vùng màn hình bị bảng điều khiển che, để đặt tâm bản đồ vào phần còn trống.
  final EdgeInsets insets;
  final void Function(String buildingId)? onTapBuilding;
  final void Function(String placeId)? onTapGate;
  final VoidCallback? onUserGesture;

  const Map3DView({
    super.key,
    required this.controller,
    this.startNodeId,
    this.facingDeg = 0,
    this.routeNodeIds = const [],
    this.destNodeId,
    this.destLabel,
    this.highlightBuildingId,
    this.insets = EdgeInsets.zero,
    this.onTapBuilding,
    this.onTapGate,
    this.onUserGesture,
  });

  @override
  State<Map3DView> createState() => _Map3DViewState();
}

class _Map3DViewState extends State<Map3DView> with TickerProviderStateMixin {
  CameraState _cam = const _FitSpec([Offset(1150, 1000)], 0, 150).compute(false);
  CameraState _from = const CameraState(0, 0, 0, 0.8, 200);
  CameraState _to = const CameraState(0, 0, 0, 0.8, 200);
  late final AnimationController _tween;
  late final AnimationController _flow;
  final _HitRegistry _hits = _HitRegistry();
  double _lastScale = 1, _lastRotation = 0;

  @override
  void initState() {
    super.initState();
    _tween = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..addListener(() {
        final t = Curves.easeInOutQuad.transform(_tween.value);
        setState(() => _cam = _from.lerp(_to, t));
      });
    _flow = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..addListener(() => setState(() {}));
    widget.controller.addListener(_onCommand);
    _syncFlow();
  }

  @override
  void didUpdateWidget(covariant Map3DView old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onCommand);
      widget.controller.addListener(_onCommand);
    }
    _syncFlow();
  }

  void _syncFlow() {
    // Mũi tên chạy trên đường đi; tắt khi không có đường hoặc người dùng muốn giảm chuyển động
    final reduce = WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    final need = widget.routeNodeIds.length > 1;
    if (need && !reduce) {
      if (!_flow.isAnimating) _flow.repeat();
    } else {
      _flow.stop();
    }
  }

  void _onCommand() {
    final c = widget.controller;
    final req = c._request;
    if (req != null) {
      c._request = null;
      _from = _cam;
      _to = req;
      final reduce = WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;
      if (reduce) {
        setState(() => _cam = req);
      } else {
        _tween.forward(from: 0);
      }
    }
    if (c._pendingRotate != 0 || c._pendingZoom != 1) {
      _tween.stop();
      setState(() {
        _cam = _cam.copyWith(
          yaw: _cam.yaw + c._pendingRotate,
          dist: (_cam.dist * c._pendingZoom).clamp(20.0, 420.0),
        );
      });
      c._pendingRotate = 0;
      c._pendingZoom = 1;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onCommand);
    _tween.dispose();
    _flow.dispose();
    super.dispose();
  }

  // ---- cử chỉ: 1 ngón kéo bản đồ, 2 ngón phóng to và xoay, cuộn chuột để phóng to
  void _pan(Offset delta, Size size) {
    final focal = _focal(size);
    final wpp = _cam.dist / focal;
    final rx = math.cos(_cam.yaw), rz = -math.sin(_cam.yaw); // hướng phải
    final fx = -math.sin(_cam.yaw), fz = -math.cos(_cam.yaw); // hướng trước mặt
    final k = 1 / math.max(math.sin(_cam.pitch), 0.35);
    final tx = _cam.tx - rx * delta.dx * wpp + fx * delta.dy * wpp * k;
    final tz = _cam.tz - rz * delta.dx * wpp + fz * delta.dy * wpp * k;
    _cam = _cam.copyWith(tx: tx.clamp(-140.0, 140.0), tz: tz.clamp(-110.0, 120.0));
  }

  double _focal(Size size) {
    final fov = (size.width < 720 ? 58 : 42) * math.pi / 180;
    return (size.height / 2) / math.tan(fov / 2);
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).brightness == Brightness.dark ? MapPalette.dark : MapPalette.light;
    return LayoutBuilder(builder: (context, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxHeight);
      return Listener(
        onPointerSignal: (e) {
          if (e is PointerScrollEvent) {
            _tween.stop();
            setState(() {
              _cam = _cam.copyWith(dist: (_cam.dist * math.pow(1.0015, e.scrollDelta.dy)).clamp(20.0, 420.0));
            });
          }
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onScaleStart: (d) {
            _tween.stop();
            _lastScale = 1;
            _lastRotation = 0;
            widget.onUserGesture?.call();
          },
          onScaleUpdate: (d) {
            setState(() {
              if (d.pointerCount >= 2) {
                final zf = _lastScale / (d.scale == 0 ? 1 : d.scale);
                _cam = _cam.copyWith(
                  dist: (_cam.dist * zf).clamp(20.0, 420.0),
                  yaw: _cam.yaw - (d.rotation - _lastRotation),
                );
                _lastScale = d.scale;
                _lastRotation = d.rotation;
              }
              _pan(d.focalPointDelta, size);
            });
          },
          onTapUp: (d) => _handleTap(d.localPosition),
          child: CustomPaint(
            size: size,
            painter: _MapPainter(
              cam: _cam,
              palette: palette,
              widget: widget,
              flow: _flow.value,
              hits: _hits,
              textScale: MediaQuery.textScalerOf(context),
            ),
          ),
        ),
      );
    });
  }

  void _handleTap(Offset p) {
    final hit = _hits.hitTest(p);
    if (hit == null) return;
    if (hit.placeId != null) {
      widget.onTapGate?.call(hit.placeId!);
    } else if (hit.buildingId != null) {
      widget.onTapBuilding?.call(hit.buildingId!);
    }
  }
}

// ---------------------------------------------------------------------
// VÙNG BẤM
// ---------------------------------------------------------------------
class _Hit {
  final Path? path;
  final Rect? rect;
  final String? buildingId;
  final String? placeId;
  _Hit({this.path, this.rect, this.buildingId, this.placeId});
  bool contains(Offset p) => (rect?.contains(p) ?? false) || (path?.contains(p) ?? false);
}

class _HitRegistry {
  final List<_Hit> solids = []; // theo thứ tự vẽ (xa → gần)
  final List<_Hit> labels = [];
  void clear() {
    solids.clear();
    labels.clear();
  }

  _Hit? hitTest(Offset p) {
    for (final h in labels.reversed) {
      if (h.contains(p)) return h;
    }
    for (final h in solids.reversed) {
      if (h.contains(p)) return h;
    }
    return null;
  }
}

// ---------------------------------------------------------------------
// PHÉP CHIẾU PHỐI CẢNH
// ---------------------------------------------------------------------
class _Proj {
  late final V3 cam, f, r, u;
  late final double focal, cx, cy;
  static const double near = 0.6;

  _Proj(CameraState s, Size size, EdgeInsets insets) {
    cam = s.position;
    f = (s.target - cam).normalized();
    r = f.cross(const V3(0, 1, 0)).normalized();
    u = r.cross(f);
    final fov = (size.width < 720 ? 58 : 42) * math.pi / 180;
    focal = (size.height / 2) / math.tan(fov / 2);
    cx = insets.left + (size.width - insets.left - insets.right) / 2;
    cy = insets.top + (size.height - insets.top - insets.bottom) / 2;
  }

  V3 toCam(V3 p) {
    final v = p - cam;
    return V3(v.dot(r), v.dot(u), v.dot(f));
  }

  Offset screen(V3 c) => Offset(cx + c.x / c.z * focal, cy - c.y / c.z * focal);

  /// Chiếu một đa giác, cắt phần nằm sau camera.
  List<Offset>? poly(List<V3> world) {
    final pts = world.map(toCam).toList();
    final out = <V3>[];
    for (var i = 0; i < pts.length; i++) {
      final cur = pts[i], prev = pts[(i - 1 + pts.length) % pts.length];
      final inCur = cur.z >= near, inPrev = prev.z >= near;
      if (inCur) {
        if (!inPrev) out.add(_cut(prev, cur));
        out.add(cur);
      } else if (inPrev) {
        out.add(_cut(prev, cur));
      }
    }
    if (out.length < 3) return null;
    return out.map(screen).toList();
  }

  (Offset, Offset)? segment(V3 a, V3 b) {
    var ca = toCam(a), cb = toCam(b);
    if (ca.z < near && cb.z < near) return null;
    if (ca.z < near) ca = _cut(cb, ca);
    if (cb.z < near) cb = _cut(ca, cb);
    return (screen(ca), screen(cb));
  }

  /// Chiếu một điểm; trả về null nếu điểm nằm sau camera. z = độ sâu.
  (Offset, double)? point(V3 p) {
    final c = toCam(p);
    if (c.z < near) return null;
    return (screen(c), c.z);
  }

  V3 _cut(V3 a, V3 b) {
    final t = (near - a.z) / (b.z - a.z);
    return a + (b - a) * t;
  }
}

Path _pathOf(List<Offset> pts) {
  final p = Path()..moveTo(pts.first.dx, pts.first.dy);
  for (var i = 1; i < pts.length; i++) {
    p.lineTo(pts[i].dx, pts[i].dy);
  }
  return p..close();
}

/// Một vật thể 3D (khối nhà, mái che, cổng...) gồm nhiều mặt, vẽ cùng nhau.
class _Solid {
  final double depth;
  final void Function(Canvas canvas, _HitRegistry hits) draw;
  _Solid(this.depth, this.draw);
}

// ---------------------------------------------------------------------
// HỌA SĨ
// ---------------------------------------------------------------------
class _MapPainter extends CustomPainter {
  final CameraState cam;
  final MapPalette palette;
  final Map3DView widget;
  final double flow;
  final _HitRegistry hits;
  final TextScaler textScale;

  _MapPainter({
    required this.cam,
    required this.palette,
    required this.widget,
    required this.flow,
    required this.hits,
    required this.textScale,
  });

  @override
  void paint(Canvas canvas, Size size) {
    hits.clear();
    final pr = _Proj(cam, size, widget.insets);
    final fill = Paint()..isAntiAlias = true;

    // 1. Mặt đất, đường, lối đi
    canvas.drawRect(Offset.zero & size, fill..color = palette.ground);
    _flat(canvas, pr, roadPolygon.map((o) => V3(wx(o.dx), 0.02, wz(o.dy))).toList(), palette.road);
    _polyline(canvas, pr, roadCenterLine.map((o) => V3(wx(o.dx), 0.05, wz(o.dy))).toList(), palette.roadLine, 1.2);
    for (final e in allEdges) {
      if (e.indoor != null) continue;
      _strip(canvas, pr, e.nodeA.pos, e.nodeB.pos, e.width, 0.03, palette.path);
    }
    for (final n in allNodes) {
      if (n.type != NodeType.door) continue;
      _dot(canvas, pr, V3(wx(n.x), 0.15, wz(n.y)), 0.6, palette.door);
    }

    // 2. Các vật thể 3D, sắp từ xa đến gần
    final solids = <_Solid>[];
    final camPos = pr.cam;
    for (final b in buildings) {
      solids.add(_buildingSolid(pr, camPos, b));
    }
    for (final e in allEdges) {
      if (e.covered && e.drawCanopy) solids.add(_canopySolid(pr, camPos, e));
    }
    final porch = porchRect;
    if (porch != null) solids.add(_boxSolid(pr, camPos, porch, 4.0, 4.35, palette.clinic, palette.clinic, posts: true));
    for (final g in gateShapes) {
      solids.add(_gateSolid(pr, camPos, g));
    }
    if (staffShedPolygon.length >= 3) solids.add(_shedSolid(pr, camPos));
    solids.sort((a, b) => b.depth.compareTo(a.depth));
    for (final s in solids) {
      s.draw(canvas, hits);
    }

    // 3. Đường đi, hướng nhìn, ghim (luôn vẽ đè lên trên)
    _drawRoute(canvas, pr);
    _drawStart(canvas, pr);
    _drawDest(canvas, pr);

    // 4. Nhãn
    _drawLabels(canvas, pr);
  }

  // ---- mặt phẳng nằm trên đất
  void _flat(Canvas canvas, _Proj pr, List<V3> pts, Color color) {
    final s = pr.poly(pts);
    if (s == null) return;
    canvas.drawPath(_pathOf(s), Paint()..color = color);
  }

  void _strip(Canvas canvas, _Proj pr, Offset a, Offset b, double width, double y, Color color) {
    final ax = wx(a.dx), az = wz(a.dy), bx = wx(b.dx), bz = wz(b.dy);
    final len = math.sqrt((bx - ax) * (bx - ax) + (bz - az) * (bz - az));
    if (len == 0) return;
    final ux = (bx - ax) / len, uz = (bz - az) / len, h = width / 2;
    // kéo dài 2 đầu nửa bề rộng để chỗ nối liền mạch
    final x1 = ax - ux * h, z1 = az - uz * h, x2 = bx + ux * h, z2 = bz + uz * h;
    _flat(canvas, pr, [
      V3(x1 - uz * h, y, z1 + ux * h),
      V3(x2 - uz * h, y, z2 + ux * h),
      V3(x2 + uz * h, y, z2 - ux * h),
      V3(x1 + uz * h, y, z1 - ux * h),
    ], color);
  }

  void _polyline(Canvas canvas, _Proj pr, List<V3> pts, Color color, double width) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < pts.length - 1; i++) {
      final s = pr.segment(pts[i], pts[i + 1]);
      if (s != null) canvas.drawLine(s.$1, s.$2, paint);
    }
  }

  void _dot(Canvas canvas, _Proj pr, V3 p, double radius, Color color) {
    final s = pr.point(p);
    if (s == null) return;
    canvas.drawCircle(s.$1, math.max(1.5, radius * pr.focal / s.$2), Paint()..color = color);
  }

  // ---- khoảng cách từ camera tới hình chữ nhật trên mặt đất (để sắp thứ tự vẽ)
  double _rectDepth(V3 cam, double x1, double z1, double x2, double z2, [double y = 0]) {
    final px = cam.x.clamp(x1, x2), pz = cam.z.clamp(z1, z2);
    final dx = cam.x - px, dz = cam.z - pz, dy = cam.y - y;
    return math.sqrt(dx * dx + dz * dz + dy * dy * 0.2);
  }

  /// Vẽ một khối hộp: các mặt tường nhìn thấy, rồi mái.
  void _box(Canvas canvas, _Proj pr, V3 cam, double x1, double z1, double x2, double z2, double y0, double y1,
      Color wall, Color roof,
      {int floors = 0, String? buildingId, String? placeId, _HitRegistry? hits, bool highlight = false}) {
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7
      ..color = _shade(wall, 0.72);
    final band = Paint()..color = const Color(0x38000000);
    final hl = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..color = palette.route;

    void face(List<V3> pts, Color c, {bool walls = false, double len = 0, V3? along, V3? origin}) {
      final s = pr.poly(pts);
      if (s == null) return;
      final path = _pathOf(s);
      canvas.drawPath(path, Paint()..color = c);
      if (walls && floors > 0 && along != null && origin != null && len > 1.5) {
        // dải cửa sổ mỗi tầng
        for (var i = 0; i < floors; i++) {
          final ya = y0 + i * kFloorHeight + 0.55, yb = ya + 0.7;
          final a0 = origin + along * 0.5, a1 = origin + along * (len - 0.5);
          final w = pr.poly([
            V3(a0.x, ya, a0.z),
            V3(a1.x, ya, a1.z),
            V3(a1.x, yb, a1.z),
            V3(a0.x, yb, a0.z),
          ]);
          if (w != null) canvas.drawPath(_pathOf(w), band);
        }
      }
      canvas.drawPath(path, edge);
      if (highlight) canvas.drawPath(path, hl);
      if (hits != null && (buildingId != null || placeId != null)) {
        hits.solids.add(_Hit(path: path, buildingId: buildingId, placeId: placeId));
      }
    }

    // mặt nam (z2), bắc (z1), đông (x2), tây (x1)
    if (cam.z > z2) {
      face([V3(x1, y0, z2), V3(x2, y0, z2), V3(x2, y1, z2), V3(x1, y1, z2)], _shade(wall, 0.95),
          walls: true, len: x2 - x1, along: const V3(1, 0, 0), origin: V3(x1, 0, z2 + 0.01));
    }
    if (cam.z < z1) {
      face([V3(x2, y0, z1), V3(x1, y0, z1), V3(x1, y1, z1), V3(x2, y1, z1)], _shade(wall, 0.80),
          walls: true, len: x2 - x1, along: const V3(-1, 0, 0), origin: V3(x2, 0, z1 - 0.01));
    }
    if (cam.x > x2) {
      face([V3(x2, y0, z2), V3(x2, y0, z1), V3(x2, y1, z1), V3(x2, y1, z2)], _shade(wall, 0.85),
          walls: true, len: z2 - z1, along: const V3(0, 0, -1), origin: V3(x2 + 0.01, 0, z2));
    }
    if (cam.x < x1) {
      face([V3(x1, y0, z1), V3(x1, y0, z2), V3(x1, y1, z2), V3(x1, y1, z1)], _shade(wall, 1.0),
          walls: true, len: z2 - z1, along: const V3(0, 0, 1), origin: V3(x1 - 0.01, 0, z1));
    }
    if (cam.y > y1) {
      face([V3(x1, y1, z1), V3(x2, y1, z1), V3(x2, y1, z2), V3(x1, y1, z2)], roof);
    }
  }

  _Solid _buildingSolid(_Proj pr, V3 cam, Building b) {
    final x1 = wx(b.rect.left), x2 = wx(b.rect.right), z1 = wz(b.rect.top), z2 = wz(b.rect.bottom);
    final hl = widget.highlightBuildingId == b.id;
    if (b.kind == BuildingKind.parking) {
      return _Solid(_rectDepth(cam, x1, z1, x2, z2), (canvas, hits) {
        _posts(canvas, pr, [V3(x1 + .6, 0, z1 + .6), V3(x2 - .6, 0, z1 + .6), V3(x1 + .6, 0, z2 - .6), V3(x2 - .6, 0, z2 - .6)], 3.2);
        _box(canvas, pr, cam, x1, z1, x2, z2, 3.2, 3.6, palette.park, palette.park,
            buildingId: b.id, hits: hits, highlight: hl);
      });
    }
    final h = b.floors * kFloorHeight + 0.4;
    final wall = palette.forKind(b.kind);
    return _Solid(_rectDepth(cam, x1, z1, x2, z2), (canvas, hits) {
      _box(canvas, pr, cam, x1, z1, x2, z2, 0, h, hl ? _shade(wall, 1.12) : wall, palette.roof,
          floors: b.floors, buildingId: b.id, hits: hits, highlight: hl);
    });
  }

  _Solid _boxSolid(_Proj pr, V3 cam, Rect r, double y0, double y1, Color wall, Color roof, {bool posts = false}) {
    final x1 = wx(r.left), x2 = wx(r.right), z1 = wz(r.top), z2 = wz(r.bottom);
    return _Solid(_rectDepth(cam, x1, z1, x2, z2), (canvas, hits) {
      if (posts) _posts(canvas, pr, [V3(x1 + .5, 0, z2 - .5), V3(x2 - .5, 0, z2 - .5)], y0);
      _box(canvas, pr, cam, x1, z1, x2, z2, y0, y1, wall, roof);
    });
  }

  _Solid _canopySolid(_Proj pr, V3 cam, MapEdge e) {
    final ax = wx(e.nodeA.x), az = wz(e.nodeA.y), bx = wx(e.nodeB.x), bz = wz(e.nodeB.y);
    // các hành lang mái che hiện đều chạy dọc hoặc ngang
    const w = 2.2;
    final x1 = math.min(ax, bx) - (ax == bx ? w : 0), x2 = math.max(ax, bx) + (ax == bx ? w : 0);
    final z1 = math.min(az, bz) - (az == bz ? w : 0), z2 = math.max(az, bz) + (az == bz ? w : 0);
    final postPts = <V3>[];
    final len = math.sqrt((bx - ax) * (bx - ax) + (bz - az) * (bz - az));
    final n = math.max(1, (len / 4).round());
    for (var i = 0; i <= n; i++) {
      final t = i / n, px = ax + (bx - ax) * t, pz = az + (bz - az) * t;
      if (ax == bx) {
        postPts..add(V3(px - 1.8, 0, pz))..add(V3(px + 1.8, 0, pz));
      } else {
        postPts..add(V3(px, 0, pz - 1.8))..add(V3(px, 0, pz + 1.8));
      }
    }
    return _Solid(_rectDepth(cam, x1, z1, x2, z2), (canvas, hits) {
      _posts(canvas, pr, postPts, 3.6);
      _box(canvas, pr, cam, x1, z1, x2, z2, 3.6, 3.9, palette.accent, _shade(palette.accent, 1.08));
    });
  }

  _Solid _gateSolid(_Proj pr, V3 cam, GateShape g) {
    final x1 = wx(g.x1), x2 = wx(g.x2), z = wz(g.y);
    return _Solid(_rectDepth(cam, x1, z - .5, x2, z + .5), (canvas, hits) {
      _box(canvas, pr, cam, x1 - .5, z - .5, x1 + .5, z + .5, 0, 4.5, palette.accent, palette.accent, placeId: g.placeId, hits: hits);
      _box(canvas, pr, cam, x2 - .5, z - .5, x2 + .5, z + .5, 0, 4.5, palette.accent, palette.accent, placeId: g.placeId, hits: hits);
      _box(canvas, pr, cam, x1 - .5, z - .5, x2 + .5, z + .5, 4.3, 5.0, palette.accent, palette.accent, placeId: g.placeId, hits: hits);
    });
  }

  _Solid _shedSolid(_Proj pr, V3 cam) {
    final pts = staffShedPolygon.map((o) => V3(wx(o.dx), 3.0, wz(o.dy))).toList();
    final posts = staffShedPosts.map((o) => V3(wx(o.dx), 0, wz(o.dy))).toList();
    var minX = double.infinity, maxX = -double.infinity, minZ = double.infinity, maxZ = -double.infinity;
    for (final p in pts) {
      minX = math.min(minX, p.x);
      maxX = math.max(maxX, p.x);
      minZ = math.min(minZ, p.z);
      maxZ = math.max(maxZ, p.z);
    }
    return _Solid(_rectDepth(cam, minX, minZ, maxX, maxZ) + 30, (canvas, hits) {
      _posts(canvas, pr, posts, 3.0);
      final s = pr.poly(pts);
      if (s != null) {
        final path = _pathOf(s);
        canvas.drawPath(path, Paint()..color = palette.park);
        canvas.drawPath(path, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.7
          ..color = _shade(palette.park, 0.7));
      }
    });
  }

  void _posts(Canvas canvas, _Proj pr, List<V3> base, double h) {
    final p = Paint()
      ..color = _shade(palette.support, 0.7)
      ..strokeWidth = 1.4;
    for (final b in base) {
      final s = pr.segment(b, V3(b.x, h, b.z));
      if (s != null) canvas.drawLine(s.$1, s.$2, p);
    }
  }

  // ---- đường đi
  void _drawRoute(Canvas canvas, _Proj pr) {
    final ids = widget.routeNodeIds;
    if (ids.length < 2) return;
    final nodes = ids.map((id) => nodeById[id]!).toList();
    final routeColor = palette.route.withValues(alpha: 0.92);
    for (var i = 0; i < nodes.length - 1; i++) {
      _strip(canvas, pr, nodes[i].pos, nodes[i + 1].pos, 1.7, 0.2, routeColor);
    }
    // mũi tên chạy dọc đường, cách nhau 5 đơn vị
    final pts = nodes.map((n) => Offset(wx(n.x), wz(n.y))).toList();
    var total = 0.0;
    for (var i = 0; i < pts.length - 1; i++) {
      total += (pts[i + 1] - pts[i]).distance;
    }
    final white = Paint()..color = const Color(0xFFFFFFFF);
    const gap = 5.0;
    for (var d = flow * gap; d < total; d += gap) {
      var rest = d;
      for (var i = 0; i < pts.length - 1; i++) {
        final seg = pts[i + 1] - pts[i], l = seg.distance;
        if (rest <= l) {
          final u = seg / l, c = pts[i] + u * rest, n = Offset(-u.dy, u.dx);
          final tip = c + u * 0.9, b1 = c - u * 0.5 + n * 0.7, mid = c - u * 0.15, b2 = c - u * 0.5 - n * 0.7;
          final s = pr.poly([
            V3(tip.dx, 0.22, tip.dy),
            V3(b1.dx, 0.22, b1.dy),
            V3(mid.dx, 0.22, mid.dy),
            V3(b2.dx, 0.22, b2.dy),
          ]);
          if (s != null) canvas.drawPath(_pathOf(s), white);
          break;
        }
        rest -= l;
      }
    }
  }

  void _drawStart(Canvas canvas, _Proj pr) {
    final id = widget.startNodeId;
    if (id == null) return;
    final n = nodeById[id]!;
    final cx = wx(n.x), cz = wz(n.y);
    // hình quạt chỉ hướng người đang nhìn
    final f = widget.facingDeg * math.pi / 180;
    final arc = <V3>[V3(cx, 0.18, cz)];
    for (var i = 0; i <= 10; i++) {
      final a = f - math.pi / 5 + (2 * math.pi / 5) * i / 10;
      arc.add(V3(cx + 9 * math.sin(a), 0.18, cz - 9 * math.cos(a)));
    }
    _flat(canvas, pr, arc, palette.start.withValues(alpha: 0.35));
    _pin(canvas, pr, cx, cz, 7, palette.start);
  }

  void _drawDest(Canvas canvas, _Proj pr) {
    final id = widget.destNodeId;
    if (id == null || widget.routeNodeIds.length < 2) return;
    final n = nodeById[id]!;
    _pin(canvas, pr, wx(n.x), wz(n.y), 9, palette.route);
  }

  void _pin(Canvas canvas, _Proj pr, double x, double z, double h, Color color) {
    final pulse = 1 + 0.25 * math.sin(flow * 2 * math.pi);
    final g = pr.point(V3(x, 0.15, z));
    if (g != null) {
      canvas.drawCircle(g.$1, math.max(4.0, 1.6 * pulse * pr.focal / g.$2), Paint()..color = color.withValues(alpha: 0.3));
    }
    final s = pr.segment(V3(x, 0, z), V3(x, h, z));
    if (s != null) {
      canvas.drawLine(s.$1, s.$2, Paint()
        ..color = color
        ..strokeWidth = 2.5);
    }
    final head = pr.point(V3(x, h, z));
    if (head != null) {
      final r = math.max(5.0, 1.1 * pr.focal / head.$2);
      canvas.drawCircle(head.$1, r, Paint()..color = color);
      canvas.drawCircle(head.$1, r, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0xFFFFFFFF));
    }
  }

  // ---- nhãn
  void _drawLabels(Canvas canvas, _Proj pr) {
    final far = cam.dist > 240;
    for (final b in buildings) {
      if (b.label.isEmpty) continue;
      final h = b.kind == BuildingKind.parking ? 3.6 : b.floors * kFloorHeight + 0.4;
      final big = b.label.length <= 2;
      final small = !big && b.floors <= 1;
      if (small && far) continue;
      final p = pr.point(V3(wx(b.rect.center.dx), h + 1.2, wz(b.rect.center.dy)));
      if (p == null) continue;
      final on = widget.highlightBuildingId == b.id;
      final rect = _label(canvas, p.$1, b.label,
          size: big ? 14 : (small ? 10.5 : 12),
          weight: big ? FontWeight.w700 : (small ? FontWeight.w500 : FontWeight.w600),
          fg: on ? const Color(0xFFFFFFFF) : (small ? palette.muted : palette.labelFg),
          bg: on ? palette.route : palette.labelBg);
      hits.labels.add(_Hit(rect: rect, buildingId: b.id));
    }
    for (final g in gateShapes) {
      final p = pr.point(V3(wx((g.x1 + g.x2) / 2), 6.2, wz(g.y)));
      if (p == null) continue;
      final rect = _label(canvas, p.$1, placeById[g.placeId]!.name, size: 11.5, weight: FontWeight.w600, fg: palette.labelFg, bg: palette.labelBg);
      hits.labels.add(_Hit(rect: rect, placeId: g.placeId));
    }
    for (final t in textLabels) {
      if (t.small && far) continue;
      final p = pr.point(V3(wx(t.pos.dx), t.height, wz(t.pos.dy)));
      if (p == null) continue;
      if (t.small) {
        _label(canvas, p.$1, t.text, size: 10.5, weight: FontWeight.w500, fg: palette.muted, bg: palette.labelBg);
      } else {
        _label(canvas, p.$1, t.text, size: 11, weight: FontWeight.w500, fg: palette.muted, bg: null);
      }
    }
    final sid = widget.startNodeId;
    if (sid != null) {
      final n = nodeById[sid]!;
      final p = pr.point(V3(wx(n.x), 8.6, wz(n.y)));
      if (p != null) {
        _label(canvas, p.$1, 'Bạn đang ở đây', size: 13, weight: FontWeight.w700, fg: const Color(0xFFFFFFFF), bg: palette.start);
      }
    }
    final did = widget.destNodeId;
    if (did != null && widget.routeNodeIds.length > 1) {
      final n = nodeById[did]!;
      final p = pr.point(V3(wx(n.x), 10.6, wz(n.y)));
      if (p != null) {
        _label(canvas, p.$1, widget.destLabel ?? 'Điểm đến',
            size: 13, weight: FontWeight.w700, fg: const Color(0xFFFFFFFF), bg: palette.route);
      }
    }
  }

  Rect _label(Canvas canvas, Offset anchor, String text,
      {required double size, required FontWeight weight, required Color fg, Color? bg}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(fontSize: size, fontWeight: weight, color: fg)),
      textDirection: TextDirection.ltr,
      textScaler: textScale,
      maxLines: 1,
    )..layout();
    final w = tp.width + 14, h = tp.height + 6;
    final rect = Rect.fromLTWH(anchor.dx - w / 2, anchor.dy - h, w, h);
    if (bg != null) {
      final rr = RRect.fromRectAndRadius(rect, const Radius.circular(5));
      canvas.drawRRect(rr, Paint()..color = bg);
      canvas.drawRRect(rr, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = palette.line);
    }
    tp.paint(canvas, Offset(rect.left + 7, rect.top + 3));
    return rect;
  }

  @override
  bool shouldRepaint(covariant _MapPainter old) => true;
}
