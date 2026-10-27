import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

/// Loại điểm trên bản đồ.
enum NodeType {
  gate, // Cổng ra vào
  door, // Cửa tòa nhà (điểm xuất phát / điểm đến)
  junction, // Ngã rẽ, chỉ dùng để nối đường
}

/// Một điểm trên bản đồ. Tọa độ x, y tính theo pixel của sơ đồ gốc
/// (ảnh map_benhvien.png khổ ~2180 x 1690).
class MapNode {
  final String id; // Mã duy nhất, dùng trong link QR (?start=...)
  final String name; // Tên hiển thị
  final double x;
  final double y;
  final NodeType type;

  /// Tên mốc dùng trong câu chỉ dẫn, ví dụ "ngã tư trước Sảnh đón xe".
  final String landmark;

  final double? lat;
  final double? lng;

  const MapNode({
    required this.id,
    required this.name,
    required this.x,
    required this.y,
    required this.type,
    String? landmark,
    this.lat,
    this.lng,
  }) : landmark = landmark ?? name;

  Offset get pos => Offset(x, y);

  /// Tên đọc trong câu chỉ dẫn: ngã rẽ dùng tên mốc, cửa và cổng dùng tên riêng.
  String get spokenName => type == NodeType.junction ? landmark : name;
}

/// Một đoạn đường nối 2 điểm.
class MapEdge {
  final MapNode nodeA;
  final MapNode nodeB;

  /// Có mái che (hành lang).
  final bool covered;

  /// Vẽ mái che riêng cho đoạn này hay không (sảnh đón xe đã có mái riêng).
  final bool drawCanopy;

  /// Đoạn đi xuyên trong nhà, ví dụ "sảnh tầng 1 Tòa A1". null nếu đi ngoài trời.
  final String? indoor;

  /// Bề rộng khi vẽ (đơn vị 3D).
  final double width;

  const MapEdge({
    required this.nodeA,
    required this.nodeB,
    this.covered = false,
    this.drawCanopy = true,
    this.indoor,
    this.width = 2.4,
  });

  /// Khoảng cách theo pixel sơ đồ (định lý Pytago, như bản cũ).
  double get weight => math.sqrt(math.pow(nodeA.x - nodeB.x, 2) + math.pow(nodeA.y - nodeB.y, 2));

  /// Chi phí cho thuật toán: đi trong nhà hơi bất tiện, hành lang mái che được ưu tiên nhẹ.
  double get cost => weight * (indoor != null ? 1.15 : (covered ? 0.95 : 1.0));

  MapNode other(MapNode n) => identical(n, nodeA) ? nodeB : nodeA;
}

/// Một khoa / phòng nằm ở một tầng của tòa nhà.
class Department {
  final int? floor; // null nếu chưa rõ tầng
  final String name;
  final String keywords; // từ khóa tìm kiếm không dấu

  const Department(this.floor, this.name, [this.keywords = '']);
}

/// Điểm đến mà người bệnh tìm được: một tòa nhà, một phòng, một cổng...
class Place {
  final String id;
  final String name;
  final String? buildingId;

  /// Các cửa vào. Thuật toán tự chọn cửa gần người đi nhất.
  final List<String> doorIds;
  final List<Department> departments;
  final String keywords;
  final String? note;

  const Place({
    required this.id,
    required this.name,
    this.buildingId,
    required this.doorIds,
    this.departments = const [],
    this.keywords = '',
    this.note,
  });
}

enum BuildingKind { clinic, emergency, support, parking }

/// Khối nhà để vẽ 3D. rect tính theo pixel sơ đồ.
class Building {
  final String id;
  final String label;
  final Rect rect;
  final int floors;
  final BuildingKind kind;
  final String? info;

  const Building(this.id, this.label, this.rect, this.floors, this.kind, [this.info]);
}

/// Cổng có khung để vẽ 3D.
class GateShape {
  final double x1, x2, y;
  final String placeId;
  const GateShape(this.x1, this.x2, this.y, this.placeId);
}

/// Chữ ghi trên mặt đất / trên mái.
class MapTextLabel {
  final String text;
  final Offset pos;
  final double height;
  final bool small;
  const MapTextLabel(this.text, this.pos, {this.height = 0.5, this.small = false});
}
