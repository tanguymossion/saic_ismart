import 'package:saic_ismart/src/utils/crypto_utils.dart';
import 'package:test/test.dart';

void main() {
  group('sha1Hex', () {
    test('produces lowercase hex digest', () {
      // echo -n "hello" | sha1sum
      expect(sha1Hex('hello'), 'aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d');
    });

    test('hashes empty string', () {
      // echo -n "" | sha1sum
      expect(sha1Hex(''), 'da39a3ee5e6b4b0d3255bfef95601890afd80709');
    });
  });

  group('sha256Hex', () {
    test('produces lowercase hex digest', () {
      // echo -n "hello" | sha256sum
      expect(
        sha256Hex('hello'),
        '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
      );
    });
  });

  group('md5Hex', () {
    test('produces lowercase hex digest without padding', () {
      // echo -n "hello" | md5sum
      expect(md5Hex('hello'), '5d41402abc4b2a76b9719d911017c592');
    });
  });

  // Test vector from tests/security_test.py in the Python reference client.
  //
  // Input:
  //   request_path    = "/api/v1/data"
  //   current_ts      = "20230514123000"
  //   tenant_id       = "1234"
  //   content_type    = "application/json"
  //   request_content = '{"key": "value"}'
  //   user_token      = "dummy_token"
  //
  // Expected APP-VERIFICATION-STRING:
  //   "afd4eaf98af2d964f8ea840fc144ee7bae95dbeeeb251d5e3a01371442f92eeb"
  group('computeHmac', () {
    const requestPath = '/api/v1/data';
    const timestampMs = '20230514123000';
    const tenantId = '1234';
    const contentType = 'application/json';
    const plaintext = '{"key": "value"}';
    const userToken = 'dummy_token';

    test('matches Python reference test vector', () {
      final keyHex = deriveRequestKey(
        requestPath,
        tenantId,
        userToken,
        timestampMs,
        contentType,
      );
      final ivHex = deriveRequestIv(timestampMs);
      final encryptedBody = encryptBody(plaintext, keyHex, ivHex);

      final result = computeHmac(
        requestPath,
        tenantId,
        userToken,
        timestampMs,
        contentType,
        encryptedBody,
      );

      expect(
        result,
        'afd4eaf98af2d964f8ea840fc144ee7bae95dbeeeb251d5e3a01371442f92eeb',
      );
    });
  });

  group('encryptBody / decryptBody round-trip', () {
    test('decrypting encrypted text returns original', () {
      const plain = 'hello iSmart';
      const keyHex = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'; // 16 bytes
      const ivHex = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'; // 16 bytes
      final cipherHex = encryptBody(plain, keyHex, ivHex);
      expect(decryptBody(cipherHex, keyHex, ivHex), plain);
    });

    test('trims leading/trailing whitespace before encrypting', () {
      const keyHex = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      const ivHex = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
      // Both should produce the same ciphertext.
      expect(
        encryptBody('  hello  ', keyHex, ivHex),
        encryptBody('hello', keyHex, ivHex),
      );
    });
  });

  group('deriveResponseKey / deriveResponseIv', () {
    test('response key matches formula', () {
      const appSendDate = '1700000000000';
      const contentType = 'application/json';
      // md5("17000000000001application/json")
      expect(
        deriveResponseKey(appSendDate, contentType),
        md5Hex('${appSendDate}1$contentType'),
      );
    });

    test('response IV matches formula', () {
      const appSendDate = '1700000000000';
      expect(deriveResponseIv(appSendDate), md5Hex(appSendDate));
    });
  });
}
