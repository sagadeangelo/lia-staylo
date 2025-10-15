// lib/upload_service.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class UploadService {
  UploadService({String? baseUrl})
      : baseUrl = (baseUrl ?? 'http://127.0.0.1:8000').replaceAll(RegExp(r'/+$'), '');

  final String baseUrl;

  // ---------- Helpers ----------
  Uri _u(String path, [Map<String, dynamic>? q]) {
    final qp = <String, String>{};
    (q ?? {}).forEach((k, v) {
      if (v != null) qp[k] = '$v';
    });
    return Uri.parse('$baseUrl$path').replace(queryParameters: qp.isEmpty ? null : qp);
  }

  // ---------- Analyze ----------
  Future<Map<String, dynamic>> analyzeText({
    required String text,
    String lang = 'es-MX',
    String? variant,
  }) async {
    final res = await http.post(
      _u('/analyze_text'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'text': text, 'lang': lang, 'variant': variant}),
    );
    if (res.statusCode != 200) {
      throw Exception('AnalyzeText falló: ${res.statusCode} ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> analyzeFile({
    required List<int> bytes,
    required String filename,
    String lang = 'es-MX',
  }) async {
    final req = http.MultipartRequest('POST', _u('/analyze/file'));
    req.fields['lang'] = lang;
    req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final streamed = await req.send();
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode != 200) {
      throw Exception('AnalyzeFile falló: ${res.statusCode} ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ---------- Apply ----------
  Future<String> applySafe({required String text, String lang = 'es-MX'}) async {
    final res = await http.post(
      _u('/apply/safe'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'text': text, 'lang': lang}),
    );
    if (res.statusCode != 200) {
      throw Exception('applySafe falló: ${res.statusCode} ${res.body}');
    }
    return (jsonDecode(res.body) as Map<String, dynamic>)['new_text'] as String;
  }

  Future<String> applyAll({required String text, String lang = 'es-MX'}) async {
    final res = await http.post(
      _u('/apply/all'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'text': text, 'lang': lang}),
    );
    if (res.statusCode != 200) {
      throw Exception('applyAll falló: ${res.statusCode} ${res.body}');
    }
    return (jsonDecode(res.body) as Map<String, dynamic>)['new_text'] as String;
  }

  // ---------- Suggest ----------
  Future<String> suggest({required String text}) async {
    final res = await http.post(
      _u('/suggest'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'text': text}),
    );
    if (res.statusCode != 200) {
      throw Exception('suggest falló: ${res.statusCode} ${res.body}');
    }
    return (jsonDecode(res.body) as Map<String, dynamic>)['suggestion'] as String;
  }

  // ---------- Diccionario ----------
  Future<List<String>> dictionaryList({required String lang}) async {
    final res = await http.get(_u('/dictionary/list', {'lang': lang}));
    if (res.statusCode != 200) {
      throw Exception('dictionaryList falló: ${res.statusCode} ${res.body}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final words = (data['words'] as List).map((e) => e.toString()).toList();
    return words;
  }

  Future<bool> dictionaryAdd({required String lang, required String token}) async {
    final res = await http.post(
      _u('/dictionary/add'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'token': token, 'lang': lang}),
    );
    if (res.statusCode != 200) {
      throw Exception('dictionaryAdd falló: ${res.statusCode} ${res.body}');
    }
    return true;
  }

  Future<bool> dictionaryRemove({required String lang, required String token}) async {
    final res = await http.post(
      _u('/dictionary/remove'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'token': token, 'lang': lang}),
    );
    if (res.statusCode != 200) {
      throw Exception('dictionaryRemove falló: ${res.statusCode} ${res.body}');
    }
    return true;
  }

  // ---------- Export ----------
  Future<Uint8List> exportDocx({required String text, String lang = 'es-MX'}) async {
    final res = await http.post(
      _u('/export/docx'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'text': text, 'lang': lang}),
    );
    if (res.statusCode != 200) {
      throw Exception('exportDocx falló: ${res.statusCode}');
    }
    return Uint8List.fromList(res.bodyBytes);
  }
}
