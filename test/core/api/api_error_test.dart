import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_web/core/api/api_error.dart';

/// **An error message that describes the transport is not an error message.**
///
/// A rejected save read *"DioException [bad response]: This exception was
/// thrown because the response has a status code of 400 and
/// RequestOptions.validateStatus was configured to throw… you typically have
/// either to verify and fix your request code or you have to fix the server
/// code."* Every word of that is about Dio. Core had answered with the one
/// sentence that says what is wrong, and the app threw it away.

DioException refused(Object? body, {int status = 400}) => DioException(
      requestOptions: RequestOptions(path: '/dashboards/x'),
      response: Response(
        requestOptions: RequestOptions(path: '/dashboards/x'),
        statusCode: status,
        data: body,
      ),
      type: DioExceptionType.badResponse,
    );

void main() {
  test('core answers in `error`, so that is what is shown', () {
    expect(
      apiMessage(refused({'error': "widget 'a' title cannot be empty"})),
      "widget 'a' title cannot be empty",
    );
  });

  test('a plain-text body is a message too', () {
    expect(apiMessage(refused('Nope.')), 'Nope.');
  });

  test('an empty body says the status plainly, not the HTTP spec', () {
    final said = apiMessage(refused(null, status: 500));
    expect(said, contains('500'));
    expect(said, isNot(contains('validateStatus')));
    expect(said, isNot(contains('developer.mozilla.org')));
  });

  test('no response at all is named by what went wrong', () {
    expect(
      apiMessage(DioException(
        requestOptions: RequestOptions(path: '/x'),
        type: DioExceptionType.connectionError,
      )),
      'Could not reach the server.',
    );
  });

  test('anything that is not a Dio failure is passed through', () {
    expect(apiMessage(StateError('boom')), contains('boom'));
  });
}
