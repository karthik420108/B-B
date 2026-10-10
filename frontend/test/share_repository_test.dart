import 'package:flutter_test/flutter_test.dart';

import 'package:health_wallet/core/network/api_client.dart';
import 'package:health_wallet/core/storage/token_storage.dart';
import 'package:health_wallet/models/models.dart';
import 'package:health_wallet/services/doctor_repository.dart';
import 'package:health_wallet/services/share_repository.dart';

/// Mimics the raw decoded JSON the API client returns for a list endpoint.
class _FakeApi extends ApiClient {
  _FakeApi() : super(TokenStorage());

  dynamic getResponse;

  @override
  Future<dynamic> getBody(String path, {Map<String, dynamic>? query}) async => getResponse;
}

void main() {
  group('ShareRepository.list', () {
    test('returns a typed List<ShareGrant> from a raw JSON array', () async {
      // Regression guard: a `dynamic` receiver made `.map(...).toList()` a
      // dynamic call that returned List<dynamic> on the web and crashed the
      // Shares screen with a type error.
      final api = _FakeApi()
        ..getResponse = [
          {
            'id': 's1',
            'status': 'active',
            'label': 'For Dr. Rao',
            'tokenPreview': 'ab12…cd34',
            'accessCount': 2,
            'isActive': true,
          }
        ];
      final repo = ShareRepository(api);

      final List<ShareGrant> shares = await repo.list();

      expect(shares, isA<List<ShareGrant>>());
      expect(shares, hasLength(1));
      expect(shares.single.id, 's1');
      expect(shares.single.isActive, isTrue);
    });

    test('also accepts an {items: [...]} envelope', () async {
      final api = _FakeApi()
        ..getResponse = {
          'items': [
            {'id': 's2', 'status': 'revoked'}
          ]
        };
      final repo = ShareRepository(api);

      final shares = await repo.list();

      expect(shares.single.id, 's2');
      expect(shares.single.status, 'revoked');
    });

    test('returns an empty typed list when there are no shares', () async {
      final api = _FakeApi()..getResponse = <dynamic>[];
      final repo = ShareRepository(api);

      expect(await repo.list(), isEmpty);
    });
  });

  group('DoctorRepository.myShares', () {
    test('returns typed maps from a raw JSON array', () async {
      final api = _FakeApi()
        ..getResponse = [
          {'id': 'g1', 'status': 'active'}
        ];
      final repo = DoctorRepository(api);

      final shares = await repo.myShares();

      expect(shares, hasLength(1));
      expect(shares.single['id'], 'g1');
    });
  });
}
