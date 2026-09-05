import 'package:dio/dio.dart';

/// What the server actually said, or the next best thing.
///
/// **An error message that describes the transport is not an error message.**
/// A rejected save read:
///
/// > Could not save: DioException [bad response]: This exception was thrown
/// > because the response has a status code of 400 and
/// > RequestOptions.validateStatus was configured to throw for this status
/// > code… In order to resolve this exception you typically have either to
/// > verify and fix your request code or you have to fix the server code.
///
/// Every word of that is about Dio. Meanwhile core had answered
/// `{"error": "widget 'x' title cannot be empty"}` — the one sentence that
/// says what is wrong and what to do — and the app threw it away. It cost a
/// round of *"the save failed"* and *"what did it say?"* to find out, and it
/// would have cost that every time.
String apiMessage(Object error) {
  if (error is! DioException) return '$error';

  final data = error.response?.data;
  final said = switch (data) {
    // Core's own shape: every handler answers `{"error": "..."}`.
    {'error': final String text} when text.trim().isNotEmpty => text.trim(),
    {'message': final String text} when text.trim().isNotEmpty => text.trim(),
    final String text when text.trim().isNotEmpty => text.trim(),
    _ => null,
  };
  if (said != null) return said;

  // Nothing useful in the body — say the status plainly rather than quoting
  // the HTTP spec at somebody who is trying to save a page.
  final code = error.response?.statusCode;
  if (code != null) return 'The server refused it ($code).';
  return switch (error.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout =>
      'The server did not answer in time.',
    DioExceptionType.connectionError => 'Could not reach the server.',
    _ => error.message ?? '$error',
  };
}
