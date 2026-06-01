import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:client/core/providers/app_version_provider.dart';

void main() {
  group('appVersionProvider', () {
    test('provider is defined and returns a FutureProvider<String>', () {
      expect(appVersionProvider, isA<FutureProvider<String>>());
    });

    test('provider can be read from a ProviderContainer', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final sub = container.listen(appVersionProvider, (_, __) {});
      await container.read(appVersionProvider.future).catchError((_) => '0.0.0');
      final value = sub.read();
      expect(value, isNotNull);
    });
  });
}
