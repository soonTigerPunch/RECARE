import 'package:flutter/material.dart';

import '../domain/inventory.dart';
import '../domain/waste_insights.dart';
import 'design_system.dart';

class WasteInsightsView extends StatelessWidget {
  const WasteInsightsView({super.key, required this.week});
  final WeekSummary week;

  String _money(int value) =>
      '${value.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (match) => '${match[1]},')}원';

  String _amounts(WastedFoodInsight food) => food.amounts.entries
      .map((entry) {
        final unit = switch (entry.key.family) {
          'volume' when entry.value >= FoodUnit.litre.factor => FoodUnit.litre,
          'weight' when entry.value >= FoodUnit.kilogram.factor =>
            FoodUnit.kilogram,
          _ => entry.key,
        };
        return '${unit.quantityText(entry.value)} ${unit.label}';
      })
      .join(' · ');

  @override
  Widget build(BuildContext context) {
    final insights = buildWasteInsights(week);
    final theme = Theme.of(context);
    return Card(
      key: const ValueKey('waste-insights'),
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('이번 주 폐기 돌아보기', style: theme.textTheme.titleMedium),
            const SizedBox(height: Space.md),
            if (insights.recordCount == 0)
              const Text('이번 주 폐기 기록이 없어요.')
            else ...[
              Text('폐기 기록 ${insights.recordCount}건'),
              Text(
                insights.unknownPriceCount == insights.recordCount
                    ? '기록된 폐기 금액이 없어요.'
                    : '금액이 기록된 폐기 ${_money(insights.knownTotal)}',
              ),
              if (insights.unknownPriceCount > 0)
                Text(
                  '구매금액 미입력 ${insights.unknownPriceCount}건',
                  style: theme.textTheme.bodySmall,
                ),
              const SizedBox(height: Space.lg),
              Text('기록된 폐기 이유', style: theme.textTheme.titleSmall),
              const SizedBox(height: Space.sm),
              for (final reason in WasteReason.values)
                if ((insights.reasonCounts[reason] ?? 0) > 0)
                  Text('${reason.label} · ${insights.reasonCounts[reason]}건'),
              if (insights.unknownReasonCount > 0)
                Text(
                  '이유 미기록 · ${insights.unknownReasonCount}건',
                  style: theme.textTheme.bodySmall,
                ),
              const SizedBox(height: Space.lg),
              Text('자주 폐기한 재료', style: theme.textTheme.titleSmall),
              for (final food in insights.topFoods.take(3))
                Padding(
                  padding: const EdgeInsets.only(top: Space.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${food.name} · ${food.count}건'),
                      Text(_amounts(food), style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              const SizedBox(height: Space.lg),
              if (insights.mostCommonReason != null)
                Text(
                  '가장 많이 기록한 이유: ${insights.mostCommonReason!.label}',
                  style: theme.textTheme.bodySmall,
                ),
              const SizedBox(height: Space.xs),
              Text(insights.hint, key: const ValueKey('waste-purchase-hint')),
            ],
          ],
        ),
      ),
    );
  }
}
