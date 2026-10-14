// Pure Dart business rules. SQL unit/action codes match Kotlin database version 1.
const maxQuantity = 1000000000000;
const maxPrice = 1000000000000;

enum FoodUnit {
  ml('ML', 'ml', 'volume', 1000),
  litre('L', 'L', 'volume', 1000000),
  gram('G', 'g', 'weight', 1000),
  kilogram('KG', 'kg', 'weight', 1000000),
  piece('PIECE', '개', 'count', 1000);

  const FoodUnit(this.code, this.label, this.family, this.factor);
  final String code, label, family;
  final int factor;
  List<FoodUnit> get compatible =>
      values.where((u) => u.family == family).toList();
  static FoodUnit fromCode(String code) =>
      values.firstWhere((u) => u.code == code);

  int parseQuantity(String input) {
    final text = input.trim();
    require(
      RegExp(r'^[0-9]+(?:\.[0-9]{1,3})?$').hasMatch(text),
      '수량은 소수점 셋째 자리까지 입력해주세요.',
    );
    final parts = text.split('.');
    final thousandths =
        BigInt.parse(parts[0]) * BigInt.from(1000) +
        BigInt.parse(parts.length == 2 ? parts[1].padRight(3, '0') : '0');
    final amount = thousandths * BigInt.from(factor) ~/ BigInt.from(1000);
    require(
      amount > BigInt.zero && amount <= BigInt.from(maxQuantity),
      '수량 범위를 확인해주세요.',
    );
    return amount.toInt();
  }

  String quantityText(int amount) {
    final whole = amount ~/ factor;
    final remainder = amount % factor;
    if (remainder == 0) return '$whole';
    final digits = factor == 1000 ? 3 : 6;
    return '$whole.${remainder.toString().padLeft(digits, '0').replaceFirst(RegExp(r'0+$'), '')}';
  }
}

enum ActionKind {
  eat('EAT', '먹음'),
  waste('WASTE', '폐기');

  const ActionKind(this.code, this.label);
  final String code, label;
  static ActionKind fromCode(String code) =>
      values.firstWhere((kind) => kind.code == code);
}

void require(bool valid, String message) {
  if (!valid) throw ArgumentError(message);
}

// A UTC midnight surrogate represents a civil date, not a timestamp.
// This keeps week boundaries and D-Day stable across daylight-saving changes.
DateTime civilDate(DateTime value) =>
    DateTime.utc(value.year, value.month, value.day);
