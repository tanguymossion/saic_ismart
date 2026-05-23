/// Exception types thrown by the saic_ismart package.
library;

/// Base class for all exceptions thrown by the saic_ismart package.
class SaicException implements Exception {
  /// Human-readable message describing the error.
  final String message;

  /// API or HTTP status code associated with the error, or `null` if not
  /// applicable (e.g. network errors, configuration errors).
  final int? code;

  // ignore: public_member_api_docs
  const SaicException({required this.message, this.code});

  @override
  String toString() => 'SaicException(code: $code, message: $message)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SaicException &&
          runtimeType == other.runtimeType &&
          code == other.code &&
          message == other.message;

  @override
  int get hashCode => Object.hash(runtimeType, code, message);
}

/// Thrown when authentication fails or a session has expired.
///
/// Raised on JSON response code 401/403, HTTP status 401/403, or when the
/// login request parameters are invalid (`base.py:__deserialize`).
class SaicAuthException extends SaicException {
  // ignore: public_member_api_docs
  const SaicAuthException({required super.message, super.code});

  @override
  String toString() => 'SaicAuthException(code: $code, message: $message)';
}

/// Thrown when a 401/403 is received while a session token is active.
///
/// Indicates that another client has authenticated with the same credentials
/// and the server has invalidated this session. The iSmart server pauses for
/// ~900 s when it detects a session conflict before accepting a new login
/// (TECHNICAL_REFERENCE.md §4, §8).
///
/// Callers should wait before re-authenticating.
class SaicSessionConflictException extends SaicAuthException {
  // ignore: public_member_api_docs
  const SaicSessionConflictException({required super.message, super.code});

  @override
  String toString() =>
      'SaicSessionConflictException(code: $code, message: $message)';
}

/// Thrown when the iSmart API returns a non-success response code.
///
/// The JSON `code` field in API responses maps to [code]. Error codes 2, 3,
/// and 7 are fatal and never retried (`base.py:__deserialize`).
class SaicApiException extends SaicException {
  // ignore: public_member_api_docs
  const SaicApiException({required super.message, super.code});

  @override
  String toString() => 'SaicApiException(code: $code, message: $message)';
}

/// Thrown when the event-id polling loop for [getVehicleStatus] exceeds its
/// timeout (default 30 s — TECHNICAL_REFERENCE.md §4).
class SaicTimeoutException extends SaicException {
  // ignore: public_member_api_docs
  const SaicTimeoutException({required super.message, super.code});

  @override
  String toString() => 'SaicTimeoutException(code: $code, message: $message)';
}

/// Thrown when a network or HTTP transport error occurs (e.g. no connectivity,
/// DNS failure, or connection refused).
class SaicNetworkException extends SaicException {
  // ignore: public_member_api_docs
  const SaicNetworkException({required super.message, super.code});

  @override
  String toString() => 'SaicNetworkException(code: $code, message: $message)';
}
