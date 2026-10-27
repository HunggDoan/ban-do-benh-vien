import 'map_data.dart';
import 'map_models.dart';

class _Adj {
  final MapNode to;
  final MapEdge edge;
  const _Adj(this.to, this.edge);
}

/// Danh sách kề, dựng một lần cho cả ứng dụng.
final Map<String, List<_Adj>> _adjacency = () {
  final m = <String, List<_Adj>>{for (final n in allNodes) n.id: <_Adj>[]};
  for (final e in allEdges) {
    m[e.nodeA.id]!.add(_Adj(e.nodeB, e));
    m[e.nodeB.id]!.add(_Adj(e.nodeA, e));
  }
  return m;
}();

/// Một tuyến đường: danh sách điểm và các đoạn nối giữa chúng.
class RouteResult {
  final List<MapNode> nodes;
  final List<MapEdge> edges;
  const RouteResult(this.nodes, this.edges);

  double get lengthPixels => edges.fold(0.0, (s, e) => s + e.weight);
  double get lengthMeters => lengthPixels * metersPerPixel;
}

/// Kết quả Dijkstra từ một điểm xuất phát tới mọi điểm khác.
class ShortestPaths {
  final MapNode start;
  final Map<String, double> dist;
  final Map<String, _Adj> _prev; // _Adj.to ở đây là điểm đứng trước

  ShortestPaths._(this.start, this.dist, this._prev);

  bool canReach(String id) => (dist[id] ?? double.infinity).isFinite;

  RouteResult? routeTo(String id) {
    if (!canReach(id)) return null;
    final nodes = <MapNode>[nodeById[id]!];
    final edges = <MapEdge>[];
    var cur = id;
    while (cur != start.id) {
      final p = _prev[cur]!;
      edges.insert(0, p.edge);
      nodes.insert(0, p.to);
      cur = p.to.id;
    }
    return RouteResult(nodes, edges);
  }
}

/// Thuật toán Dijkstra (đồ thị nhỏ nên dùng bản O(V²) cho dễ đọc).
ShortestPaths dijkstra(MapNode start) {
  final dist = <String, double>{for (final n in allNodes) n.id: double.infinity};
  final prev = <String, _Adj>{};
  final done = <String>{};
  dist[start.id] = 0;

  while (true) {
    String? u;
    var best = double.infinity;
    dist.forEach((k, d) {
      if (!done.contains(k) && d < best) {
        best = d;
        u = k;
      }
    });
    if (u == null) break; // các điểm còn lại không tới được
    final cur = u!;
    done.add(cur);
    for (final a in _adjacency[cur]!) {
      final nd = best + a.edge.cost;
      if (nd < dist[a.to.id]!) {
        dist[a.to.id] = nd;
        prev[a.to.id] = _Adj(nodeById[cur]!, a.edge);
      }
    }
  }
  return ShortestPaths._(start, dist, prev);
}

/// Tìm đường tới một điểm đến có nhiều cửa: chọn cửa gần người đi nhất.
RouteResult? routeToPlace(MapNode start, Place place) {
  final sp = dijkstra(start);
  String? best;
  for (final d in place.doorIds) {
    if (!sp.canReach(d)) continue;
    if (best == null || sp.dist[d]! < sp.dist[best]!) best = d;
  }
  return best == null ? null : sp.routeTo(best);
}

/// Kiểm tra dữ liệu: các điểm chưa có đường nối tới Cổng chính.
List<String> findUnreachable() {
  final root = nodeById['cong_chinh'] ?? (allNodes.isEmpty ? null : allNodes.first);
  if (root == null) return const [];
  final sp = dijkstra(root);
  return [
    for (final n in allNodes)
      if (!sp.canReach(n.id)) 'Điểm "${n.id}" chưa có đường nối tới ${root.name}.',
  ];
}

/// Giữ lại hàm cũ để các đoạn code khác vẫn gọi được.
List<MapNode> findShortestPath(MapNode start, MapNode end, List<MapNode> nodes, List<MapEdge> edges) {
  return dijkstra(start).routeTo(end.id)?.nodes ?? <MapNode>[];
}
