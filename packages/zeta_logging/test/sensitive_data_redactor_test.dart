import 'package:test/test.dart';
import 'package:zeta_logging/zeta_logging.dart';

void main() {
  group(redactSensitiveText, () {
    test('redacts authentication, key, token, secret, and home values', () {
      const home = '/Users/private';
      final result = redactSensitiveText(
        'Authorization: Basic dXNlcjpwYXNz\n'
        'Proxy-Authorization=Bearer proxy.token\n'
        'Bearer abc.def.ghi api_key="api-secret" token=value '
        "password='password-value' private-key=private secret=value "
        'sk-1234567890abcdef path=$home/project',
        userHome: home,
      );

      expect(result, contains('Authorization: ••••••'));
      expect(result, contains('Proxy-Authorization=••••••'));
      expect(result, contains('Bearer ••••••'));
      expect(result, contains('api_key=••••••'));
      expect(result, contains('token=••••••'));
      expect(result, contains('password=••••••'));
      expect(result, contains('private-key=••••••'));
      expect(result, contains('secret=••••••'));
      expect(result, contains('sk-••••••'));
      expect(result, contains('path=~/project'));
    });

    test('uses the current home when no override is supplied', () {
      expect(redactSensitiveText('ordinary text'), 'ordinary text');
    });

    test('keeps text unchanged when an explicit home is empty', () {
      expect(
        redactSensitiveText('/home/user/project', userHome: ''),
        '/home/user/project',
      );
    });

    test('resolves supported home environment fallbacks', () {
      expect(
        redactSensitiveText(
          r'C:\Users\zeta\project',
          environment: const <String, String>{
            'USERPROFILE': r'C:\Users\zeta',
          },
          isWindows: true,
        ),
        r'~\project',
      );
      expect(
        redactSensitiveText(
          r'C:\Users\zeta\project',
          environment: const <String, String>{
            'HOMEDRIVE': 'C:',
            'HOMEPATH': r'\Users\zeta',
          },
          isWindows: true,
        ),
        r'~\project',
      );
      expect(
        redactSensitiveText(
          '/home/zeta/project',
          environment: const <String, String>{'HOME': '/home/zeta'},
          isWindows: false,
        ),
        '~/project',
      );
    });
  });
}
