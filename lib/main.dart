import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'directions.dart';
import 'map3d_view.dart';
import 'map_data.dart';
import 'map_models.dart';
import 'path_finder.dart';
import 'qr.dart';
import 'search.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await loadMapData();
    dataProblems.addAll(findUnreachable());
    if (dataProblems.isNotEmpty) {
      debugPrint('Lỗi dữ liệu map_data.json:\n${dataProblems.join('\n')}');
    }
    runApp(const HospitalMapApp());
  } catch (e) {
    // File JSON sai cú pháp (thiếu dấu phẩy, ngoặc...) sẽ báo ở đây
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Không đọc được dữ liệu bản đồ (public/map_data.json):\n\n$e',
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ),
      ),
    );
  }
}

class HospitalMapApp extends StatelessWidget {
  const HospitalMapApp({super.key});

  Route<dynamic> _route(RouteSettings settings) {
    // Link QR có dạng /#/?start=... nên chỉ xét phần đường dẫn, bỏ qua tham số
    final path = Uri.tryParse(settings.name ?? '/')?.path ?? '/';
    if (path == '/admin-qr') {
      return MaterialPageRoute(
        builder: (_) => const AdminQrScreen(),
        settings: settings,
      );
    }
    return MaterialPageRoute(
      builder: (_) => const HospitalMapScreen(),
      settings: settings,
    );
  }

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF3465BA);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Bản đồ Bệnh viện Sản Nhi',
      theme: ThemeData(
        colorSchemeSeed: seed,
        brightness: Brightness.light,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: seed,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      onGenerateRoute: _route,
      // Chỉ tạo đúng một màn hình ban đầu (tránh Flutter web tách "/?start=x" thành 2 màn hình)
      onGenerateInitialRoutes: (name) => [_route(RouteSettings(name: name))],
    );
  }
}

enum _SheetMode { route, place, info }

class HospitalMapScreen extends StatefulWidget {
  /// Dùng khi mở từ trang QR để xem thử; bình thường để trống và đọc từ link.
  final String? initialStartId;
  final double? initialFacing;
  const HospitalMapScreen({super.key, this.initialStartId, this.initialFacing});

  @override
  State<HospitalMapScreen> createState() => _HospitalMapScreenState();
}

class _HospitalMapScreenState extends State<HospitalMapScreen> {
  final _map = Map3DController();
  final _searchCtl = TextEditingController();
  final _searchFocus = FocusNode();

  String _startId = 'cong_chinh';
  double _facing = 0; // hướng người đang nhìn trên sơ đồ (độ)

  List<SearchEntry> _results = const [];
  bool _showResults = false;

  _SheetMode? _sheet;
  bool _collapsed = false;
  Place? _place;
  Department? _dept;
  RouteResult? _route;
  Directions? _dirs;
  String? _highlight;
  String _infoTitle = '', _infoText = '';

