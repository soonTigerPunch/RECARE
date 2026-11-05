import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../data/inventory_repository.dart';
import '../../data/recipe_repository.dart';
import '../../domain/inventory.dart';
import '../../domain/recipes.dart';
import '../../services/recipe_client.dart';
import '../design_system.dart';
import 'recipe_common.dart';
import 'recipe_detail.dart';

/// Full-screen recipe flow. The parent retains ownership of [client].
class RecipeHubPage extends StatefulWidget {
  const RecipeHubPage({
    super.key,
    required this.inventory,
    required this.repository,
    required this.client,
    required this.clock,
    this.initialPage = 'input',
    this.onRegister,
  });
  final InventoryRepository inventory;
  final RecipeRepository repository;
  final RecipeClient client;
  final DateTime Function() clock;
  final String initialPage;
  final Future<void> Function()? onRegister;
  @override
  State<RecipeHubPage> createState() => _RecipeHubPageState();
}

class _RecipeHubPageState extends State<RecipeHubPage>
    with WidgetsBindingObserver {
  late final RecipeFavorites favorites = RecipeFavorites(widget.repository);
  final exclusions = TextEditingController();
  final search = TextEditingController();
  List<Food> foods = [];
  List<RecipeResult> recent = [];
  final selected = <String>{};
  final staples = <String>{};
  int servings = 1;
  int? minutes = 20;
  int consentVersion = 0;
  bool shopping = false, initialLoading = true, preparing = false;
  late String page = widget.initialPage;
  String? notice, error;
  RecipeResult? result;
  RecipeRequest? pendingRequest;
  RecipeRequest? resultRequest;
  int requestEpoch = 0;
  final history = <String>[];
  bool allowExit = false;
  Timer? midnight;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _scheduleMidnight();
  }

  void _scheduleMidnight() {
    midnight?.cancel();
    final now = widget.clock();
    final next = DateTime(now.year, now.month, now.day + 1);
    midnight = Timer(next.difference(now), () {
      _refreshStock();
      _scheduleMidnight();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshStock();
      _scheduleMidnight();
    }
  }

  @override
  void dispose() {
    requestEpoch++;
    if (page == 'loading') widget.client.cancel();
    midnight?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    exclusions.dispose();
    search.dispose();
    // A detail route can retain this controller while the hub is on the stack.
    favorites.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final values = await Future.wait<Object>([
        widget.inventory.load(),
        widget.repository.loadSettings(),
        widget.repository.loadRecent(),
        favorites.load().then((_) => true),
      ]);
      if (!mounted) return;
      final snapshot = values[0] as InventorySnapshot;
      final settings = values[1] as RecipeSettings;
      setState(() {
        foods = snapshot.foods;
        selected.addAll(defaultRecipeFoodIds(foods, widget.clock()));
        staples.addAll(settings.staples);
        servings = settings.servings;
        minutes = settings.maxMinutes;
        consentVersion = settings.consentVersion;
        recent = values[2] as List<RecipeResult>;
        initialLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          initialLoading = false;
          error = recipeError(e);
        });
      }
    }
  }

  List<Food> get eligible => eligibleRecipeFoods(foods, widget.clock());
  List<RecipeStock> get groups => groupRecipeFoods(eligible);
  List<RecipeStock> _selectedStocks([List<Food>? source]) => groupRecipeFoods(
    eligibleRecipeFoods(
      source ?? foods,
      widget.clock(),
    ).where((f) => selected.contains(f.id)),
  );
  RecipeSettings get settings => RecipeSettings(
    staples: staples.toList(),
    servings: servings,
    maxMinutes: minutes,
    consentVersion: consentVersion,
  );
  Future<void> _persistSettings() async {
    try {
      await widget.repository.saveSettings(settings);
    } catch (e) {
      if (mounted) recipeMessage(context, recipeError(e));
    }
  }

  String _signature(Iterable<Food> source) => source
      .where((f) => selected.contains(f.id))
      .map(
        (f) =>
            '${f.id}|${f.name}|${f.remaining}|${f.unit.code}|${dateText(f.expiry)}',
      )
      .join(';');
  Future<bool> _refreshStock() async {
    try {
      final snapshot = await widget.inventory.load();
      if (!mounted) return false;
      final changed = _signature(foods) != _signature(snapshot.foods);
      final eligibleIds = eligibleRecipeFoods(
        snapshot.foods,
        widget.clock(),
      ).map((f) => f.id).toSet();
      final removed = selected.difference(eligibleIds).isNotEmpty;
      setState(() {
        foods = snapshot.foods;
        selected.retainAll(eligibleIds);
        if (changed || removed) {
          notice = '재고 또는 날짜가 바뀌었어요. 선택한 재료와 수량을 다시 확인해주세요.';
        }
      });
      return changed || removed;
    } catch (e) {
      if (mounted) setState(() => error = recipeError(e));
      return true;
    }
  }

  void _toggleFoods(List<Food> lots, bool value) {
    final next = {...selected};
    if (value) {
      next.addAll(lots.map((f) => f.id));
    } else {
      next.removeAll(lots.map((f) => f.id));
    }
    if (groupRecipeFoods(eligible.where((f) => next.contains(f.id))).length >
        10) {
      recipeMessage(context, '재료는 최대 10종까지 선택할 수 있어요. 다른 재료를 해제해주세요.');
      return;
    }
    setState(() {
      selected
        ..clear()
        ..addAll(next);
    });
  }

  Future<void> _privacy() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('전송 및 기기 저장 안내'),
      content: const SingleChildScrollView(
        child: Text(
          '추천을 요청하면 선택 재료의 이름·양·단위·남은 일수, 확인한 양념, 인분·시간·구매 조건과 제외 조건을 RECARE 서버와 OpenAI로 전송해 조리법을 생성해요. 구매금액, 전체 처리 이력과 기기 재고 ID는 OpenAI에 보내지 않아요.\n\n'
          '원문 제외 조건은 현재 화면의 메모리에만 유지하며 최근 추천이나 즐겨찾기에 저장하지 않아요. 레시피 본문에는 조건을 반영한 내용이 남을 수 있어요. 최근 5회와 즐겨찾기 최대 100개는 이 기기에 저장하며 앱 삭제 시 사라져요.\n\n'
          '서비스 개인정보 처리방침의 공개 주소는 아직 준비 중이에요. 공개 운영 전 처리 주체·보관 정책과 정식 안내를 확정해야 해요. OpenAI의 모든 로그가 즉시 삭제된다는 의미는 아니에요.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('닫기'),
        ),
      ],
    ),
  );
  Future<void> _generate() async {
    if (preparing || page == 'loading') return;
    setState(() {
      preparing = true;
      error = null;
    });
    try {
      if (await _refreshStock() || !mounted) return;
      final stocks = _selectedStocks();
      if (stocks.isEmpty || stocks.length > 10) return;
      if (consentVersion < 1) {
        final agreed =
            await showDialog<bool>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: const Text('추천 전 전송 정보를 확인해주세요'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '선택한 재료의 이름·양·단위·소비기한까지 남은 일수, 양념 보유 정보, 인분·시간·추가 구매·제외 조건을 RECARE 서버와 OpenAI에 보내요. 구매금액과 전체 처리 이력은 보내지 않아요.\n\n제외 조건 원문은 기기에 저장하지 않지만 생성된 설명에는 반영될 수 있어요.',
                      ),
                      TextButton(
                        onPressed: _privacy,
                        child: const Text('개인정보 및 기기 저장 안내'),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('취소'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('확인하고 추천받기'),
                  ),
                ],
              ),
            ) ??
            false;
        if (!mounted || !agreed) return;
        setState(() => consentVersion = 1);
      }
      await widget.repository.saveSettings(settings);
      if (!mounted) return;
      // Recheck stock after the consent dialog, which may span midnight.
      if (await _refreshStock() || !mounted) return;
      final request = RecipeRequest(
        requestId: const Uuid().v4(),
        stocks: _selectedStocks(),
        staples: staples.toList(),
        servings: servings,
        maxMinutes: minutes,
        allowShopping: shopping,
        exclusions: exclusions.text.trim(),
      );
      request.toJson(widget.clock());
      pendingRequest = request;
      await _runRequest(request, lookup: false);
    } catch (e) {
      if (mounted) setState(() => error = recipeError(e));
    } finally {
      if (mounted) setState(() => preparing = false);
    }
  }

  Future<void> _runRequest(
    RecipeRequest request, {
    required bool lookup,
  }) async {
    final epoch = ++requestEpoch;
    setState(() {
      if (!lookup && page != 'loading') history.add(page);
      page = 'loading';
      error = null;
    });
    try {
      final response =
          await (lookup
                  ? widget.client.lookup(request, widget.clock())
                  : widget.client.recommend(request, widget.clock()))
              .timeout(const Duration(seconds: 35));
      if (!mounted || epoch != requestEpoch) return;
      if (response == null) {
        setState(() {
          page = 'error';
          error = '이 요청의 저장된 결과가 아직 없어요. 잠시 후 같은 요청 상태를 다시 확인하거나 조건 화면에서 새 추천을 명시적으로 시작해주세요.';
        });
        return;
      }
      await widget.repository.saveRecent(response);
      if (!mounted || epoch != requestEpoch) return;
      recent = await widget.repository.loadRecent();
      if (!mounted || epoch != requestEpoch) return;
      setState(() {
        result = response;
        resultRequest = request;
        page = 'results';
      });
    } on RecipeClientException catch (e) {
      if (!mounted || epoch != requestEpoch) return;
      setState(() {
        page = 'error';
        error =
            '${e.message}${e.retryAt == null ? '' : '\n다시 이용 가능: ${e.retryAt!.toLocal()}'}';
      });
    } on TimeoutException {
      if (!mounted || epoch != requestEpoch) return;
      widget.client.cancel();
      setState(() {
        page = 'error';
        error =
            '응답을 기다리는 시간이 길어졌어요. 같은 요청의 결과를 확인할 수 있어요. 새 추천은 버튼을 누를 때만 시작해요.';
      });
    } catch (e) {
      if (!mounted || epoch != requestEpoch) return;
      setState(() {
        page = 'error';
        error = '추천에는 인터넷 연결이 필요해요. 입력을 유지했어요. 최근 추천과 즐겨찾기는 기기에서 볼 수 있어요.';
      });
    }
  }

  void _cancel() {
    requestEpoch++;
    widget.client.cancel();
    setState(() {
      page = 'input';
      if (history.isNotEmpty && history.last == 'input') history.removeLast();
      preparing = false;
      notice = '추천을 취소했어요. 이미 시작된 서버 작업의 비용은 발생할 수 있어요.';
    });
  }

  Future<void> _openDetail(Recipe recipe, {bool saved = false}) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => RecipeDetailPage(
          recipe: recipe,
          inventory: widget.inventory,
          repository: widget.repository,
          favorites: favorites,
          clock: widget.clock,
          saved: saved,
          onRecommend: () {
            setState(() {
              if (page != 'input') history.add(page);
              page = 'input';
              selected
                ..clear()
                ..addAll(
                  recipe.stockFoodIds.intersection(
                    eligible.map((f) => f.id).toSet(),
                  ),
                );
              exclusions.clear();
              notice = '현재 재고와 제외 조건을 확인한 뒤 추천 버튼을 눌러주세요.';
            });
          },
        ),
      ),
    );
    if (mounted) await _refreshStock();
  }

  void _show(String value) {
    setState(() {
      if (page != value) history.add(page);
      page = value;
      search.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (page) {
      'recent' => '최근 추천',
      'favorites' => '즐겨찾기',
      'results' => '추천 결과',
      _ => 'AI 레시피',
    };
    return PopScope(
      canPop: allowExit || (page != 'loading' && history.isEmpty),
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) {
          ScaffoldMessenger.of(context).removeCurrentSnackBar();
          return;
        }
        if (page != 'loading') {
          if (history.isNotEmpty) {
            setState(() {
              page = history.removeLast();
              search.clear();
            });
          }
          return;
        }
        final exit = await recipeConfirm(
          context,
          '추천을 취소하고 나갈까요?',
          '입력 화면으로 돌아갈 수 있어요. 이미 시작한 서버 작업에는 비용이 발생할 수 있어요.',
          action: '취소하고 나가기',
        );
        if (!context.mounted || !exit) return;
        _cancel();
        setState(() => allowExit = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) Navigator.pop(context);
        });
      },
      child: Scaffold(
        appBar: AppBar(
          leading: history.isNotEmpty && page != 'loading'
              ? BackButton(
                  onPressed: () {
                    setState(() {
                      page = history.removeLast();
                      search.clear();
                    });
                  },
                )
              : null,
          title: Text(title),
          actions: [
            IconButton(
              tooltip: '전송 및 저장 안내',
              onPressed: _privacy,
              icon: const Icon(Icons.info_outline),
            ),
          ],
        ),
        body: initialLoading
            ? const Center(
                child: CircularProgressIndicator(
                  key: ValueKey('recipe-initial-loading'),
                ),
              )
            : _body(),
        bottomNavigationBar: page == 'input' && !initialLoading
            ? RecipeBottomAction(
                child: FilledButton(
                  key: const ValueKey('recipe-generate'),
                  onPressed: _selectedStocks().isEmpty || preparing
                      ? null
                      : _generate,
                  child: Text(
                    preparing
                        ? '재고 확인 중…'
                        : '선택한 ${_selectedStocks().length}개 재료로 추천받기',
                  ),
                ),
              )
            : null,
      ),
    );
  }

  Widget _links() => Wrap(
    spacing: Space.sm,
    children: [
      TextButton(onPressed: () => _show('input'), child: const Text('재료·조건')),
      if (result != null)
        TextButton(
          onPressed: () => _show('results'),
          child: const Text('현재 결과'),
        ),
      TextButton(onPressed: () => _show('recent'), child: const Text('최근 추천')),
      TextButton(
        onPressed: () => _show('favorites'),
        child: const Text('즐겨찾기'),
      ),
    ],
  );
  Widget _body() {
    if (page == 'loading') {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Space.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: Space.xl),
              const Text('선택한 재료로 요리를 찾고 있어요'),
              const SizedBox(height: Space.md),
              const Text('취소해도 이미 시작한 서버 작업의 비용은 발생할 수 있어요.'),
              TextButton(onPressed: _cancel, child: const Text('추천 취소')),
            ],
          ),
        ),
      );
    }
    if (page == 'input') return _input();
    if (page == 'error') {
      return ListView(
        padding: const EdgeInsets.all(Space.lg),
        children: [
          _links(),
          const SizedBox(height: Space.xl),
          Text(error ?? '추천을 완료하지 못했어요.'),
          if (pendingRequest != null)
            FilledButton(
              onPressed: () => _runRequest(pendingRequest!, lookup: true),
              child: const Text('같은 요청 결과 확인'),
            ),
          TextButton(
            onPressed: () => _show('input'),
            child: const Text('조건 수정 · 새 추천 준비'),
          ),
        ],
      );
    }
    if (page == 'favorites' || page == 'recent') return _saved();
    final recipes = result?.recipes ?? <Recipe>[];
    return ListView(
      padding: const EdgeInsets.all(Space.lg),
      children: [
        _links(),
        Text(
          '${resultRequest?.stocks.map((s) => s.name).join(' · ') ?? ''}\n${resultRequest?.servings ?? servings}인분 · ${resultRequest?.maxMinutes == null ? '시간 제한 없음' : '${resultRequest!.maxMinutes}분 이내'}',
        ),
        const SizedBox(height: Space.md),
        const Text('각 요리는 독립적인 대안이에요. 추천 당시 재고를 기준으로 해요.'),
        if (recipes.length < 3)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.md),
            child: Text(
              result?.message.isNotEmpty == true
                  ? result!.message
                  : '조건에 맞는 요리 ${recipes.length}개를 찾았어요. 조건을 완화하지 않았어요.',
            ),
          ),
        if (recipes.isEmpty) const Text('조건에 맞는 요리가 없어요. 재료나 조건을 확인해주세요.'),
        for (final recipe in recipes)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.md),
            child: RecipeCard(
              recipe: recipe,
              favorites: favorites,
              onOpen: () => _openDetail(recipe),
            ),
          ),
        TextButton(onPressed: () => _show('input'), child: const Text('조건 수정')),
      ],
    );
  }

  Widget _input() {
    final filtered = groups
        .where(
          (g) =>
              g.name.toLowerCase().contains(search.text.trim().toLowerCase()),
        )
        .toList();
    final expired = foods
        .where(
          (f) =>
              f.remaining > 0 && f.expiry.isBefore(civilDate(widget.clock())),
        )
        .length;
    return ListView(
      padding: const EdgeInsets.all(Space.lg),
      children: [
        _links(),
        if (notice != null) _banner(notice!),
        if (error != null) _banner(error!),
        Text('사용할 재료', style: Theme.of(context).textTheme.titleMedium),
        const Text('오늘부터 3일 안에 기한이 오는 재료를 먼저 선택했어요. 재료 상태와 제품 표시를 직접 확인해주세요.'),
        if (expired > 0) Text('소비기한이 지난 재료 $expired개는 추천에서 제외했어요.'),
        if (eligible.isEmpty) ...[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: Space.xl),
            child: Text('추천 가능한 재료가 없어요. 식재료를 등록하거나 현재 재고를 확인해주세요.'),
          ),
          if (widget.onRegister != null)
            FilledButton(
              onPressed: () async {
                await widget.onRegister!();
                if (!mounted) return;
                await _refreshStock();
              },
              child: const Text('식재료 등록'),
            ),
        ] else ...[
          const SizedBox(height: Space.md),
          TextField(
            key: const ValueKey('recipe-stock-search'),
            controller: search,
            decoration: const InputDecoration(
              labelText: '재료 검색',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: Space.md),
          if (filtered.isEmpty) const Text('검색한 재료가 없어요.'),
          for (final group in filtered) _group(group),
          Text('${_selectedStocks().length}/10종 선택 · 같은 이름과 단위 계열만 묶어요.'),
        ],
        const SizedBox(height: Space.xl),
        Text('보유한 기본 양념', style: Theme.of(context).textTheme.titleMedium),
        const Text('집에 있는 양념만 직접 선택해주세요. 선택하지 않은 양념을 보유한 것으로 간주하지 않아요.'),
        Wrap(
          spacing: Space.sm,
          children: [
            for (final staple in recipeStaples)
              FilterChip(
                label: Text(staple),
                selected: staples.contains(staple),
                onSelected: (v) {
                  setState(() {
                    if (v) {
                      staples.add(staple);
                    } else {
                      staples.remove(staple);
                    }
                  });
                  _persistSettings();
                },
              ),
          ],
        ),
        const SizedBox(height: Space.xl),
        Text('인분', style: Theme.of(context).textTheme.titleMedium),
        Wrap(
          spacing: Space.sm,
          children: [
            for (var n = 1; n <= 4; n++)
              ChoiceChip(
                label: Text('$n인분'),
                selected: servings == n,
                onSelected: (_) {
                  setState(() => servings = n);
                  _persistSettings();
                },
              ),
          ],
        ),
        const SizedBox(height: Space.lg),
        Text('예상 조리 시간', style: Theme.of(context).textTheme.titleMedium),
        Wrap(
          spacing: Space.sm,
          children: [
            for (final n in <int?>[10, 20, 30, null])
              ChoiceChip(
                label: Text(n == null ? '제한 없음' : '$n분 이내'),
                selected: minutes == n,
                onSelected: (_) {
                  setState(() => minutes = n);
                  _persistSettings();
                },
              ),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('추가 구매 허용'),
          subtitle: const Text('최대 3종의 부족 재료를 제안할 수 있어요.'),
          value: shopping,
          onChanged: (v) => setState(() => shopping = v),
        ),
        TextField(
          key: const ValueKey('recipe-exclusions'),
          controller: exclusions,
          maxLength: 200,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: '알레르기·제외 재료',
            hintText: '예: 땅콩, 새우',
            helperText: '현재 화면에서만 유지해요. 완전한 알레르기 안전 판정이 아니므로 제품 표시를 확인해주세요.',
          ),
        ),
        const SizedBox(height: Space.xl),
      ],
    );
  }

  Widget _banner(String text) => Padding(
    padding: const EdgeInsets.only(bottom: Space.lg),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.md),
        child: Text(text),
      ),
    ),
  );
  Widget _group(RecipeStock group) {
    final checked = group.foods.every((f) => selected.contains(f.id));
    final some = group.foods.any((f) => selected.contains(f.id));
    final first = group.foods.first;
    final days = first.expiry.difference(civilDate(widget.clock())).inDays;
    final heading = CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      value: checked ? true : (some ? null : false),
      tristate: true,
      title: Text(group.name),
      subtitle: Text(
        '${group.unit.quantityText(group.amount)} ${group.unit.label} · ${dateText(first.expiry)} · ${days == 0 ? '오늘까지' : '$days일 남음'}',
      ),
      onChanged: (_) => _toggleFoods(group.foods, !checked),
    );
    if (group.foods.length == 1) return heading;
    return Column(
      children: [
        heading,
        ExpansionTile(
          title: Text('보관분 ${group.foods.length}개 선택'),
          children: [
            for (final food in group.foods)
              CheckboxListTile(
                value: selected.contains(food.id),
                title: Text(
                  '${food.unit.quantityText(food.remaining)} ${food.unit.label} · ${dateText(food.expiry)}',
                ),
                subtitle: Text('보관분 ${group.foods.indexOf(food) + 1}'),
                onChanged: (v) => _toggleFoods([food], v ?? false),
              ),
          ],
        ),
      ],
    );
  }

  Widget _saved() => ListenableBuilder(
    listenable: favorites,
    builder: (context, _) {
      final isFavorites = page == 'favorites';
      final all = isFavorites
          ? favorites.recipes
          : recent.expand((r) => r.recipes).toList();
      final query = search.text.trim().toLowerCase();
      final recipes = all
          .where(
            (r) => '${r.title} ${r.ingredients.map((i) => i.name).join(' ')}'
                .toLowerCase()
                .contains(query),
          )
          .toList();
      return ListView(
        padding: const EdgeInsets.all(Space.lg),
        children: [
          _links(),
          Text(
            isFavorites
                ? '${favorites.recipes.length}/100개 · 이 기기에만 저장해요'
                : '최근 ${recent.length}/5회 · 이 기기에만 저장해요',
          ),
          const Text('저장 당시 레시피예요. 현재 재고와 알레르기 조건을 확인해주세요.'),
          const SizedBox(height: Space.lg),
          TextField(
            controller: search,
            decoration: const InputDecoration(
              labelText: '요리명·주요 재료 검색',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (all.isEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.xl),
              child: Text(
                isFavorites ? '다시 만들고 싶은 요리를 별표로 저장해보세요.' : '아직 최근 추천이 없어요.',
              ),
            ),
            FilledButton(
              onPressed: () => _show('input'),
              child: const Text('레시피 추천받기'),
            ),
          ] else if (recipes.isEmpty) ...[
            const Text('검색 결과가 없어요.'),
            TextButton(
              onPressed: () {
                search.clear();
                setState(() {});
              },
              child: const Text('검색어 초기화'),
            ),
          ],
          for (final recipe in recipes)
            Padding(
              padding: const EdgeInsets.only(top: Space.md),
              child: RecipeCard(
                recipe: recipe,
                favorites: favorites,
                onOpen: () => _openDetail(recipe, saved: true),
              ),
            ),
          if (!isFavorites && recent.isNotEmpty)
            TextButton(
              onPressed: () async {
                if (!await recipeConfirm(
                  context,
                  '최근 추천을 모두 지울까요?',
                  '즐겨찾기와 먹음 기록은 유지해요.',
                  action: '최근 추천 삭제',
                )) {
                  return;
                }
                try {
                  await widget.repository.clearRecent();
                  if (mounted) setState(() => recent = []);
                } catch (e) {
                  if (context.mounted) recipeMessage(context, recipeError(e));
                }
              },
              child: const Text('최근 추천 이력 삭제'),
            ),
        ],
      );
    },
  );
}
