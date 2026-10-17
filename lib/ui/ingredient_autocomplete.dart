import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/food_catalog.dart';
import '../domain/inventory.dart';
import 'design_system.dart';
import 'food_illustration.dart';

class IngredientAutocomplete extends StatefulWidget {
  const IngredientAutocomplete({
    super.key,
    required this.controller,
    required this.enabled,
    required this.loadHistory,
    required this.onSelected,
    required this.onNameChanged,
    required this.onActiveChanged,
  });
  final TextEditingController controller;
  final bool enabled;
  final Future<List<Food>> Function() loadHistory;
  final ValueChanged<FoodSuggestion> onSelected;
  final VoidCallback onNameChanged;
  final ValueChanged<bool> onActiveChanged;
  @override
  State<IngredientAutocomplete> createState() => _IngredientAutocompleteState();
}

class _IngredientAutocompleteState extends State<IngredientAutocomplete> {
  final _focus = FocusNode();
  FoodSuggestionIndex _index = FoodSuggestionIndex();
  bool _historyFailed = false, _loadingHistory = false;
  String? _dismissed;
  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
    unawaited(_load());
  }

  void _focusChanged() {
    if (!mounted) return;
    setState(() {});
    widget.onActiveChanged(_focus.hasFocus);
  }

  Future<void> _load() async {
    if (_loadingHistory) return;
    setState(() => _loadingHistory = true);
    try {
      final history = await widget.loadHistory();
      if (mounted) {
        setState(() {
          _index = FoodSuggestionIndex(history: history);
          _historyFailed = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _historyFailed = true);
    } finally {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  void _select(FoodSuggestion suggestion) {
    _dismissed = suggestion.name;
    widget.onSelected(suggestion);
    _focus.unfocus();
  }

  @override
  void dispose() {
    _focus.removeListener(_focusChanged);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = widget.controller.text;
    final show =
        widget.enabled &&
        _focus.hasFocus &&
        normalizeFoodName(query).isNotEmpty &&
        query != _dismissed;
    final suggestions = show ? _index.search(query) : const <FoodSuggestion>[];
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          key: const ValueKey('food-name'),
          controller: widget.controller,
          focusNode: _focus,
          enabled: widget.enabled,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: '식재료 이름',
            hintText: '예: 서울우유, 당근',
          ),
          validator: (value) =>
              value == null || value.trim().isEmpty || value.trim().length > 60
              ? '식재료 이름은 1~60자로 입력해주세요.'
              : null,
          onChanged: (_) {
            setState(() => _dismissed = null);
            widget.onNameChanged();
          },
        ),
        if (show) ...[
          const SizedBox(height: Space.sm),
          Material(
            key: const ValueKey('food-suggestions'),
            color: colors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Corners.field),
              side: BorderSide(color: colors.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.md,
                    Space.sm,
                    Space.md,
                    0,
                  ),
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '추천 · 대표 이미지',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (_historyFailed)
                        TextButton(
                          onPressed: _loadingHistory
                              ? null
                              : () => unawaited(_load()),
                          child: const Text('이전 기록 재시도'),
                        ),
                    ],
                  ),
                ),
                if (suggestions.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(Space.md),
                    child: Text(
                      _loadingHistory
                          ? '이전 등록 이력을 불러오고 있어요.'
                          : _historyFailed
                          ? '이전 기록을 불러오지 못했어요. 직접 입력할 수 있어요.'
                          : '일치하는 재료가 없어요. 그대로 직접 입력할 수 있어요.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 240),
                    child: ListView.builder(
                      shrinkWrap: true,
                      primary: false,
                      padding: const EdgeInsets.symmetric(vertical: Space.xs),
                      itemCount: suggestions.length,
                      itemBuilder: (context, i) {
                        final item = suggestions[i];
                        return InkWell(
                          key: ValueKey('suggestion-${item.id}'),
                          onTap: () => _select(item),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: Space.md,
                              vertical: Space.sm,
                            ),
                            child: Row(
                              children: [
                                FoodIllustration(visual: item.visual),
                                const SizedBox(width: Space.md),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.name,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyLarge,
                                      ),
                                      const SizedBox(height: Space.xs),
                                      Text(
                                        '${item.quantityLabel} · ${item.sourceLabel}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
