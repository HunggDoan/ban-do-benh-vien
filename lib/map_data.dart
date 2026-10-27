import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

import 'map_models.dart';

// =====================================================================
// DỮ LIỆU BẢN ĐỒ: public/map_data.json
// File JSON này dùng chung cho app Flutter, trang web cho người bệnh và trang quản trị.
// Muốn đổi khoa, thêm tòa, thêm đường: dùng trang quản trị (/quantri/), không sửa file này.
//
// Bản release tải dữ liệu mới nhất từ trang web, nên sửa trên trang quản trị là app
// cũng cập nhật theo, không cần build lại. Không có mạng thì dùng bản có sẵn trong app.

/// Đường dẫn file dữ liệu trong dự án (khai báo trong pubspec.yaml).
const String kBundledDataAsset = 'public/map_data.json';

/// Nơi tải dữ liệu mới nhất khi chạy bản release trên điện thoại.
const String kLiveDataUrl = 'https://bando-sannhinghean.netlify.app/map_data.json';
// =====================================================================

// ---- cấu hình
late String appDomain;
late String logScriptUrl;
late double metersPerPixel; // 1 pixel sơ đồ ≈ bao nhiêu mét
late double walkingSpeed; // m/giây
late double mapUpBearing; // hướng la bàn của "phía trên" sơ đồ
late Map<String, String?> oldNodeIds; // mã QR cũ: null = đã bỏ, chuỗi = mã thay thế
late Map<String, double> gateFacing; // hướng nhìn mặc định ở các cổng

// ---- đồ thị đường đi
late List<MapNode> allNodes;
late Map<String, MapNode> nodeById;
late List<MapNode> displayNodes; // cổng và cửa (điểm xuất phát được)
late List<MapEdge> allEdges;

// ---- điểm đến
late List<Place> places;
late Map<String, Place> placeById;
late Map<String, String> placeIdByBuilding;
late List<(String, String, bool)> quickSearches;

// ---- hình khối 3D
late List<Building> buildings;
late Map<String, Building> buildingById;
late List<GateShape> gateShapes;
late Rect? porchRect;
late List<Offset> roadPolygon;
late List<Offset> roadCenterLine;
late List<Offset> staffShedPolygon;
late List<Offset> staffShedPosts;
late List<MapTextLabel> textLabels;

/// Các lỗi tìm thấy trong file JSON (mã điểm sai, điểm chưa nối đường...).
final List<String> dataProblems = [];

bool _loaded = false;

/// Gọi một lần trước runApp().
Future<void> loadMapData() async {
  if (_loaded) return;
  // 1. Bản release: thử lấy dữ liệu mới nhất trên trang web
  if (kReleaseMode) {
    try {
      final base = kIsWeb ? Uri.base.resolve('/map_data.json') : Uri.parse(kLiveDataUrl);
      final url = base.replace(queryParameters: {'t': '${DateTime.now().millisecondsSinceEpoch}'});
      final r = await http.get(url).timeout(const Duration(seconds: 5));
      if (r.statusCode == 200) {
        parseMapData(jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>);
        _loaded = true;
        return;
      }
    } catch (e) {
      debugPrintLoad('Không tải được dữ liệu trực tuyến, dùng bản trong app: $e');
    }
  }
  // 2. Bản chạy thử (flutter run) hoặc không có mạng: dùng file trong dự án
  final text = await rootBundle.loadString(kBundledDataAsset);
  parseMapData(jsonDecode(text) as Map<String, dynamic>);
  _loaded = true;
}

// ignore: avoid_print
void debugPrintLoad(String m) => print(m);

double _d(dynamic v) => (v as num).toDouble();
Offset _pt(dynamic v) => Offset(_d((v as List)[0]), _d(v[1]));
List<Offset> _pts(dynamic v) => v == null ? <Offset>[] : (v as List).map(_pt).toList();
List<Map<String, dynamic>> _list(dynamic v) =>
    v == null ? <Map<String, dynamic>>[] : (v as List).map((e) => e as Map<String, dynamic>).toList();

