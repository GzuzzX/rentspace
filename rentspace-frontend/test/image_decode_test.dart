import 'package:flutter_test/flutter_test.dart';
import 'package:rentspace/services/remote_store.dart';
void main() {
  test('Malformed image does not crash snapshot decoding', () {
    expect(decodeImageSafely('broken!'), isNull);
    expect(decodeImageSafely('a'), isNull);
    expect(decodeImageSafely('AQID'), [1, 2, 3]);
  });
}