String dateText(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

int? parsePrice(String input) {
  final text = input.trim();
  if (text.isEmpty) return null;
  require(RegExp(r'^[0-9]+$').hasMatch(text), '구매금액은 0 이상의 정수로 입력해주세요.');
  final value = BigInt.parse(text);
  require(value <= BigInt.from(maxPrice), '구매금액은 1조 원 이하로 입력해주세요.');
  return value.toInt();
}

class Food {
  Food({
    required this.id,
    required String name,
    required this.unit,
    required this.total,
    int? remaining,
    required DateTime expiry,
    required this.price,
    required DateTime created,
  }) : name = name.trim(),
       remaining = remaining ?? total,
       expiry = civilDate(expiry),
       created = civilDate(created) {
    require(
      this.name.isNotEmpty && this.name.length <= 60,
      '식재료 이름은 1~60자로 입력해주세요.',
    );
    require(
      total > 0 &&
          total <= maxQuantity &&
          this.remaining >= 0 &&
          this.remaining <= total,
      '수량을 확인해주세요.',
    );
    require(
      price == null || (price! >= 0 && price! <= maxPrice),
      '구매금액을 확인해주세요.',
    );
  }
  final String id, name;
  final FoodUnit unit;
  final int total, remaining;
  final DateTime expiry, created;
  final int? price;

  Food withRemaining(int amount) => Food(
    id: id,
    name: name,
    unit: unit,
    total: total,
    remaining: amount,
    expiry: expiry,
    price: price,
    created: created,
  );

  Map<String, Object?> toRow() => {
    'id': id,
    'name': name,
    'unit': unit.code,
    'total': total,
    'remaining': remaining,
    'expiry': dateText(expiry),
    'price': price,
    'created': dateText(created),
  };
  factory Food.fromRow(Map<String, Object?> row) => Food(
    id: row['id'] as String,
    name: row['name'] as String,
    unit: FoodUnit.fromCode(row['unit'] as String),
    total: row['total'] as int,
    remaining: row['remaining'] as int,
    expiry: DateTime.parse(row['expiry'] as String),
    price: row['price'] as int?,
    created: DateTime.parse(row['created'] as String),
  );
}

class FoodRecord {
  FoodRecord({
    required this.id,
    required this.foodId,
    required this.foodName,
    required this.kind,
    required this.amount,
    required this.unit,
    required DateTime date,
    required this.cost,
  }) : date = civilDate(date);
  final String id, foodId, foodName;
  final ActionKind kind;
  final int amount;
  final FoodUnit unit;
  final DateTime date;
  final int? cost;
  factory FoodRecord.fromRow(Map<String, Object?> row) => FoodRecord(
    id: row['id'] as String,
    foodId: row['food_id'] as String,
    foodName: row['food_name'] as String,
    kind: ActionKind.fromCode(row['kind'] as String),
    amount: row['amount'] as int,
    unit: FoodUnit.fromCode(row['unit'] as String),
    date: DateTime.parse(row['date'] as String),
    cost: row['cost'] as int?,
  );
  Map<String, Object?> toRow() => {
    'id': id,
    'food_id': foodId,
    'food_name': foodName,
    'kind': kind.code,
    'amount': amount,
    'unit': unit.code,
    'date': dateText(date),
    'cost': cost,
  };
}

class Processing {
  const Processing(this.food, this.record);
  final Food food;
  final FoodRecord record;
}

int _allocatedCost(int price, int amount, int total) {
  final product = BigInt.from(price) * BigInt.from(amount);
  final denominator = BigInt.from(total);
  // Exact HALF_UP rounding without doubles or overflowing a 64-bit product.
  return ((product * BigInt.two + denominator) ~/ (denominator * BigInt.two))
      .toInt();
}

Processing processFood(
  Food food,
  ActionKind kind,
  int amount,
  FoodUnit unit,
  DateTime date,
  String requestId, {
  required DateTime today,
}) {
  require(unit.family == food.unit.family, '등록한 식재료와 같은 종류의 단위를 선택해주세요.');
  require(amount > 0 && amount <= food.remaining, '처리 수량은 남은 재고 이하로 입력해주세요.');
  final day = civilDate(date);
  require(!day.isAfter(civilDate(today)), '처리 날짜는 오늘 또는 이전 날짜를 선택해주세요.');
  final processed = food.total - food.remaining;
  final cost = food.price == null
      ? null
      : _allocatedCost(food.price!, processed + amount, food.total) -
            _allocatedCost(food.price!, processed, food.total);
  return Processing(
    food.withRemaining(food.remaining - amount),
    FoodRecord(
      id: requestId,
      foodId: food.id,
      foodName: food.name,
      kind: kind,
      amount: amount,
      unit: unit,
      date: day,
      cost: cost,
    ),
  );
}

class WeekSummary {
  WeekSummary(this.start, this.end, Iterable<FoodRecord> records)
    : records = List.unmodifiable(records);
  final DateTime start, end;
  final List<FoodRecord> records;
  int get knownTotal =>
      records.fold(0, (sum, record) => sum + (record.cost ?? 0));
  int get unknownCount => records.where((r) => r.cost == null).length;
}

WeekSummary weeklyWaste(Iterable<FoodRecord> records, DateTime today) {
  final day = civilDate(today);
  final start = day.subtract(Duration(days: day.weekday - DateTime.monday));
  final filtered =
      records
          .where(
            (r) =>
                r.kind == ActionKind.waste &&
                !r.date.isBefore(start) &&
                !r.date.isAfter(day),
          )
          .toList()
        ..sort((a, b) {
          final byDate = b.date.compareTo(a.date);
          return byDate == 0 ? b.id.compareTo(a.id) : byDate;
        });
  return WeekSummary(start, start.add(const Duration(days: 6)), filtered);
}