void parseMapData(Map<String, dynamic> j) {
  dataProblems.clear();
  _doorBuildingCache = null;
  final cfg = j['config'] as Map<String, dynamic>;
  appDomain = cfg['domain'] as String;
  logScriptUrl = cfg['logUrl'] as String? ?? '';
  metersPerPixel = _d(cfg['metersPerPixel']);
  walkingSpeed = _d(cfg['walkingSpeed']);
  mapUpBearing = _d(cfg['mapUpBearing']);
  oldNodeIds = ((j['oldIds'] as Map?) ?? {}).map((k, v) => MapEntry(k as String, v as String?));
  gateFacing = ((j['gateFacing'] as Map?) ?? {}).map((k, v) => MapEntry(k as String, _d(v)));

  // ---- điểm
  final nodes = <MapNode>[];
  final byId = <String, MapNode>{};
  for (final n in _list(j['nodes'])) {
    final id = n['id'] as String;
    if (byId.containsKey(id)) dataProblems.add('Mã điểm "$id" bị trùng.');
    final NodeType type;
    switch (n['type']) {
      case 'gate':
        type = NodeType.gate;
      case 'door':
        type = NodeType.door;
      case 'junction':
        type = NodeType.junction;
      default:
        dataProblems.add('Điểm "$id" có type "${n['type']}" không hợp lệ (gate / door / junction).');
        type = NodeType.junction;
    }
    final name = (n['name'] ?? n['landmark'] ?? id) as String;
    final node = MapNode(
      id: id,
      name: name,
      x: _d(n['x']),
      y: _d(n['y']),
      type: type,
      landmark: (n['landmark'] ?? n['name'] ?? id) as String,
    );
    nodes.add(node);
    byId[id] = node;
  }
  allNodes = nodes;
  nodeById = byId;
  displayNodes = nodes.where((n) => n.type != NodeType.junction).toList();

  // ---- đường: mỗi mục là một chuỗi điểm nối liền ("path")
  final edges = <MapEdge>[];
  final rawEdges = _list(j['edges']);
  for (var i = 0; i < rawEdges.length; i++) {
    final e = rawEdges[i];
    final path = e['path'] != null ? (e['path'] as List).cast<String>() : <String>[e['a'] as String, e['b'] as String];
    for (var k = 0; k < path.length - 1; k++) {
      final a = byId[path[k]], b = byId[path[k + 1]];
      if (a == null || b == null) {
        dataProblems.add('Đường thứ ${i + 1}: không có điểm "${a == null ? path[k] : path[k + 1]}".');
        continue;
      }
      edges.add(MapEdge(
        nodeA: a,
        nodeB: b,
        covered: e['covered'] == true,
        drawCanopy: e['canopy'] != false,
        indoor: e['indoor'] as String?,
        width: e['width'] == null ? 2.4 : _d(e['width']),
      ));
    }
  }
  allEdges = edges;

  // ---- điểm đến
  final pl = <Place>[];
  for (final p in _list(j['places'])) {
    final id = p['id'] as String;
    final doors = <String>[];
    for (final d in (p['doors'] as List? ?? const []).cast<String>()) {
      if (byId.containsKey(d)) {
        doors.add(d);
      } else {
        dataProblems.add('Điểm đến "$id": không có cửa "$d".');
      }
    }
    pl.add(Place(
      id: id,
      name: p['name'] as String,
      buildingId: p['building'] as String?,
      doorIds: doors,
      departments: _list(p['departments'])
          .map((d) => Department(
                d['floor'] == null ? null : (d['floor'] as num).toInt(),
                d['name'] as String,
                (d['keywords'] ?? '') as String,
              ))
          .toList(),
      keywords: (p['keywords'] ?? '') as String,
      note: p['note'] as String?,
    ));
  }
  places = pl;
  placeById = {for (final p in pl) p.id: p};

  quickSearches = _list(j['quickSearches'])
      .map((q) => (q['label'] as String, q['query'] as String, q['emergency'] == true))
      .toList();

  // ---- khối nhà
  final bl = <Building>[];
  final byBld = <String, String>{};
  for (final b in _list(j['buildings'])) {
    final id = b['id'] as String;
    final r = (b['rect'] as List).map(_d).toList();
    final BuildingKind kind;
    switch (b['kind']) {
      case 'clinic':
        kind = BuildingKind.clinic;
      case 'emergency':
        kind = BuildingKind.emergency;
      case 'parking':
        kind = BuildingKind.parking;
      default:
        kind = BuildingKind.support;
    }
    bl.add(Building(id, (b['label'] ?? '') as String, Rect.fromLTRB(r[0], r[1], r[2], r[3]),
        math.max(1, ((b['floors'] ?? 1) as num).toInt()), kind, b['info'] as String?));
    final place = b['place'] as String?;
    if (place != null) {
      if (placeById.containsKey(place)) {
        byBld[id] = place;
      } else {
        dataProblems.add('Khối nhà "$id": không có điểm đến "$place".');
      }
    }
  }
  buildings = bl;
  buildingById = {for (final b in bl) b.id: b};
  placeIdByBuilding = byBld;

  final gs = <GateShape>[];
  for (final g in _list(j['gates'])) {
    final place = g['place'] as String;
    if (!placeById.containsKey(place)) {
      dataProblems.add('Cổng: không có điểm đến "$place".');
      continue;
    }
    gs.add(GateShape(_d(g['x1']), _d(g['x2']), _d(g['y']), place));
  }
  gateShapes = gs;

  // ---- trang trí
  final decor = (j['decor'] as Map<String, dynamic>?) ?? <String, dynamic>{};
  final porch = decor['porch'] as List?;
  porchRect = porch == null ? null : Rect.fromLTRB(_d(porch[0]), _d(porch[1]), _d(porch[2]), _d(porch[3]));
  roadPolygon = _pts(decor['road']);
  roadCenterLine = _pts(decor['roadCenter']);
  staffShedPolygon = _pts(decor['staffShed']);
  staffShedPosts = _pts(decor['staffShedPosts']);
  textLabels = _list(decor['labels'])
      .map((l) => MapTextLabel(
            l['text'] as String,
            Offset(_d(l['x']), _d(l['y'])),
            height: l['height'] == null ? 0.5 : _d(l['height']),
            small: l['small'] == true,
          ))
      .toList();
}

