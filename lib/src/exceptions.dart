/// Exception types thrown by the saic_ismart package.
library;

/// Thrown when the iSmart API returns a non-success response code.
///
/// The JSON `code` field in API responses maps to [statusCode]. Error codes
/// 2, 3, and 7 are fatal and never retried (`base.py:__deserialize`).
class SaicApiException implements Exception {
  /// API or HTTP status code that triggered this exception.
  final int statusCode;

  /// Human-readable message from the API response or HTTP body.
  final String message;

  // ignore: public_member_api_docs
  const SaicApiException({required this.statusCode, required this.message});

  @override
  String toString() => 'SaicApiException($statusCode): $message';
}

/// Thrown when authentication fails or a session has expired.
///
/// Raised on JSON response code 401/403, HTTP status 401/403, or when the
/// login request parameters are invalid (`base.py:__deserialize`).
class SaicAuthException extends SaicApiException {
  // ignore: public_member_api_docs
  const SaicAuthException({required super.statusCode, required super.message});

  @override
  String toString() => 'SaicAuthException($statusCode): $message';
}
