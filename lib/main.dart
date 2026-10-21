import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:uuid/uuid.dart';

import 'data/inventory_repository.dart';
import 'data/preferences.dart';
import 'domain/inventory.dart';
import 'domain/portions.dart';
import 'domain/food_catalog.dart';
import 'domain/shopping.dart';
import 'services/reminder_service.dart';
import 'ui/reminder_settings.dart';
import 'ui/expiry_check_in_dialog.dart';
import 'ui/batch_registration.dart';
import 'ui/shopping_page.dart';
import 'ui/waste_insights_view.dart';
import 'ui/food_illustration.dart';
import 'ui/ingredient_autocomplete.dart';
import 'ui/design_system.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RecareApp());
}

typedef RepositoryFactory = Future<InventoryRepository> Function();
typedef Clock = DateTime Function();

typedef PreferencesFactory = Future<PreferencesStore> Function();

class RecareApp extends StatefulWidget {
  const RecareApp({
    super.key,
    this.repositoryFactory,
    this.preferencesFactory,
    this.reminderService,
    this.automaticCheckIns = true,
    this.clock,
  });
  final RepositoryFactory? repositoryFactory;
  final PreferencesFactory? preferencesFactory;
  final ReminderService? reminderService;
  final bool automaticCheckIns;
  final Clock? clock;
  @override
  State<RecareApp> createState() => _RecareAppState();
}

