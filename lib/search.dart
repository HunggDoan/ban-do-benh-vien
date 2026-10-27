import 'map_data.dart';
import 'map_models.dart';

/// Bỏ dấu tiếng Việt (giữ nguyên cách làm của bản cũ).
String removeVietnameseTones(String input) {
  var str = input;
  str = str.replaceAll(RegExp(r'[àáạảãâầấậẩẫăằắặẳẵ]'), 'a');
  str = str.replaceAll(RegExp(r'[ÀÁẠẢÃÂẦẤẬẨẪĂẰẮẶẲẴ]'), 'A');
  str = str.replaceAll(RegExp(r'[èéẹẻẽêềếệểễ]'), 'e');
  str = str.replaceAll(RegExp(r'[ÈÉẸẺẼÊỀẾỆỂỄ]'), 'E');
  str = str.replaceAll(RegExp(r'[ìíịỉĩ]'), 'i');
  str = str.replaceAll(RegExp(r'[ÌÍỊỈĨ]'), 'I');
  str = str.replaceAll(RegExp(r'[òóọỏõôồốộổỗơờớợởỡ]'), 'o');
  str = str.replaceAll(RegExp(r'[ÒÓỌỎÕÔỒỐỘỔỖƠỜỚỢỞỠ]'), 'O');
  str = str.replaceAll(RegExp(r'[ùúụủũưừứựửữ]'), 'u');
  str = str.replaceAll(RegExp(r'[ÙÚỤỦŨƯỪỨỰỬỮ]'), 'U');
  str = str.replaceAll(RegExp(r'[ỳýỵỷỹ]'), 'y');
  str = str.replaceAll(RegExp(r'[ỲÝỴỶỸ]'), 'Y');
  str = str.replaceAll(RegExp(r'[đ]'), 'd');
  str = str.replaceAll(RegExp(r'[Đ]'), 'D');
  return str;
}

/// Chuẩn hóa để so khớp: chữ thường, không dấu, bỏ ký tự phân cách.
String normalizeText(String s) => removeVietnameseTones(s.toLowerCase())
    .replaceAll(RegExp(r'[–\-_,&()·.]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Một dòng kết quả tìm kiếm: hoặc cả điểm đến, hoặc một khoa trong điểm đến đó.
class SearchEntry {
  final Place place;
  final Department? dept;
  final String title;
  final String subtitle;
  final String _haystack;
  final String _normTitle;

  SearchEntry(this.place, this.dept, this.title, this.subtitle, String haystack)
      : _haystack = normalizeText(haystack),
        _normTitle = normalizeText(title);
}

final List<SearchEntry> searchIndex = () {
  final list = <SearchEntry>[];
  for (final p in places) {
    final isGate = p.doorIds.isNotEmpty && nodeById[p.doorIds.first]?.type == NodeType.gate;
    final sub = p.departments.isNotEmpty ? '${p.departments.length} khoa, phòng' : (isGate ? 'Cổng' : 'Điểm đến');
    list.add(SearchEntry(p, null, p.name, sub, '${p.name} ${p.keywords}'));
    for (final d in p.departments) {
      final sub = '${d.floor != null ? 'Tầng ${d.floor} · ' : ''}${p.name}';
      list.add(SearchEntry(p, d, d.name, sub, '${d.name} ${p.name} ${d.keywords}'));
    }
  }
  return list;
}();

/// Tìm theo mọi từ người dùng gõ (không cần dấu, không cần đúng thứ tự).
List<SearchEntry> searchPlaces(String query) {
  final q = normalizeText(query);
  if (q.isEmpty) return const [];
  final tokens = q.split(' ');
  int rank(SearchEntry e) {
    if (e._normTitle.startsWith(q)) return 0;
    if (e._normTitle.contains(q)) return 1;
    return e.dept != null ? 2 : 3;
  }

  final hits = searchIndex.where((e) => tokens.every(e._haystack.contains)).toList();
  hits.sort((a, b) {
    final r = rank(a).compareTo(rank(b));
    if (r != 0) return r;
    return (a.dept != null ? 0 : 1).compareTo(b.dept != null ? 0 : 1);
  });
  return hits.take(40).toList();
}