// =====================================================================
// HƯỚNG NHÌN MẶC ĐỊNH KHI QUÉT QR
// =====================================================================
Map<String, String>? _doorBuildingCache;
Map<String, String> get _doorBuilding {
  final cached = _doorBuildingCache;
  if (cached != null) return cached;
  final m = <String, String>{};
  for (final p in places) {
    final b = p.buildingId;
    if (b == null) continue;
    for (final d in p.doorIds) {
      m.putIfAbsent(d, () => b);
    }
  }
  return _doorBuildingCache = m;
}

/// Hướng người quét đang nhìn khi link QR không có tham số h.
/// Ở cổng: nhìn vào trong khuôn viên. Ở cửa: nhìn vào tấm biển dán trên tường tòa nhà.
double defaultFacing(String nodeId) {
  final g = gateFacing[nodeId];
  if (g != null) return g;
  final n = nodeById[nodeId];
  final b = buildingById[_doorBuilding[nodeId]];
  if (n == null || b == null) return 0;
  final dx = b.rect.center.dx - n.x, dy = b.rect.center.dy - n.y;
  final ax = dx.abs() / b.rect.width, ay = dy.abs() / b.rect.height;
  if (ax > ay) return dx > 0 ? 90 : 270;
  return dy > 0 ? 180 : 0;
}

/// Đổi hướng la bàn (độ, 0 = Bắc) sang hướng trên sơ đồ.
double compassToMap(double compassDeg) => ((compassDeg - mapUpBearing) % 360 + 360) % 360;

/// Vector hướng trên sơ đồ (x sang phải, y xuống dưới) từ góc độ.
Offset facingVector(double deg) => Offset(math.sin(deg * math.pi / 180), -math.cos(deg * math.pi / 180));
