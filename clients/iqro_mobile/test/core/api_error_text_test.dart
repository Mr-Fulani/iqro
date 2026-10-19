import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/network/api_error_text.dart';
import 'package:iqro_mobile/core/network/api_exception.dart';
import 'package:iqro_mobile/l10n/generated/app_localizations.dart';

void main() {
  final ru = lookupAppLocalizations(const Locale('ru'));

  test('a known code is shown in the app language, not the server detail', () {
    const error = ApiException(
      message: 'Account linking is unavailable for this session.',
      code: 'account_link_unavailable',
      statusCode: 403,
    );

    expect(
      apiErrorText(ru, error, fallback: 'fallback'),
      'Этот вход нельзя завершить в текущей сессии.',
    );
  });

  test('both rate limits share one message', () {
    for (final code in <String>['auth_rate_limited', 'reading_rate_limited']) {
      expect(
        apiErrorText(
          ru,
          ApiException(message: 'Too many', code: code, statusCode: 429),
          fallback: 'fallback',
        ),
        ru.apiErrorRateLimited,
      );
    }
  });

  test('an unknown code or a non-API error uses the fallback', () {
    expect(
      apiErrorText(
        ru,
        const ApiException(message: 'Boom', code: 'new_code', statusCode: 400),
        fallback: ru.apiErrorUnknown,
      ),
      'Повторите попытку позже.',
    );
    expect(
      apiErrorText(ru, StateError('db'), fallback: ru.apiErrorUnknown),
      ru.apiErrorUnknown,
    );
  });
}