  @override
  void initState() {
    super.initState();
    String? message;
    String? toPlace;
    if (widget.initialStartId != null) {
      _startId = widget.initialStartId!;
      _facing = widget.initialFacing ?? defaultFacing(_startId);
    } else {
      final p = _readParams();
      toPlace = p.to;
      _facing = p.h ?? 0;
      final start = p.start;
      if (start != null) {
        final n = nodeById[start];
        if (n != null && n.type != NodeType.junction) {
          _startId = start;
        } else if (oldNodeIds.containsKey(start) && oldNodeIds[start] == null) {
          message = 'Tòa C đã ngừng sử dụng. Vị trí xuất phát được đặt tại Cổng chính, bạn có thể đổi ở ô phía trên.';
        } else if (n != null || oldNodeIds.containsKey(start)) {
          message = 'Mã QR này không gắn với cửa hay cổng nào. Vui lòng chọn vị trí của bạn ở ô phía trên.';
        } else {
          message = 'Không nhận ra mã QR. Vị trí xuất phát đang là Cổng chính, bạn có thể đổi ở ô phía trên.';
        }
        if (_startId != start) _facing = defaultFacing(_startId);
        _logScan(nodeById[_startId]!);
      }
      if (p.h == null) _facing = defaultFacing(_startId);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final dest = toPlace == null ? null : placeById[toPlace];
      if (dest != null) {
        _searchCtl.text = dest.name;
        _showRouteTo(dest, null);
      } else {
        _fitStart();
      }
      if (message != null) _toast(message);
    });
  }

  @override
  void dispose() {
    _map.dispose();
    _searchCtl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // ---------------- đọc link QR ----------------
  ({String? start, String? to, double? h}) _readParams() {
    final uri = Uri.base;
    String? start = uri.queryParameters['start'];
    String? to = uri.queryParameters['to'];
    String? h = uri.queryParameters['h'];
    // Flutter web dùng dấu /#/ nên tham số có thể nằm sau dấu #
    if (uri.hasFragment) {
      final frag = uri.fragment;
      final qi = frag.indexOf('?');
      if (qi >= 0) {
        final qp = Uri.splitQueryString(frag.substring(qi + 1));
        start ??= qp['start'];
        to ??= qp['to'];
        h ??= qp['h'];
      } else if (nodeById.containsKey(frag)) {
        start ??= frag;
      }
    }
    final hv = double.tryParse(h ?? '');
    return (
      start: start,
      to: to,
      h: hv == null ? null : ((hv % 360) + 360) % 360,
    );
  }

  /// Ghi nhận lượt quét lên Google Sheets (không chờ, không làm đơ ứng dụng).
  void _logScan(MapNode n) {
    final url = Uri.parse(logScriptUrl)
        .replace(queryParameters: {'location': n.name, 'id': n.id});
    http.get(url).then((_) {}, onError: (Object _) {});
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 6)),
      );
  }

  // ---------------- điểm xuất phát ----------------
  void _setStart(String id, double? h) {
    setState(() {
      _startId = id;
      _facing = h ?? defaultFacing(id);
    });
    final place = _place;
    if (_sheet == _SheetMode.route && place != null) {
      _showRouteTo(place, _dept);
    } else {
      _fitStart();
    }
  }

  void _fitStart() {
    final n = nodeById[_startId]!;
    final d = facingVector(_facing);
    _map.fit([n.pos, n.pos + d * 300], _facing, minSize: 40);
  }

  // ---------------- tìm kiếm ----------------
  void _onQuery(String v) {
    setState(() {
      _results = searchPlaces(v);
      _showResults = v.trim().isNotEmpty;
    });
  }

  void _quick(String query, String label) {
    _searchCtl.text = label;
    final r = searchPlaces(query);
    if (r.length == 1) {
      _choose(r.first);
    } else {
      setState(() {
        _results = r;
        _showResults = true;
      });
    }
  }

  void _choose(SearchEntry e) {
    _searchCtl.text = e.title;
    _searchFocus.unfocus();
    setState(() => _showResults = false);
    _showRouteTo(e.place, e.dept);
  }

  void _clearSearch() {
    _searchCtl.clear();
    setState(() {
      _results = const [];
      _showResults = false;
    });
  }

  // ---------------- chỉ đường ----------------
  void _showRouteTo(Place place, Department? dept) {
    final r = routeToPlace(nodeById[_startId]!, place);
    setState(() {
      _sheet = _SheetMode.route;
      _collapsed = false;
      _place = place;
      _dept = dept;
      _route = r;
      _dirs = r == null ? null : buildDirections(r, dept, facing: _facing);
      _highlight = place.buildingId;
    });
    if (r != null) _fitRoute(r);
  }

  void _fitRoute(RouteResult r) =>
      _map.fit(r.nodes.map((n) => n.pos).toList(), _facing, minSize: 30);

  void _openPlace(Place place) {
    setState(() {
      _sheet = _SheetMode.place;
      _collapsed = false;
      _place = place;
      _dept = null;
      _route = null;
      _dirs = null;
      _highlight = place.buildingId;
    });
  }

  void _tapBuilding(String id) {
    final pid = placeIdByBuilding[id];
    if (pid != null) {
      _openPlace(placeById[pid]!);
      return;
    }
    final b = buildingById[id]!;
    setState(() {
      _sheet = _SheetMode.info;
      _collapsed = false;
      _route = null;
      _dirs = null;
      _highlight = id;
      _infoTitle = b.label.isEmpty ? 'Công trình phụ' : b.label;
      _infoText = b.info ?? '';
    });
  }

  void _closeSheet() {
    setState(() {
      _sheet = null;
      _place = null;
      _dept = null;
      _route = null;
      _dirs = null;
      _highlight = null;
    });
    _clearSearch();
    _fitStart();
  }

  // ---------------- giao diện ----------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bản đồ Bệnh viện Sản Nhi'),
        backgroundColor: const Color(0xFF3465BA),
        foregroundColor: Colors.white,
        toolbarHeight: 48,
      ),
      body: LayoutBuilder(
        builder: (context, c) {
          final wide = c.maxWidth > 720;
          final sheetOpen = _sheet != null;
          final sheetMax = c.maxHeight * 0.48;
          final insets = wide
              ? EdgeInsets.only(left: sheetOpen ? 430 : 0)
              : EdgeInsets.only(
                  top: 150,
                  bottom: sheetOpen ? (_collapsed ? 150 : sheetMax) : 0,
                );
          final route = _route;
          final dept = _dept;
          final place = _place;
          final destLabel = place == null
              ? null
              : (dept != null && dept.floor != null
                    ? '${place.name} · Tầng ${dept.floor}'
                    : place.name);

          final map = Listener(
            onPointerDown: (_) {
              if (_showResults || _searchFocus.hasFocus) {
                _searchFocus.unfocus();
                setState(() => _showResults = false);
              }
            },
            child: Map3DView(
              controller: _map,
              startNodeId: _startId,
              facingDeg: _facing,
              routeNodeIds: route?.nodes.map((n) => n.id).toList() ?? const [],
              destNodeId: route?.nodes.last.id,
              destLabel: destLabel,
              highlightBuildingId: _highlight,
              insets: insets,
              onTapBuilding: _tapBuilding,
              onTapGate: (pid) => _openPlace(placeById[pid]!),
            ),
          );

          return Stack(
            children: [
              Positioned.fill(child: map),
              if (wide)
                Positioned(
                  top: 12,
                  left: 16,
                  width: 400,
                  bottom: 12,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _searchCard(showChips: true),
                      if (_showResults)
                        Flexible(child: _resultsCard())
                      else if (sheetOpen) ...[
                        const SizedBox(height: 8),
                        Flexible(child: _sheetCard()),
                      ],
                    ],
                  ),
                )
              else ...[
                if (sheetOpen)
                  Positioned(
                    left: 8,
                    right: 8,
                    bottom: 8,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: sheetMax),
                      child: _sheetCard(),
                    ),
                  ),
                Positioned(
                  top: 8,
                  left: 12,
                  right: 12,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _searchCard(showChips: !sheetOpen),
                      if (_showResults)
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: c.maxHeight * 0.55,
                          ),
                          child: _resultsCard(),
                        ),
                    ],
                  ),
                ),
              ],
              Positioned(
                right: 12,
                top: wide ? c.maxHeight / 2 - 120 : 175,
                child: _viewButtons(),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _searchCard({required bool showChips}) {
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurfaceVariant;
    return Card(
      elevation: 4,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 6, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.my_location, size: 18, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                Text(
                  'Bạn đang ở',
                  style: TextStyle(fontSize: 13, color: muted),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      isDense: true,
                      value: _startId,
                      items: displayNodes
                          .map(
                            (n) => DropdownMenuItem<String>(
                              value: n.id,
                              child: Text(
                                n.name,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) _setStart(v, null);
                      },
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 14),
            Row(
              children: [
                Icon(Icons.search, color: Colors.red.shade600),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchCtl,
                    focusNode: _searchFocus,
                    style: const TextStyle(fontSize: 16),
                    textInputAction: TextInputAction.search,
                    decoration: const InputDecoration(
                      hintText: 'Tìm khoa, phòng hoặc tòa nhà…',
                      border: InputBorder.none,
                      isDense: true,
                    ),
                    onChanged: _onQuery,
                    onSubmitted: (_) {
                      if (_results.isNotEmpty) _choose(_results.first);
                    },
                    onTap: () {
                      if (_searchCtl.text.trim().isNotEmpty)
                        _onQuery(_searchCtl.text);
                    },
                  ),
                ),
                if (_searchCtl.text.isNotEmpty)
                  IconButton(
                    tooltip: 'Xóa ô tìm kiếm',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close),
                    onPressed: _clearSearch,
                  ),
              ],
            ),
            if (showChips) ...[
              const SizedBox(height: 6),
              SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final q in quickSearches)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ActionChip(
                          visualDensity: VisualDensity.compact,
                          label: Text(
                            q.$1,
                            style: TextStyle(
                              color: q.$3 ? Colors.red.shade700 : null,
                            ),
                          ),
                          onPressed: () => _quick(q.$2, q.$1),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _resultsCard() {
    final q = _searchCtl.text.trim();
    return Card(
      margin: const EdgeInsets.only(top: 8),
      elevation: 4,
      child: _results.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                'Không tìm thấy “$q”. Thử gõ ngắn hơn, ví dụ “sản”, “nhi”, “xét nghiệm”, hoặc hỏi quầy hướng dẫn gần nhất.',
                style: const TextStyle(fontSize: 14, height: 1.5),
              ),
            )
          : ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: _results.length,
              itemBuilder: (context, i) {
                final e = _results[i];
                return ListTile(
                  title: Text(
                    e.title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(e.subtitle),
                  onTap: () => _choose(e),
                );
              },
            ),
    );
  }

  Widget _sheetCard() {
    final cs = Theme.of(context).colorScheme;
    final routeColor = Colors.red.shade700;
    String eyebrow = '', title = '', sub = '';
    String? summary;
    Widget? body;
    final actions = <Widget>[];
    final small = OutlinedButton.styleFrom(
      visualDensity: VisualDensity.compact,
    );

    switch (_sheet) {
      case _SheetMode.route:
        final place = _place!, dept = _dept, route = _route, dirs = _dirs;
        eyebrow = 'CHỈ ĐƯỜNG';
        title = dept?.name ?? place.name;
        sub = dept != null
            ? '${dept.floor != null ? 'Tầng ${dept.floor} · ' : ''}${place.name}'
            : (place.note ?? '');
        if (route == null || dirs == null) {
          body = const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Chưa có lối đi nối từ vị trí của bạn tới điểm này trong dữ liệu. Vui lòng hỏi nhân viên hoặc quầy hướng dẫn gần nhất.',
            ),
          );
        } else {
          summary = route.edges.isEmpty
              ? 'Bạn đang ở ngay đây'
              : 'Khoảng ${dirs.minutes} phút đi bộ · ${formatMeters(dirs.meters)}';
          actions.add(
            OutlinedButton(
              style: small,
              onPressed: () => setState(() => _collapsed = !_collapsed),
              child: Text(_collapsed ? 'Xem các bước' : 'Thu gọn'),
            ),
          );
          actions.add(
            OutlinedButton(
              style: small,
              onPressed: () => _fitRoute(route),
              child: const Text('Xem toàn tuyến'),
            ),
          );
          body = ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
            itemCount: dirs.steps.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, i) => _stepTile(dirs.steps[i]),
          );
        }
      case _SheetMode.place:
        final place = _place!;
        final isGate = place.doorIds.any(
          (d) => nodeById[d]?.type == NodeType.gate,
        );
        eyebrow = isGate ? 'CỔNG' : 'TÒA NHÀ';
        title = place.name;
        sub = place.note ?? '';
        actions.add(
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: routeColor,
              visualDensity: VisualDensity.compact,
            ),
            onPressed: () {
              _searchCtl.text = place.name;
              _showRouteTo(place, null);
            },
            child: const Text('Chỉ đường tới đây'),
          ),
        );
        if (place.departments.isNotEmpty) body = _floorList(place);
      case _SheetMode.info:
        eyebrow = 'CÔNG TRÌNH';
        title = _infoTitle;
        sub = _infoText;
      case null:
        return const SizedBox.shrink();
    }
    actions.add(
      OutlinedButton(
        style: small,
        onPressed: _closeSheet,
        child: const Text('Đóng'),
      ),
    );

    return Card(
      elevation: 6,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eyebrow,
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
                if (sub.isNotEmpty)
                  Text(
                    sub,
                    style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
                  ),
                if (summary != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      summary,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: routeColor,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: actions),
              ],
            ),
          ),
          if (!_collapsed && body != null) ...[
            const Divider(height: 1),
            Flexible(child: body),
          ],
        ],
      ),
    );
  }

  Widget _stepTile(DirectionStep s) {
    final routeColor = Colors.red.shade700;
    final startColor = Colors.blue.shade700;
    final IconData icon;
    Color fg = Theme.of(context).colorScheme.onSurface;
    switch (s.kind) {
      case StepKind.start:
        icon = Icons.trip_origin;
        fg = startColor;
      case StepKind.straight:
        icon = Icons.straight;
      case StepKind.left:
        icon = Icons.turn_left;
      case StepKind.right:
        icon = Icons.turn_right;
      case StepKind.back:
        icon = Icons.u_turn_left;
      case StepKind.end:
        icon = Icons.location_on;
        fg = routeColor;
      case StepKind.floor:
        icon = Icons.stairs;
        fg = routeColor;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 17,
            backgroundColor: fg.withValues(alpha: 0.13),
            child: Icon(icon, size: 20, color: fg),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text.rich(
                _rich(s.text),
                style: const TextStyle(fontSize: 16, height: 1.45),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Chuyển "**chữ đậm**" thành TextSpan in đậm.
  TextSpan _rich(String text) {
    final parts = text.split('**');
    return TextSpan(
      children: [
        for (var i = 0; i < parts.length; i++)
          TextSpan(
            text: parts[i],
            style: i.isOdd
                ? const TextStyle(fontWeight: FontWeight.w700)
                : null,
          ),
      ],
    );
  }

  Widget _floorList(Place place) {
    final byFloor = <int, List<String>>{};
    for (final d in place.departments) {
      final list = byFloor.putIfAbsent(d.floor ?? 0, () => <String>[]);
      if (!list.contains(d.name)) list.add(d.name);
    }
    final floors = byFloor.keys.toList()..sort();
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      children: [
        for (final f in floors)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 72,
                  child: Text(
                    f == 0 ? 'Trong tòa' : 'Tầng $f',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: muted,
                      fontSize: 14,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    byFloor[f]!.join(', '),
                    style: const TextStyle(fontSize: 14, height: 1.45),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _viewButtons() {
    final cs = Theme.of(context).colorScheme;
    Widget btn(String label, bool on, VoidCallback onTap) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: on ? cs.primary : cs.surface,
        elevation: 3,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: on ? cs.onPrimary : cs.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
    Widget icon(IconData i, String tip, VoidCallback onTap) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: cs.surface,
        elevation: 3,
        borderRadius: BorderRadius.circular(10),
        child: IconButton(
          tooltip: tip,
          visualDensity: VisualDensity.compact,
          icon: Icon(i, size: 20),
          onPressed: onTap,
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        btn('3D', !_map.topView, () => setState(() => _map.setTopView(false))),
        btn(
          'Từ trên',
          _map.topView,
          () => setState(() => _map.setTopView(true)),
        ),
        btn('Toàn cảnh', false, _map.overview),
        icon(Icons.rotate_left, 'Xoay trái', () => _map.rotateBy(-0.4)),
        icon(Icons.rotate_right, 'Xoay phải', () => _map.rotateBy(0.4)),
      ],
    );
  }
}
