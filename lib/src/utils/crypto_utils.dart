/// Cryptographic helpers for the SAIC iSmart API.
///
/// Implements the AES-128-CBC + HMAC-SHA-256 pipeline used by the API to
/// encrypt request/response bodies and sign requests. All formulas are taken
/// from `net/crypto.py` and `crypto_utils.py` in the Python reference client.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;

/// Returns the lowercase SHA-256 hex digest of [input] (UTF-8 encoded).
///
/// Used to hash the VIN before every API call.
/// Source: `crypto_utils.py:sha256_hex_digest()`
String sha256Hex(String input) =>
    sha256.convert(utf8.encode(input)).toString();

/// Returns the lowercase MD5 hex digest of [input] (UTF-8 encoded, no padding).
///
/// Equivalent to Python's `md5_hex_digest(do_padding=False)`. The padding
/// variant (appends `"00"` before hashing) is never used in production paths.
/// Source: `crypto_utils.py:md5_hex_digest()`
String md5Hex(String input) => md5.convert(utf8.encode(input)).toString();

/// Derives the AES-128-CBC encryption key for a request body.
///
/// Formula (`net/crypto.py:encrypt_request`):
/// ```
/// md5Hex(md5Hex(requestPath + tenantId + userToken + "app") + timestampMs + "1" + contentType)
/// ```
/// [requestPath] must include the query string, e.g.
/// `/vehicle/status?vin=abc&vehStatusReqType=2`.
String deriveRequestKey(
  String requestPath,
  String tenantId,
  String userToken,
  String timestampMs,
  String contentType,
) {
  final part1 = md5Hex('$requestPath$tenantId${userToken}app');
  return md5Hex('$part1${timestampMs}1$contentType');
}

/// Derives the AES-128-CBC IV for a request body.
///
/// Formula (`net/crypto.py:encrypt_request`): `md5Hex(timestampMs)`
String deriveRequestIv(String timestampMs) => md5Hex(timestampMs);

/// Derives the AES-128-CBC decryption key for a response body.
///
/// Formula (`net/crypto.py:decrypt_response`):
/// `md5Hex(appSendDate + "1" + contentType)`
///
/// [appSendDate] comes from the `APP-SEND-DATE` response header.
/// [contentType] comes from the `ORIGINAL-CONTENT-TYPE` response header.
String deriveResponseKey(String appSendDate, String contentType) =>
    md5Hex('${appSendDate}1$contentType');

/// Derives the AES-128-CBC IV for a response body.
///
/// Formula (`net/crypto.py:decrypt_response`): `md5Hex(appSendDate)`
String deriveResponseIv(String appSendDate) => md5Hex(appSendDate);

/// Computes the `APP-VERIFICATION-STRING` request header value (HMAC-SHA-256).
///
/// [encryptedBody] must be the hex-encoded AES ciphertext that was (or will be)
/// sent as the request body. Pass an empty string for bodyless requests (GET).
///
/// Formula (`net/crypto.py:get_app_verification_string`):
/// ```
/// encryptKey = deriveRequestKey(...)
/// hmacMsg    = requestPath + tenantId + userToken + "app"
///              + timestampMs + "1" + contentType + encryptedBody
/// hmacKey    = md5Hex(encryptKey + timestampMs)
/// result     = HMAC-SHA256(hmacKey, hmacMsg).hexDigest
/// ```
String computeHmac(
  String requestPath,
  String tenantId,
  String userToken,
  String timestampMs,
  String contentType,
  String encryptedBody,
) {
  final encryptKey = deriveRequestKey(
    requestPath,
    tenantId,
    userToken,
    timestampMs,
    contentType,
  );
  final hmacKey = md5Hex('$encryptKey$timestampMs');
  if (hmacKey.isEmpty) return '';

  final message =
      '$requestPath$tenantId${userToken}app${timestampMs}1$contentType$encryptedBody';

  return Hmac(sha256, utf8.encode(hmacKey)).convert(utf8.encode(message)).toString();
}

/// AES-128-CBC encrypts [plaintext] and returns the hex-encoded ciphertext.
///
/// [keyHex] and [ivHex] are the 32-character lowercase hex strings produced
/// by [deriveRequestKey] / [deriveRequestIv]. PKCS7 padding is applied
/// automatically (PKCS5 == PKCS7 for 16-byte AES blocks).
///
/// The plaintext is trimmed before encryption, matching Python's
/// `request_body.strip()` (`net/crypto.py:encrypt_request`).
String encryptBody(String plaintext, String keyHex, String ivHex) {
  final key = enc.Key(Uint8List.fromList(hex.decode(keyHex)));
  final iv = enc.IV(Uint8List.fromList(hex.decode(ivHex)));
  final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
  final encrypted = encrypter.encrypt(plaintext.trim(), iv: iv);
  return hex.encode(encrypted.bytes);
}

/// AES-128-CBC decrypts hex-encoded [ciphertextHex] and returns the plaintext.
///
/// [keyHex] and [ivHex] are the 32-character lowercase hex strings produced
/// by [deriveResponseKey] / [deriveResponseIv].
///
/// The ciphertext is trimmed before decryption, matching Python's
/// `response_body.strip()` (`net/crypto.py:decrypt_response`).
String decryptBody(String ciphertextHex, String keyHex, String ivHex) {
  final key = enc.Key(Uint8List.fromList(hex.decode(keyHex)));
  final iv = enc.IV(Uint8List.fromList(hex.decode(ivHex)));
  final ciphertext = enc.Encrypted(
    Uint8List.fromList(hex.decode(ciphertextHex.trim())),
  );
  final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
  return encrypter.decrypt(ciphertext, iv: iv);
}
