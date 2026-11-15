import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rentspace/services/remote_store.dart';

void main() {
  test('decodeImageSafely decodes valid base64 image payloads', () {
    final original = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]);
    final encoded = base64Encode(original);

    expect(decodeImageSafely(encoded), orderedEquals(original));
    expect(decodeImageSafely('  $encoded\n'), orderedEquals(original));
  });

  test('decodeImageSafely returns null on empty or corrupt base64', () {
    expect(decodeImageSafely(''), isNull);
    expect(decodeImageSafely('   '), isNull);
    expect(decodeImageSafely('not!valid@base64###'), isNull);
    expect(decodeImageSafely('abc'), isNull);
  });
}
