import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:zeta_foundation/platform.dart';

void main() {
  test('从 path_provider 返回应用文档目录路径', () async {
    final previous = PathProviderPlatform.instance;
    addTearDown(() => PathProviderPlatform.instance = previous);
    PathProviderPlatform.instance = _FakePathProviderPlatform(
      applicationDocumentsPath: '/Users/test/Documents',
    );

    expect(await ZetaUserDirectory.getUserDirectory(), '/Users/test/Documents');
  });
}

final class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform({required this.applicationDocumentsPath});

  final String applicationDocumentsPath;

  @override
  Future<String> getApplicationDocumentsPath() async =>
      applicationDocumentsPath;
}
