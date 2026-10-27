import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'main.dart';
import 'map_data.dart';

// =================================================================
// MÀN HÌNH ADMIN: TẠO QR CHO CÁC CỔNG VÀ CỬA, KÈM HƯỚNG NHÌN (tham số h)
// Mở bằng đường dẫn  <tên miền>/#/admin-qr
// =================================================================
class AdminQrScreen extends StatefulWidget {
  const AdminQrScreen({super.key});

  @override
  State<AdminQrScreen> createState() => _AdminQrScreenState();
}

class _AdminQrScreenState extends State<AdminQrScreen> {
  /// Hướng người đứng quét đang nhìn, tính theo sơ đồ.
  static const _dirs = <(double, String)>[
    (0, '↑'), (45, '↗'), (90, '→'), (135, '↘'), (180, '↓'), (225, '↙'), (270, '←'), (315, '↖'),
  ];

  final Map<String, double> _facing = {for (final n in displayNodes) n.id: defaultFacing(n.id)};

  String _url(String id) => '$appDomain/?start=$id&h=${_facing[id]!.round()}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kho QR Code (Nội bộ IT)'),
        backgroundColor: Colors.blueGrey,
        foregroundColor: Colors.white,
      ),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (dataProblems.isNotEmpty)
          Container(
            color: Colors.red.shade50,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: Text(
              'map_data.json có ${dataProblems.length} lỗi:\n${dataProblems.join('\n')}',
              style: TextStyle(color: Colors.red.shade900, height: 1.5),
            ),
          ),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: Text(
            'Với mỗi tấm biển, chọn mũi tên chỉ hướng mà người đứng quét mã đang nhìn (từ người tới tấm biển). '
            'Mũi tên tính theo sơ đồ: ↑ về phía Tòa E · ↓ về phía đường Tôn Thất Tùng · '
            '→ về phía Tòa D, Khoa Nhiệt đới · ← về phía Tòa F, B2. '
            'Bấm "Xem thử" để kiểm tra câu chỉ dẫn đầu tiên trước khi in.',
            style: TextStyle(height: 1.5),
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(20),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 260,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 0.58,
            ),
            itemCount: displayNodes.length,
            itemBuilder: (context, index) {
              final node = displayNodes[index];
              final h = _facing[node.id]!;
              return Card(
                elevation: 3,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(children: [
                    Expanded(
                      child: QrImageView(
                        data: _url(node.id),
                        version: QrVersions.auto,
                        backgroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(node.name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15), textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    Row(children: [
                      for (final d in _dirs)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 1.5),
                            child: Material(
                              color: d.$1 == h ? Colors.blue.shade700 : Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                                side: BorderSide(color: Colors.grey.shade400),
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(6),
                                onTap: () => setState(() => _facing[node.id] = d.$1),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 5),
                                  child: Text(d.$2,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(fontSize: 15, color: d.$1 == h ? Colors.white : null)),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ]),
                    const SizedBox(height: 6),
                    SelectableText(
                      '?start=${node.id}&h=${h.round()}',
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => HospitalMapScreen(initialStartId: node.id, initialFacing: h),
                      )),
                      child: const Text('Xem thử trên bản đồ'),
                    ),
                  ]),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}