class _RecareAppState extends State<RecareApp> {
  final _routes = RouteObserver<ModalRoute<dynamic>>();
  AppPreferences _preferences = const AppPreferences();
  PreferencesStore? _store;
  bool _preferencesBusy = true;
  String? _preferencesError;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPreferences());
  }

  Future<void> _loadPreferences() async {
    if (mounted) {
      setState(() {
        _preferencesBusy = true;
        _preferencesError = null;
      });
    }
    try {
      final store =
          await (widget.preferencesFactory ?? PreferencesStore.open)();
      final preferences = await store.load();
      if (mounted) {
        setState(() {
          _store = store;
          _preferences = preferences;
          _preferencesBusy = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _preferencesBusy = false;
          _preferencesError = '설정을 불러오지 못했어요. 다시 시도해주세요.';
        });
      }
    }
  }

  Future<void> _changePreferences(AppPreferences preferences) async {
    if (_preferencesBusy || _store == null) return;
    setState(() {
      _preferencesBusy = true;
      _preferencesError = null;
    });
    try {
      await _store!.save(preferences);
      if (mounted) {
        setState(() {
          _preferences = preferences;
          _preferencesBusy = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _preferencesBusy = false;
          _preferencesError = '설정을 저장하지 못했어요. 다시 선택해주세요.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'RE:CARE',
    navigatorObservers: [_routes],
    debugShowCheckedModeBanner: false,
    locale: const Locale('ko'),
    supportedLocales: const [Locale('ko')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: RecareTheme.light,
    darkTheme: RecareTheme.dark,
    themeMode: switch (_preferences.appearance) {
      AppAppearance.system => ThemeMode.system,
      AppAppearance.light => ThemeMode.light,
      AppAppearance.dark => ThemeMode.dark,
    },
    home: InventoryHome(
      reminderService: widget.reminderService,
      automaticCheckIns: widget.automaticCheckIns,
      routeObserver: _routes,
      repositoryFactory: widget.repositoryFactory ?? InventoryRepository.open,
      clock: widget.clock ?? DateTime.now,
      preferences: _preferences,
      preferencesBusy: _preferencesBusy,
      preferencesAvailable: _store != null,
      preferencesError: _preferencesError,
      onPreferencesChanged: _changePreferences,
      onPreferencesRetry: _loadPreferences,
    ),
  );
}

String money(int? value) => value == null
    ? '금액 미입력'
    : '${value.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',')}원';
String quantity(Food food) =>
    '${food.unit.quantityText(food.remaining)} ${food.unit.label}';
String errorText(Object error) => error is ArgumentError
    ? error.message.toString()
    : '저장 결과를 확인하지 못했어요. 다시 시도해주세요.';
void notify(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

Future<void> addFoodToShopping(
  InventoryRepository repository,
  Food food,
  DateTime now,
) => repository.addShoppingItem(
  ShoppingItem(
    id: const Uuid().v4(),
    name: food.name,
    unit: food.unit,
    amount: food.total,
    created: now,
  ),
);

void showProcessingUndo(
  BuildContext context, {
  required InventoryRepository repository,
  required String recordId,
  required ActionKind kind,
  required Future<void> Function() onChanged,
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text('${kind.label} 기록을 저장했어요.'),
      duration: const Duration(seconds: 8),
      action: SnackBarAction(
        label: '실행 취소',
        onPressed: () {
          if (!context.mounted) return;
          unawaited(() async {
            try {
              final undone = await repository.undoProcess(recordId);
              await onChanged();
              if (context.mounted) {
                notify(
                  context,
                  undone
                      ? '처리를 되돌렸어요. 재고와 금액을 복원했어요.'
                      : '지금은 이 처리를 되돌릴 수 없어요. 최신 재고를 확인해주세요.',
                );
              }
            } catch (e) {
              if (context.mounted) notify(context, errorText(e));
            }
          }());
        },
      ),
    ),
  );
}

String deadline(Food food, DateTime today) {
  if (food.remaining == 0) return '모두 처리됨';
  final days = food.expiry.difference(civilDate(today)).inDays;
  return days < 0
      ? '${-days}일 지남'
      : days == 0
      ? 'D-Day'
      : 'D-$days';
}

class InventoryHome extends StatefulWidget {
  const InventoryHome({
    super.key,
    required this.repositoryFactory,
    required this.clock,
    required this.preferences,
    required this.preferencesBusy,
    required this.preferencesAvailable,
    required this.preferencesError,
    required this.onPreferencesChanged,
    required this.onPreferencesRetry,
    this.reminderService,
    this.automaticCheckIns = true,
    this.routeObserver,
  });
  final RepositoryFactory repositoryFactory;
  final Clock clock;
  final AppPreferences preferences;
  final bool preferencesBusy, preferencesAvailable;
  final String? preferencesError;
  final Future<void> Function(AppPreferences) onPreferencesChanged;
  final VoidCallback onPreferencesRetry;
  final ReminderService? reminderService;
  final bool automaticCheckIns;
  final RouteObserver<ModalRoute<dynamic>>? routeObserver;
  @override
  State<InventoryHome> createState() => _InventoryHomeState();
}

class _InventoryHomeState extends State<InventoryHome>
    with WidgetsBindingObserver, RouteAware {
  ModalRoute<dynamic>? _observedRoute;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null && route != _observedRoute) {
      widget.routeObserver?.unsubscribe(this);
      widget.routeObserver?.subscribe(this, route);
      _observedRoute = route;
    }
  }

  @override
  void didPopNext() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_maybeShowCheckIns());
    });
  }

  InventoryRepository? _repo;
  InventorySnapshot _snapshot = InventorySnapshot([], []);
  bool _loading = true, _failed = false;
  int _tab = 0;
  late DateTime _today;
  Timer? _timer;
  late final ReminderService _reminders;
  StreamSubscription<void>? _reminderOpens;
  bool _urgentOnly = false;
  bool _checkInsPending = true, _checkInShowing = false;
  @override
  void initState() {
    super.initState();
    _today = civilDate(widget.clock());
    _reminders = widget.reminderService ?? ReminderService();
    _reminderOpens = _reminders.openUrgentRequests.listen((_) => _openUrgent());
    unawaited(_consumeReminder());
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      final day = civilDate(widget.clock());
      if (day != _today && mounted) {
        setState(() => _today = day);
        _checkInsPending = true;
        if (!_loading) unawaited(_refresh());
      }
    });
  }

  void _openUrgent() {
    if (!mounted) return;
    _checkInsPending = true;
    if (!_checkInShowing) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
    setState(() {
      _tab = 1;
      _urgentOnly = true;
    });
    if (!_loading) unawaited(_refresh());
  }

  Future<void> _consumeReminder() async {
    try {
      if (await _reminders.consumeOpenUrgent()) _openUrgent();
    } catch (_) {
      /* A reminder bridge failure must not block offline inventory. */
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _checkInsPending = true;
      setState(() => _today = civilDate(widget.clock()));
      if (!_loading) unawaited(_refresh());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.routeObserver?.unsubscribe(this);
    unawaited(_reminderOpens?.cancel());
    if (widget.reminderService == null) _reminders.dispose();
    WidgetsBinding.instance.removeObserver(this);
    if (_repo != null) unawaited(_repo!.close());
    super.dispose();
  }

  Future<void> _refresh() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _failed = false;
      });
    }
    try {
      final repo = _repo ?? await widget.repositoryFactory();
      if (!mounted) {
        await repo.close();
        return;
      }
      _repo = repo;
      final snapshot = await repo.load();
      if (mounted) {
        setState(() {
          _snapshot = snapshot;
          _loading = false;
        });
        unawaited(_maybeShowCheckIns());
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _failed = true;
          _loading = false;
        });
      }
    }
  }

  bool get _foreground =>
      WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  Future<void> _maybeShowCheckIns() async {
    if (!_foreground ||
        !widget.automaticCheckIns ||
        !_checkInsPending ||
        _checkInShowing ||
        !mounted ||
        _loading ||
        _failed ||
        _repo == null ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    _checkInShowing = true;
    _checkInsPending = false;
    var opened = false;
    try {
      final foods = await _repo!.pendingExpiryCheckIns(widget.clock());
      if (!mounted ||
          foods.isEmpty ||
          !_foreground ||
          ModalRoute.of(context)?.isCurrent != true) {
        if (mounted && foods.isNotEmpty) _checkInsPending = true;
        return;
      }
      opened = true;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ExpiryCheckInDialog(
          repository: _repo!,
          foods: foods,
          clock: widget.clock,
        ),
      );
    } catch (_) {
      // A check-in failure must never prevent opening the offline inventory.
      _checkInsPending = true;
    } finally {
      _checkInShowing = false;
      if (opened && mounted) unawaited(_refresh());
    }
  }

  Future<void> _add() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => FoodEditor(repository: _repo!, clock: widget.clock),
      ),
    );
    if (!mounted) return;
    if (saved == true) {
      await _refresh();
      if (mounted) notify(context, '식재료를 등록했어요.');
    } else {
      unawaited(_maybeShowCheckIns());
    }
  }

  Future<void> _batch() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            BatchRegistrationPage(repository: _repo!, clock: widget.clock),
      ),
    );
    if (mounted && saved == true) {
      await _refresh();
      if (mounted) notify(context, '선택한 재료를 모두 등록했어요.');
    }
  }

  Future<void> _shopping() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ShoppingPage(repository: _repo!, clock: widget.clock),
      ),
    );
    if (mounted) await _refresh();
  }

  Future<void> _quickProcess(Food food, ActionKind kind) async {
    String? recordId;
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ProcessDialog(
        repository: _repo!,
        food: food,
        kind: kind,
        clock: widget.clock,
        onSaved: (id) => recordId = id,
      ),
    );
    if (!mounted || saved != true) return;
    await _refresh();
    if (mounted && recordId != null) {
      showProcessingUndo(
        context,
        repository: _repo!,
        recordId: recordId!,
        kind: kind,
        onChanged: _refresh,
      );
    }
  }

  Future<void> _addShopping(Food food) async {
    try {
      await addFoodToShopping(_repo!, food, widget.clock());
      if (mounted) notify(context, '장보기 목록에 담았어요. 같은 항목은 한 번만 표시해요.');
    } catch (e) {
      if (mounted) notify(context, errorText(e));
    }
  }

  Future<void> _open(Food food) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => FoodDetail(
          repository: _repo!,
          food: food,
          clock: widget.clock,
          onProcessed: (recordId, kind, refreshDetail) {
            if (!mounted) return;
            showProcessingUndo(
              context,
              repository: _repo!,
              recordId: recordId,
              kind: kind,
              onChanged: () async {
                if (mounted) await _refresh();
                await refreshDetail();
              },
            );
          },
        ),
      ),
    );
    if (mounted) await _refresh();
  }

  void _showWeek() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('이번 주 폐기')),
          body: SafeArea(
            child: WeekView(week: weeklyWaste(_snapshot.records, _today)),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final active = _snapshot.foods.where((f) => f.remaining > 0).toList();
    int compareExpiry(Food a, Food b) {
      final date = a.expiry.compareTo(b.expiry);
      return date == 0 ? a.name.compareTo(b.name) : date;
    }

    final visible =
        (widget.preferences.includeFinished ? _snapshot.foods : active)
            .where(
              (food) =>
                  !_urgentOnly ||
                  (food.remaining > 0 &&
                      !food.expiry.isAfter(
                        _today.add(const Duration(days: 3)),
                      )),
            )
            .toList()
          ..sort(compareExpiry);
    final urgent =
        active
            .where(
              (f) => !f.expiry.isAfter(_today.add(const Duration(days: 3))),
            )
            .toList()
          ..sort(compareExpiry);
    return Scaffold(
      appBar: AppBar(
        title: Text(switch (_tab) {
          0 => 'RE:CARE',
          1 => '식재료 목록',
          _ => '설정',
        }),
        actions: [
          IconButton(
            key: const ValueKey('open-shopping'),
            tooltip: '장보기 목록',
            onPressed: _loading || _failed || _repo == null ? null : _shopping,
            icon: const Icon(Icons.shopping_basket_outlined),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) => setState(() => _tab = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: '홈'),
          NavigationDestination(
            icon: Icon(Icons.view_list_outlined),
            label: '목록',
          ),
          NavigationDestination(icon: Icon(Icons.tune_outlined), label: '설정'),
        ],
      ),
      body: SafeArea(
        child: _tab == 2
            ? SettingsView(
                preferences: widget.preferences,
                busy: widget.preferencesBusy,
                available: widget.preferencesAvailable,
                error: widget.preferencesError,
                onChanged: widget.onPreferencesChanged,
                onRetry: widget.onPreferencesRetry,
                reminderService: _reminders,
              )
            : _loading
            ? const Center(child: CircularProgressIndicator())
            : _failed
            ? ErrorPanel(onRetry: _refresh)
            : Column(
                children: [
                  Expanded(
                    child: _tab == 0
                        ? HomeOverview(
                            week: weeklyWaste(_snapshot.records, _today),
                            urgent: urgent,
                            hasStock: active.isNotEmpty,
                            today: _today,
                            onOpen: _open,
                            onWeek: _showWeek,
                            onList: () => setState(() => _tab = 1),
                          )
                        : ListView.builder(
                            key: const ValueKey('inventory-page'),
                            padding: const EdgeInsets.symmetric(
                              horizontal: Space.xl,
                            ),
                            itemCount: visible.isEmpty ? 2 : visible.length + 1,
                            itemBuilder: (context, index) {
                              if (index == 0) {
                                return Padding(
                                  padding: const EdgeInsets.only(
                                    top: Space.sm,
                                    bottom: Space.lg,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              '${visible.length}개 식재료',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodyMedium,
                                            ),
                                          ),
                                          Text(
                                            '소비기한순',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall,
                                          ),
                                        ],
                                      ),
                                      Wrap(
                                        spacing: Space.sm,
                                        children: [
                                          ChoiceChip(
                                            key: const ValueKey(
                                              'inventory-all',
                                            ),
                                            label: const Text('전체'),
                                            selected: !_urgentOnly,
                                            onSelected: (_) => setState(
                                              () => _urgentOnly = false,
                                            ),
                                          ),
                                          ChoiceChip(
                                            key: const ValueKey(
                                              'inventory-urgent',
                                            ),
                                            label: const Text('3일 이내·지난 재료'),
                                            selected: _urgentOnly,
                                            onSelected: (_) => setState(
                                              () => _urgentOnly = true,
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (visible.isNotEmpty) ...[
                                        const SizedBox(height: Space.sm),
                                        Text(
                                          '식재료를 선택하면 상세 정보를 확인할 수 있어요.',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                      ],
                                    ],
                                  ),
                                );
                              }
                              if (visible.isEmpty) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: Space.xxl,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _urgentOnly
                                            ? '3일 이내이거나 소비기한이 지난 재료가 없어요.'
                                            : _snapshot.foods.isEmpty
                                            ? '아직 등록된 식재료가 없어요.'
                                            : '보관 중인 식재료가 없어요.',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyLarge,
                                      ),
                                      const SizedBox(height: Space.sm),
                                      Text(
                                        _urgentOnly
                                            ? '전체를 선택하면 다른 재료를 볼 수 있어요.'
                                            : _snapshot.foods.isEmpty
                                            ? '냉장고 속 식재료를 등록해보세요.'
                                            : '설정에서 처리 완료 표시를 켜면 이전 식재료를 볼 수 있어요.',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ],
                                  ),
                                );
                              }
                              final food = visible[index - 1];
                              return IngredientRow(
                                food: food,
                                today: _today,
                                onTap: () => _open(food),
                                onEat: () =>
                                    _quickProcess(food, ActionKind.eat),
                                onWaste: () =>
                                    _quickProcess(food, ActionKind.waste),
                                onShopping: () => _addShopping(food),
                              );
                            },
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Space.xl,
                      Space.md,
                      Space.xl,
                      Space.lg,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FilledButton(
                          onPressed: _add,
                          child: const Text('식재료 등록'),
                        ),
                        TextButton.icon(
                          key: const ValueKey('open-batch'),
                          onPressed: _batch,
                          icon: const Icon(Icons.playlist_add),
                          label: const Text('한 번에 등록'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

String weeklyAmount(WeekSummary week) =>
    week.records.isNotEmpty && week.unknownCount == week.records.length
    ? '금액 미입력'
    : money(week.knownTotal);
String weeklyCount(WeekSummary week) =>
    '폐기 ${week.records.length}건${week.unknownCount > 0 ? ' · 금액 미입력 ${week.unknownCount}건' : ''}';

class HomeOverview extends StatelessWidget {
  const HomeOverview({
    super.key,
    required this.week,
    required this.urgent,
    required this.hasStock,
    required this.today,
    required this.onOpen,
    required this.onWeek,
    required this.onList,
  });
  final WeekSummary week;
  final List<Food> urgent;
  final bool hasStock;
  final DateTime today;
  final ValueChanged<Food> onOpen;
  final VoidCallback onWeek, onList;

  @override
  Widget build(BuildContext context) => ListView(
    key: const ValueKey('home-page'),
    padding: const EdgeInsets.all(Space.xl),
    children: [
      Text('이번 주 폐기 금액', style: Theme.of(context).textTheme.bodyMedium),
      const SizedBox(height: Space.sm),
      Text(
        weeklyAmount(week),
        key: const ValueKey('weekly-total'),
        style: Theme.of(context).textTheme.displaySmall,
      ),
      const SizedBox(height: Space.sm),
      Text(weeklyCount(week), style: Theme.of(context).textTheme.bodyMedium),
      if (week.unknownCount > 0 && week.unknownCount != week.records.length)
        Padding(
          padding: const EdgeInsets.only(top: Space.xs),
          child: Text(
            '금액을 입력한 기록만 합산했어요.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(onPressed: onWeek, child: const Text('폐기 내역')),
      ),
      const SizedBox(height: Space.lg),
      const Divider(height: 1),
      const SizedBox(height: Space.lg),
      Row(
        children: [
          Expanded(
            child: Text(
              '먼저 확인할 재료',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          TextButton(onPressed: onList, child: const Text('전체 목록')),
        ],
      ),
      if (urgent.isNotEmpty)
        Text(
          '소비기한이 지났거나 3일 이내인 재료를 확인해보세요.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      const SizedBox(height: Space.sm),
      if (urgent.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.xl),
          child: Text(
            hasStock
                ? '소비기한이 임박한 재료가 없어요.'
                : '보관 중인 식재료가 없어요. 냉장고 속 식재료를 등록해보세요.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      for (final food in urgent.take(4))
        IngredientRow(food: food, today: today, onTap: () => onOpen(food)),
      if (urgent.length > 4)
        Padding(
          padding: const EdgeInsets.only(top: Space.md),
          child: Text(
            '임박한 재료 ${urgent.length - 4}개 더 있음',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
    ],
  );
}

class SettingsView extends StatelessWidget {
  const SettingsView({
    super.key,
    required this.preferences,
    required this.busy,
    required this.available,
    required this.error,
    required this.onChanged,
    required this.onRetry,
    this.reminderService,
  });
  final ReminderService? reminderService;
  final AppPreferences preferences;
  final bool busy, available;
  final String? error;
  final Future<void> Function(AppPreferences) onChanged;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => ListView(
    key: const ValueKey('settings-page'),
    padding: const EdgeInsets.all(Space.xl),
    children: [
      if (busy) const LinearProgressIndicator(),
      if (error != null) ...[
        const SizedBox(height: Space.lg),
        Text(
          error!,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: Theme.of(context).colorScheme.error),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: busy ? null : onRetry,
            child: const Text('다시 시도'),
          ),
        ),
      ],
      Text('화면', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: Space.lg),
      Text('화면 모드', style: Theme.of(context).textTheme.bodyMedium),
      const SizedBox(height: Space.sm),
      Wrap(
        spacing: Space.sm,
        runSpacing: Space.sm,
        children: [
          for (final appearance in AppAppearance.values)
            ChoiceChip(
              key: ValueKey('appearance-${appearance.name}'),
              label: Text(switch (appearance) {
                AppAppearance.system => '시스템',
                AppAppearance.light => '라이트',
                AppAppearance.dark => '다크',
              }),
              selected: preferences.appearance == appearance,
              showCheckmark: false,
              onSelected: busy || !available
                  ? null
                  : (_) => unawaited(
                      onChanged(preferences.copyWith(appearance: appearance)),
                    ),
            ),
        ],
      ),
      const SizedBox(height: Space.xl),
      const Divider(height: 1),
      const SizedBox(height: Space.xl),
      Text('목록', style: Theme.of(context).textTheme.titleMedium),
      SwitchListTile.adaptive(
        key: const ValueKey('include-finished'),
        contentPadding: EdgeInsets.zero,
        title: const Text('처리 완료 표시'),
        subtitle: const Text('재고가 없는 식재료도 표시'),
        value: preferences.includeFinished,
        onChanged: busy || !available
            ? null
            : (value) => unawaited(
                onChanged(preferences.copyWith(includeFinished: value)),
              ),
      ),
      const SizedBox(height: Space.xl),
      const Divider(height: 1),
      const SizedBox(height: Space.xl),
      if (reminderService != null) ...[
        ReminderSettingsCard(service: reminderService!),
        const SizedBox(height: Space.xl),
      ],
      Text('저장과 기록', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: Space.md),
      Text(
        '식재료와 처리 기록은 이 기기에 저장됩니다.',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      const SizedBox(height: Space.sm),
      Text(
        '이번 주 폐기금액은 월요일부터 오늘까지의 폐기 기록을 합산합니다. 구매금액 미입력은 0원과 구분합니다.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );
}

class FoodDetail extends StatefulWidget {
  const FoodDetail({
    super.key,
    required this.repository,
    required this.food,
    required this.clock,
    this.onProcessed,
  });
  final InventoryRepository repository;
  final Food food;
  final Clock clock;
  final void Function(
    String recordId,
    ActionKind kind,
    Future<void> Function() refreshDetail,
  )?
  onProcessed;
  @override
  State<FoodDetail> createState() => _FoodDetailState();
}

class _FoodDetailState extends State<FoodDetail> {
  late Food _food;
  List<FoodRecord> _records = [];
  bool _loading = true, _failed = false, _deleting = false, _hasHistory = false;
  @override
  void initState() {
    super.initState();
    _food = widget.food;
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _failed = false;
      });
    }
    try {
      final snapshot = await widget.repository.load();
      final food = snapshot.foods.firstWhere((f) => f.id == _food.id);
      final hasHistory = await widget.repository.hasProcessingHistory(food.id);
      if (mounted) {
        setState(() {
          _food = food;
          _hasHistory = hasHistory;
          _records = snapshot.records
              .where((r) => r.foodId == food.id)
              .toList();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  Future<void> _edit() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => FoodEditor(
          repository: widget.repository,
          food: _food,
          hasRecords: _hasHistory,
          clock: widget.clock,
        ),
      ),
    );
    if (!mounted) return;
    if (saved == true) {
      await _refresh();
      if (mounted) notify(context, '식재료를 수정했어요.');
    }
  }

  Future<void> _process(ActionKind kind) async {
    String? recordId;
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ProcessDialog(
        repository: widget.repository,
        food: _food,
        kind: kind,
        clock: widget.clock,
        onSaved: (id) => recordId = id,
      ),
    );
    if (!mounted) return;
    if (saved == true) {
      await _refresh();
      if (mounted && recordId != null) {
        if (widget.onProcessed != null) {
          widget.onProcessed!(recordId!, kind, () async {
            if (mounted) await _refresh();
          });
        } else {
          showProcessingUndo(
            context,
            repository: widget.repository,
            recordId: recordId!,
            kind: kind,
            onChanged: _refresh,
          );
        }
      }
    }
  }

  Future<void> _addToShopping() async {
    try {
      await addFoodToShopping(widget.repository, _food, widget.clock());
      if (mounted) notify(context, '장보기 목록에 담았어요. 같은 재료·수량은 한 번만 담습니다.');
    } catch (e) {
      if (mounted) notify(context, errorText(e));
    }
  }

  Future<void> _delete() async {
    if (_loading || _failed || _deleting) return;
    if (_hasHistory) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('식재료 삭제'),
          content: const Text(
            '처리 기록이 있는 식재료는 삭제할 수 없어요. 남은 재고는 먹음 또는 폐기로 처리해주세요.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('확인'),
            ),
          ],
        ),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('식재료 삭제'),
        content: Text('${_food.name}\n냉장고 목록에서 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('삭제하기'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      await widget.repository.deleteFood(_food.id);
      if (mounted) {
        notify(context, '식재료를 삭제했어요.');
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _deleting = false);
        notify(context, errorText(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_deleting,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('식재료 상세'),
        actions: [
          TextButton(
            onPressed: _loading || _failed || _deleting ? null : _edit,
            child: const Text('수정'),
          ),
          TextButton(
            onPressed: _loading || _failed || _deleting ? null : _delete,
            child: const Text('삭제'),
          ),
          const SizedBox(width: Space.sm),
        ],
      ),
      body: SafeArea(
        child: _failed
            ? ErrorPanel(onRetry: _refresh)
            : ListView(
                key: const ValueKey('food-detail'),
                padding: const EdgeInsets.all(Space.xl),
                children: [
                  if (_loading || _deleting) const LinearProgressIndicator(),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          _food.name,
                          style: Theme.of(context).textTheme.headlineLarge,
                        ),
                      ),
                      const SizedBox(width: Space.md),
                      FoodIllustration(
                        visual: foodVisualForName(_food.name),
                        size: 56,
                      ),
                    ],
                  ),
                  const SizedBox(height: Space.sm),
                  ExpiryLine(food: _food, today: widget.clock()),
                  const SizedBox(height: Space.xxl),
                  Text('남은 재고', style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: Space.xs),
                  Text(
                    quantity(_food),
                    key: const ValueKey('remaining-stock'),
                    style: Theme.of(context).textTheme.displaySmall,
                  ),
                  const SizedBox(height: Space.xl),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: Theme.of(context)
                                .colorScheme
                                .secondary,
                          ),
                          onPressed:
                              _loading || _deleting || _food.remaining == 0
                              ? null
                              : () => _process(ActionKind.eat),
                          child: const Text('먹음 기록'),
                        ),
                      ),
                      const SizedBox(width: Space.md),
                      Expanded(
                        child: OutlinedButton(
                          onPressed:
                              _loading || _deleting || _food.remaining == 0
                              ? null
                              : () => _process(ActionKind.waste),
                          child: const Text('폐기 기록'),
                        ),
                      ),
                    ],
                  ),
                  if (_food.remaining == 0) ...[
                    const SizedBox(height: Space.md),
                    OutlinedButton.icon(
                      key: const ValueKey('detail-shopping-add'),
                      onPressed: _loading || _deleting ? null : _addToShopping,
                      icon: const Icon(Icons.add_shopping_cart_outlined),
                      label: const Text('다음 장보기 목록에 추가'),
                    ),
                  ],
                  const SizedBox(height: Space.xxl),
                  const Divider(height: 1),
                  const SizedBox(height: Space.md),
                  InfoRow(
                    label: '전체 구매금액',
                    value: money(_food.price),
                    emphasis: true,
                  ),
                  InfoRow(
                    label: '등록 수량',
                    value:
                        '${_food.unit.quantityText(_food.total)} ${_food.unit.label}',
                  ),
                  InfoRow(label: '등록일', value: dateText(_food.created)),
                  const SizedBox(height: Space.md),
                  const Divider(height: 1),
                  const SizedBox(height: Space.xl),
                  Text('처리 기록', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: Space.md),
                  if (!_loading && _records.isEmpty)
                    Text(
                      _hasHistory
                          ? '현재 반영된 처리 기록이 없어요. 되돌린 이력은 보존됩니다.'
                          : '아직 처리 기록이 없어요.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  for (final record in _records)
                    RecordRow(record: record, showFoodName: false),
                ],
              ),
      ),
    ),
  );
}

class FoodEditor extends StatefulWidget {
  const FoodEditor({
    super.key,
    required this.repository,
    required this.clock,
    this.food,
    this.hasRecords = false,
  });
  final InventoryRepository repository;
  final Clock clock;
  final Food? food;
  final bool hasRecords;
  @override
  State<FoodEditor> createState() => _FoodEditorState();
}

class _FoodEditorState extends State<FoodEditor> {
  final _form = GlobalKey<FormState>();
  late TextEditingController _name, _amount, _price;
  late FoodUnit _unit;
  late String _id;
  DateTime? _expiry;
  bool _busy = false, _searching = false;
  FoodSuggestion? _selection;
  String? _error;
  @override
  void initState() {
    super.initState();
    final food = widget.food;
    _id = food?.id ?? const Uuid().v4();
    _unit = food?.unit ?? FoodUnit.piece;
    _expiry = food?.expiry;
    _name = TextEditingController(text: food?.name ?? '');
    _amount = TextEditingController(
      text: food == null ? '' : food.unit.quantityText(food.total),
    );
    _price = TextEditingController(text: food?.price?.toString() ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _price.dispose();
    super.dispose();
  }

  void _chooseIngredient(FoodSuggestion suggestion) {
    setState(() {
      _selection = suggestion;
      _name.text = suggestion.name;
      _unit = suggestion.inputUnit;
      _amount.text = _unit.quantityText(suggestion.amount);
      // Every registration is a new purchase. Neither catalogue nor history
      // provides a reliable expiry date or actual paid price for this purchase.
      _expiry = null;
      _price.clear();
      _error = null;
    });
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    if (_expiry == null) {
      setState(() => _error = '소비기한을 선택해주세요.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final total = _unit.parseQuantity(_amount.text);
      final food = Food(
        id: _id,
        name: _name.text,
        unit: _unit,
        total: total,
        remaining: widget.hasRecords ? widget.food!.remaining : total,
        expiry: _expiry!,
        price: parsePrice(_price.text),
        created: widget.food?.created ?? widget.clock(),
      );
      await widget.repository.save(food);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = errorText(e);
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: Text(widget.food == null ? '식재료 등록' : '식재료 수정')),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            key: const ValueKey('food-editor'),
            padding: const EdgeInsets.all(Space.xl),
            children: [
              if (_busy) const LinearProgressIndicator(),
              if (widget.food == null &&
                  _error == null &&
                  !_searching &&
                  _selection == null) ...[
                Text(
                  '냉장고에 보관 중인 식재료를 등록해보세요.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: Space.xl),
              ],
              if (widget.food == null)
                IngredientAutocomplete(
                  key: const ValueKey('ingredient-autocomplete'),
                  controller: _name,
                  enabled: !_busy,
                  loadHistory: widget.repository.recentFoods,
                  onSelected: _chooseIngredient,
                  onNameChanged: () => setState(() => _selection = null),
                  onActiveChanged: (active) =>
                      setState(() => _searching = active),
                )
              else
                TextFormField(
                  key: const ValueKey('food-name'),
                  controller: _name,
                  enabled: !_busy,
                  decoration: const InputDecoration(labelText: '식재료 이름'),
                  validator: (v) =>
                      v == null || v.trim().isEmpty || v.trim().length > 60
                      ? '식재료 이름은 1~60자로 입력해주세요.'
                      : null,
                ),
              if (_selection != null && !_searching && _error == null)
                Padding(
                  padding: const EdgeInsets.only(top: Space.md),
                  child: Row(
                    children: [
                      FoodIllustration(
                        key: const ValueKey('selected-food-image'),
                        visual: _selection!.visual,
                      ),
                      const SizedBox(width: Space.md),
                      Expanded(
                        child: Text(
                          '대표 이미지 · 소비기한과 구매금액을 확인해주세요.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: Space.xl),
              TextFormField(
                key: const ValueKey('food-quantity'),
                controller: _amount,
                enabled: !_busy && !widget.hasRecords,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: '등록 수량',
                  helperText: '소수점 셋째 자리까지 입력할 수 있어요.',
                ),
                validator: (v) {
                  try {
                    _unit.parseQuantity(v ?? '');
                    return null;
                  } catch (e) {
                    return errorText(e);
                  }
                },
              ),
              const SizedBox(height: Space.sm),
              UnitSelector(
                units: FoodUnit.values,
                selected: _unit,
                enabled: !_busy && !widget.hasRecords,
                onSelect: (unit) => setState(() => _unit = unit),
              ),
              const SizedBox(height: Space.xl),
              DateButton(
                label: '소비기한',
                value: _expiry,
                enabled: !_busy,
                initial: widget.clock(),
                onSelect: (date) => setState(() => _expiry = date),
              ),
              const SizedBox(height: Space.xl),
              TextFormField(
                key: const ValueKey('food-price'),
                controller: _price,
                enabled: !_busy && !widget.hasRecords,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '전체 구매금액',
                  suffixText: '원',
                  hintText: '선택 입력',
                  helperText: '비워두면 금액 미입력으로 저장합니다.',
                ),
                validator: (v) {
                  try {
                    parsePrice(v ?? '');
                    return null;
                  } catch (e) {
                    return errorText(e);
                  }
                },
              ),
              if (widget.hasRecords)
                const Padding(
                  padding: EdgeInsets.only(top: Space.lg),
                  child: Text(
                    '처리 기록이 있어 이름과 소비기한만 수정할 수 있어요. 추가 구매분은 새 식재료로 등록해주세요.',
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: Space.lg),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: Space.xxl),
              FilledButton(
                onPressed: _busy ? null : _save,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: Text(widget.food == null ? '등록하기' : '수정 저장'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class ProcessDialog extends StatefulWidget {
  const ProcessDialog({
    super.key,
    required this.repository,
    required this.food,
    required this.kind,
    required this.clock,
    this.onSaved,
  });
  final ValueChanged<String>? onSaved;
  final InventoryRepository repository;
  final Food food;
  final ActionKind kind;
  final Clock clock;
  @override
  State<ProcessDialog> createState() => _ProcessDialogState();
}

class _ProcessDialogState extends State<ProcessDialog> {
  final _amount = TextEditingController();
  final _request = const Uuid().v4();
  late FoodUnit _unit;
  late DateTime _date;
  bool _busy = false, _manual = false;
  int? _denominator, _presetAmount;
  WasteReason? _wasteReason;
  String? _error;

  @override
  void initState() {
    super.initState();
    _unit = widget.food.unit;
    _date = civilDate(widget.clock());
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  int? get _selectedAmount {
    if (!_manual) return _presetAmount;
    try {
      return _unit.parseQuantity(_amount.text);
    } catch (_) {
      return null;
    }
  }

  String? get _manualError {
    if (!_manual || _amount.text.trim().isEmpty) return null;
    try {
      final amount = _unit.parseQuantity(_amount.text);
      require(amount <= widget.food.remaining, '남은 재고 이하로 입력해주세요.');
      return null;
    } catch (e) {
      return errorText(e);
    }
  }

  void _selectPortion(int denominator) {
    FocusScope.of(context).unfocus();
    try {
      final amount = portionAmount(widget.food.remaining, denominator);
      setState(() {
        _manual = false;
        _denominator = denominator;
        _presetAmount = amount;
        _unit = widget.food.unit.compatible.first;
        _amount.text = _unit.quantityText(amount);
        _error = null;
      });
    } catch (e) {
      setState(() {
        _denominator = null;
        _presetAmount = null;
        _error = errorText(e);
      });
    }
  }

  void _enterManually() {
    setState(() {
      _manual = true;
      _denominator = null;
      _error = null;
    });
  }

  Processing? get _preview {
    final amount = _selectedAmount;
    if (amount == null) return null;
    try {
      return processFood(
        widget.food,
        widget.kind,
        amount,
        _unit,
        _date,
        _request,
        today: widget.clock(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    try {
      final amount = _selectedAmount;
      require(amount != null, '처리 수량을 선택해주세요.');
      processFood(
        widget.food,
        widget.kind,
        amount!,
        _unit,
        _date,
        _request,
        today: widget.clock(),
      );
      FocusScope.of(context).unfocus();
      setState(() {
        _busy = true;
        _error = null;
      });
      await widget.repository.process(
        foodId: widget.food.id,
        kind: widget.kind,
        amount: amount,
        unit: _unit,
        date: _date,
        requestId: _request,
        today: widget.clock(),
        wasteReason: _wasteReason,
      );
      if (mounted) {
        widget.onSaved?.call(_request);
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = errorText(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text('${widget.kind.label} 기록'),
        insetPadding: const EdgeInsets.symmetric(
          horizontal: Space.lg,
          vertical: Space.xl,
        ),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_busy) const LinearProgressIndicator(),
                Text(
                  widget.food.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: Space.xs),
                Text(
                  '남은 재고 ${quantity(widget.food)}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: Space.xl),
                Text(
                  '얼마나 ${widget.kind == ActionKind.eat ? '먹었나요?' : '버렸나요?'}',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: Space.sm),
                Wrap(
                  spacing: Space.sm,
                  runSpacing: Space.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final denominator in [1, 2, 3, 4])
                      ChoiceChip(
                        key: ValueKey('portion-$denominator'),
                        label: Text(switch (denominator) {
                          1 => '전부',
                          2 => '절반',
                          _ => '1/$denominator',
                        }),
                        selected: !_manual && _denominator == denominator,
                        showCheckmark: false,
                        onSelected: _busy
                            ? null
                            : (_) => _selectPortion(denominator),
                      ),
                    OutlinedButton(
                      key: const ValueKey('manual-amount'),
                      onPressed: _busy ? null : _enterManually,
                      style: OutlinedButton.styleFrom(
                        backgroundColor: _manual
                            ? Theme.of(context).colorScheme.primaryContainer
                            : null,
                      ),
                      child: const Text('직접 입력'),
                    ),
                  ],
                ),
                const SizedBox(height: Space.sm),
                Text('남은 수량 기준', style: Theme.of(context).textTheme.bodySmall),
                if (_manual) ...[
                  const SizedBox(height: Space.lg),
                  TextField(
                    key: const ValueKey('process-quantity'),
                    controller: _amount,
                    enabled: !_busy,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: '${widget.kind.label} 수량',
                      errorText: _manualError,
                    ),
                    onChanged: (_) => setState(() => _error = null),
                  ),
                  const SizedBox(height: Space.sm),
                  UnitSelector(
                    units: widget.food.unit.compatible,
                    selected: _unit,
                    enabled: !_busy,
                    onSelect: (unit) => setState(() => _unit = unit),
                  ),
                ],
                if (preview != null) ...[
                  const SizedBox(height: Space.lg),
                  Text(
                    '처리 수량 ${_unit.quantityText(preview.record.amount)} ${_unit.label}',
                    key: const ValueKey('selected-quantity'),
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: Space.xs),
                  Text(
                    '처리 금액 ${money(preview.record.cost)}',
                    style: Theme.of(context).textTheme.bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: Space.xs),
                  Text(
                    '처리 후 ${quantity(preview.food)}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
                const SizedBox(height: Space.lg),
                if (widget.kind == ActionKind.waste) ...[
                  Text(
                    '폐기 이유 (선택)',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: Space.sm),
                  Wrap(
                    spacing: Space.sm,
                    runSpacing: Space.xs,
                    children: [
                      ChoiceChip(
                        label: const Text('선택 안 함'),
                        selected: _wasteReason == null,
                        onSelected: _busy
                            ? null
                            : (_) => setState(() => _wasteReason = null),
                      ),
                      for (final reason in WasteReason.values)
                        ChoiceChip(
                          key: ValueKey('waste-reason-${reason.name}'),
                          label: Text(reason.label),
                          selected: _wasteReason == reason,
                          showCheckmark: false,
                          onSelected: _busy
                              ? null
                              : (_) => setState(() => _wasteReason = reason),
                        ),
                    ],
                  ),
                  const SizedBox(height: Space.lg),
                ],
                DateButton(
                  label: '처리 날짜',
                  value: _date,
                  enabled: !_busy,
                  initial: widget.clock(),
                  last: widget.clock(),
                  onSelect: (date) => setState(() => _date = date),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.md),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: _busy || preview == null ? null : _save,
            style: widget.kind == ActionKind.eat
                ? FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.secondary,
                    foregroundColor: Theme.of(context).colorScheme.onSecondary,
                  )
                : null,
            child: Text('${widget.kind.label} 저장'),
          ),
        ],
      ),
    );
  }
}

class WeekView extends StatelessWidget {
  const WeekView({super.key, required this.week});
  final WeekSummary week;
  @override
  Widget build(BuildContext context) => ListView(
    key: const ValueKey('weekly-page'),
    padding: const EdgeInsets.all(Space.xl),
    children: [
      Text(
        '${dateText(week.start)} ~ ${dateText(week.end)}',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      const SizedBox(height: Space.xxl),
      Text(
        week.unknownCount > 0 ? '금액을 입력한 기록의 합계' : '폐기 금액 합계',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      const SizedBox(height: Space.sm),
      Text(
        week.records.isNotEmpty && week.unknownCount == week.records.length
            ? '금액 미입력'
            : money(week.knownTotal),
        key: const ValueKey('weekly-total'),
        style: Theme.of(context).textTheme.displaySmall,
      ),
      const SizedBox(height: Space.md),
      Text(
        '폐기 ${week.records.length}건${week.unknownCount > 0 ? ' · 금액 미입력 ${week.unknownCount}건' : ''}',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      const SizedBox(height: Space.xxl),
      const Divider(height: 1),
      const SizedBox(height: Space.xl),
      WasteInsightsView(week: week),
      const SizedBox(height: Space.xl),
      Text('폐기 내역', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: Space.md),
      if (week.records.isEmpty)
        Text('이번 주 폐기 기록이 없어요.', style: Theme.of(context).textTheme.bodyMedium),
      for (final record in week.records) RecordRow(record: record),
    ],
  );
}

class DateButton extends StatelessWidget {
  const DateButton({
    super.key,
    required this.label,
    required this.value,
    required this.enabled,
    required this.initial,
    required this.onSelect,
    this.last,
  });
  final String label;
  final DateTime? value, last;
  final DateTime initial;
  final bool enabled;
  final ValueChanged<DateTime> onSelect;
  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: !enabled
        ? null
        : () async {
            FocusScope.of(context).unfocus();
            final date = value ?? initial;
            final selected = await showDatePicker(
              context: context,
              initialDate: DateTime(date.year, date.month, date.day),
              firstDate: DateTime(1900),
              lastDate: last == null
                  ? DateTime(2100, 12, 31)
                  : DateTime(last!.year, last!.month, last!.day),
              helpText: '$label 선택',
              confirmText: '선택',
              cancelText: '취소',
            );
            if (selected != null && context.mounted) {
              onSelect(civilDate(selected));
            }
          },
    style: OutlinedButton.styleFrom(
      minimumSize: const Size.fromHeight(56),
      padding: const EdgeInsets.symmetric(horizontal: Space.lg),
    ),
    child: Row(
      children: [
        Expanded(child: Text(label, textAlign: TextAlign.start)),
        const SizedBox(width: Space.sm),
        Flexible(
          child: Text(
            value == null ? '날짜 선택' : dateText(value!),
            textAlign: TextAlign.end,
          ),
        ),
      ],
    ),
  );
}

class UnitSelector extends StatelessWidget {
  const UnitSelector({
    super.key,
    required this.units,
    required this.selected,
    required this.enabled,
    required this.onSelect,
  });
  final List<FoodUnit> units;
  final FoodUnit selected;
  final bool enabled;
  final ValueChanged<FoodUnit> onSelect;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: Space.sm,
    runSpacing: Space.xs,
    children: [
      for (final unit in units)
        ChoiceChip(
          label: Text(unit.label),
          selected: selected == unit,
          showCheckmark: false,
          onSelected: enabled ? (_) => onSelect(unit) : null,
        ),
    ],
  );
}

class IngredientRow extends StatelessWidget {
  const IngredientRow({
    super.key,
    required this.food,
    required this.today,
    required this.onTap,
    this.onEat,
    this.onWaste,
    this.onShopping,
  });
  final Food food;
  final DateTime today;
  final VoidCallback onTap;
  final VoidCallback? onEat, onWaste, onShopping;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      InkWell(
        key: ValueKey('food-${food.id}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(Corners.field),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, constraints) => Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        food.name,
                        style: Theme.of(context).textTheme.titleMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: Space.md),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: constraints.maxWidth * 0.4,
                      ),
                      child: Text(
                        quantity(food),
                        style: Theme.of(context).textTheme.bodyMedium,
                        textAlign: TextAlign.end,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Space.sm),
              ExpiryLine(food: food, today: today),
            ],
          ),
        ),
      ),
      if (food.remaining > 0 && (onEat != null || onWaste != null))
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: Space.sm,
            children: [
              TextButton.icon(
                key: ValueKey('quick-eat-${food.id}'),
                onPressed: onEat,
                icon: const Icon(Icons.restaurant_outlined),
                label: const Text('먹음'),
              ),
              TextButton.icon(
                key: ValueKey('quick-waste-${food.id}'),
                onPressed: onWaste,
                icon: const Icon(Icons.delete_outline),
                label: const Text('폐기'),
              ),
            ],
          ),
        ),
      if (food.remaining == 0 && onShopping != null)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: ValueKey('shopping-add-${food.id}'),
            onPressed: onShopping,
            icon: const Icon(Icons.add_shopping_cart),
            label: const Text('장보기 추가'),
          ),
        ),
      const Divider(height: 1),
    ],
  );
}

class ExpiryLine extends StatelessWidget {
  const ExpiryLine({super.key, required this.food, required this.today});
  final Food food;
  final DateTime today;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: Space.md,
    runSpacing: Space.xs,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Text(
        '소비기한 ${dateText(food.expiry)}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      DeadlineText(food: food, today: today),
    ],
  );
}

class DeadlineText extends StatelessWidget {
  const DeadlineText({super.key, required this.food, required this.today});
  final Food food;
  final DateTime today;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final urgent =
        food.remaining > 0 &&
        !food.expiry.isAfter(civilDate(today).add(const Duration(days: 3)));
    return Text(
      deadline(food, today),
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: food.remaining == 0
            ? colors.onSurfaceVariant
            : urgent
            ? colors.error
            : colors.primary,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class InfoRow extends StatelessWidget {
  const InfoRow({
    super.key,
    required this.label,
    required this.value,
    this.emphasis = false,
  });
  final String label, value;
  final bool emphasis;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Space.sm),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        const SizedBox(width: Space.md),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: emphasis
                ? Theme.of(context).textTheme.titleMedium
                : Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      ],
    ),
  );
}

class RecordRow extends StatelessWidget {
  const RecordRow({super.key, required this.record, this.showFoodName = true});
  final FoodRecord record;
  final bool showFoodName;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Space.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) => Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  showFoodName ? record.foodName : record.kind.label,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(width: Space.md),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: constraints.maxWidth * 0.4,
                ),
                child: Text(
                  money(record.cost),
                  textAlign: TextAlign.end,
                  style: Theme.of(context).textTheme.bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.sm),
        Text(
          '${dateText(record.date)} · ${record.unit.quantityText(record.amount)} ${record.unit.label}'
          '${record.wasteReason == null ? '' : ' · ${record.wasteReason!.label}'}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: Space.lg),
        const Divider(height: 1),
      ],
    ),
  );
}

class ErrorPanel extends StatelessWidget {
  const ErrorPanel({super.key, required this.onRetry});
  final Future<void> Function() onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(Space.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '기록을 불러오지 못했어요.',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: Space.md),
          const Text('저장된 데이터를 유지하고 다시 불러옵니다.'),
          const SizedBox(height: Space.xl),
          FilledButton(onPressed: onRetry, child: const Text('다시 시도')),
        ],
      ),
    ),
  );
}
