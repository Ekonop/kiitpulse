class GatewayException implements Exception {
  const GatewayException(this.message, {this.code, this.retryable = false});

  final String message;
  final String? code;
  final bool retryable;

  @override
  String toString() => 'GatewayException($code): $message';
}
