/// Exception types thrown by the saic_ismart package.
library;

/// Thrown when the iSmart API returns a non-success response.
class ISmartApiException implements Exception {
  /// HTTP status code returned by the server.
  final int statusCode;

  /// Human-readable message from the API response.
  final String message;

  // ignore: public_member_api_docs
  const ISmartApiException({required this.statusCode, required this.message});

  @override
  String toString() => 'ISmartApiException($statusCode): $message';
}

/// Thrown when authentication fails or a session has expired.
class ISmartAuthException extends ISmartApiException {
  // ignore: public_member_api_docs
  const ISmartAuthException({required super.statusCode, required super.message});
}
