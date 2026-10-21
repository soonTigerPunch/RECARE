import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recare/domain/inventory.dart';
import 'package:recare/ui/design_system.dart';
import 'package:recare/ui/waste_insights_view.dart';

void main() {
  final today = DateTime(2026, 10, 21);
  FoodRecord waste(
    String id,
    String name, {
    int? cost,
    WasteReason? reason,
    FoodUnit unit = FoodUnit.piece,
    int amount = 1000,
  }) => FoodRecord(
    id: id,
    foodId: id,
    foodName: name,
    kind: ActionKind.waste,
    amount: amount,
    unit: unit,
    date: today,
    cost: cost,
    wasteReason: reason,
  );
  Future<void> open(WidgetTester tester, List<FoodRecord> records) =>
      tester.pumpWidget(
        MaterialApp(
          theme: RecareTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: WasteInsightsView(week: weeklyWaste(records, today)),
            ),
          ),
        ),
      );

  testWidgets('reports actual reasons, unknowns, and food quantities', (
    tester,
  ) async {
    await open(tester, [
      waste(
        '1',
        '우유',
        cost: 1500,
        reason: WasteReason.forgot,
        unit: FoodUnit.ml,
        amount: 500000,
      ),
      waste(
        '2',
        '우유',
        reason: WasteReason.forgot,
        unit: FoodUnit.litre,
        amount: 1000000,
      ),
      waste('3', '당근', cost: 0),
    ]);
    expect(find.text('폐기 기록 3건'), findsOneWidget);
    expect(find.text('금액이 기록된 폐기 1,500원'), findsOneWidget);
    expect(find.text('구매금액 미입력 1건'), findsOneWidget);
    expect(find.text('${WasteReason.forgot.label} · 2건'), findsOneWidget);
    expect(find.text('이유 미기록 · 1건'), findsOneWidget);
    expect(find.text('우유 · 2건'), findsOneWidget);
    expect(find.textContaining('1.5 L'), findsOneWidget);
    expect(find.byKey(const ValueKey('waste-purchase-hint')), findsOneWidget);
    expect(find.textContaining('절약'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty week gives no fabricated amount or reason', (
    tester,
  ) async {
    await open(tester, []);
    expect(find.text('이번 주 폐기 기록이 없어요.'), findsOneWidget);
    expect(find.textContaining('0원'), findsNothing);
    expect(find.textContaining(WasteReason.forgot.label), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('all unknown prices remain explicitly unknown', (tester) async {
    await open(tester, [waste('1', '사과')]);
    expect(find.text('구매금액 미입력 1건'), findsOneWidget);
    expect(find.text('기록된 폐기 금액이 없어요.'), findsOneWidget);
    expect(find.textContaining('0원'), findsNothing);
  });
}
