import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../models/domain.dart';

class ApiError extends DomainError {
  ApiError(super.message, this.status);
  final int status;
}

class ApiClient {
  ApiClient({http.Client? client, String? baseUrl})
    : client = client ?? http.Client(),
      baseUrl =
          (baseUrl ??
                  const String.fromEnvironment(
                    'API_BASE_URL',
                    defaultValue: '',
                  ))
              .replaceFirst(RegExp(r'/+$'), '') {
    if (this.baseUrl.isEmpty) {
      this.baseUrl = 'http://localhost:3001/api';
    }
  }
  final http.Client client;
  String baseUrl;
  String? token;

  Map<String, String>? get authHeaders => token == null || token!.isEmpty
      ? null
      : {'Authorization': 'Bearer $token'};

  Future<dynamic> request(String method, String path, [Object? body]) async {
    final request = http.Request(method, Uri.parse('$baseUrl$path'));
    request.headers['Content-Type'] = 'application/json';
    if (body != null) request.body = jsonEncode(body);
    return _send(request);
  }

  Future<dynamic> upload(
    String path,
    String name,
    Uint8List bytes,
    String note,
  ) {
    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl$path'));
    request.fields['note'] = note;
    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: name,
        contentType: MediaType(
          'image',
          name.toLowerCase().endsWith('.png') ? 'png' : 'jpeg',
        ),
      ),
    );
    return _send(request);
  }

  Future<dynamic> _send(http.BaseRequest request) async {
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    try {
      final response = await (() async => http.Response.fromStream(
        await client.send(request),
      ))().timeout(const Duration(seconds: 30));
      dynamic data;
      try {
        data = jsonDecode(utf8.decode(response.bodyBytes));
      } catch (_) {
        throw ApiError('เซิร์ฟเวอร์ตอบกลับไม่ถูกต้อง', response.statusCode);
      }
      if (response.statusCode >= 400) {
        throw ApiError(
          data is Map
              ? '${data['error'] ?? data['message'] ?? 'เกิดข้อผิดพลาด'}'
              : 'เกิดข้อผิดพลาดจากเซิร์ฟเวอร์',
          response.statusCode,
        );
      }
      return data;
    } on TimeoutException {
      throw DomainError(
        'เซิร์ฟเวอร์ใช้เวลาตอบนาน กรุณาตรวจสอบรายการก่อนลองใหม่',
      );
    } on http.ClientException catch (e) {
      debugPrint('ClientException: $e');
      throw DomainError(
        'เชื่อมต่อเซิร์ฟเวอร์ไม่ได้ กรุณาตรวจสอบเครือข่ายและ API_BASE_URL',
      );
    }
  }
}
