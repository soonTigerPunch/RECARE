import 'package:flutter_test/flutter_test.dart';
import 'package:recare/domain/inventory.dart';
import 'package:recare/domain/waste_insights.dart';

void main() {
  final today = DateTime(2026, 10, 21);
  FoodRecord record(
    String id, {
    int? cost,
    WasteReason? reason,
    FoodUnit unit = FoodUnit.ml,
  }) => FoodRecord(
    id: id,
    foodId: id,
    foodName: '우유',
    kind: ActionKind.waste,
    amount: 1000000,
    unit: unit,
    date: today,
    cost: cost,
    wasteReason: reason,
  );
  test('insights retain unknowns and aggregate compatible amounts', () {
    final insights = buildWasteInsights(
      weeklyWaste([
        record('a', cost: 0, reason: WasteReason.forgot),
        record('b', cost: 50, reason: WasteReason.forgot, unit: FoodUnit.litre),
        record('c'),
      ], today),
    );
    expect(insights.recordCount, 3);
    expect(insights.knownTotal, 50);
    expect(insights.unknownPriceCount, 1);
    expect(insights.unknownReasonCount, 1);
    expect(insights.reasonCounts[WasteReason.forgot], 2);
    expect(insights.mostCommonReason, WasteReason.forgot);
    expect(insights.topFoods.single.amounts, {FoodUnit.ml: 3000000});
    expect(insights.hint, contains('소비기한'));
  });
  test('empty and unknown-reason weeks have neutral hints', () {
    final empty = buildWasteInsights(weeklyWaste([], today));
    expect(empty.recordCount, 0);
    expect(empty.topFoods, isEmpty);
    expect(empty.mostCommonReason, isNull);
    expect(
      buildWasteInsights(weeklyWaste([record('a')], today)).hint,
      contains('이유'),
    );
  });
  test(
    'reason rows round trip while historical absent reasons stay unknown',
    () {
      for (final reason in WasteReason.values) {
        expect(
          FoodRecord.fromRow(record('a', reason: reason).toRow()).wasteReason,
          reason,
        );
        expect(WasteReason.fromCode(reason.code), reason);
      }
      final row = record('a').toRow()..remove('waste_reason');
      expect(FoodRecord.fromRow(row).wasteReason, isNull);
    },
  );
}
