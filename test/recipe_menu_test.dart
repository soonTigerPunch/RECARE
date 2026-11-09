import 'package:flutter_test/flutter_test.dart';
import 'package:recare/domain/recipes.dart';

void main() {
  test(
    'menu response contains typed titles without fabricated recipe details',
    () {
      final result = RecipeMenuResult.fromResponse(
        {
          'status': 'ok',
          'message': '',
          'menus': [
            {'id': 'm0', 'title': '두부구이'},
            {'id': 'm1', 'title': '두부국'},
          ],
          'generated_at': '2026-11-08T12:00:00Z',
        },
        'parent',
        DateTime(2026, 11, 8),
      );
      expect(result.menus.map((m) => m.title), ['두부구이', '두부국']);
      expect(result.menus.first.id, 'm0');
      expect(
        () => RecipeMenuResult.fromResponse(
          {
            'status': 'ok',
            'message': '',
            'menus': [
              {'id': 'm0', 'title': ''},
            ],
          },
          'parent',
          DateTime.now(),
        ),
        throwsArgumentError,
      );
    },
  );
}
