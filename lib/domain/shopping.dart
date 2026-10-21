import 'inventory.dart';

String normalizedShoppingName(String name) =>
    name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

class ShoppingItem {
  ShoppingItem({
    required this.id,
    required String name,
    required this.unit,
    required this.amount,
    required DateTime created,
  }) : name = name.trim(),
       created = civilDate(created) {
    require(id.trim().isNotEmpty, '장보기 항목을 확인해주세요.');
    require(
      this.name.isNotEmpty && this.name.length <= 60,
      '식재료 이름은 1~60자로 입력해주세요.',
    );
    require(amount > 0 && amount <= maxQuantity, '수량을 확인해주세요.');
  }
  final String id, name;
  final FoodUnit unit;
  final int amount;
  final DateTime created;
  String get normalizedKey =>
      '${normalizedShoppingName(name)}|${unit.family}|$amount';
  Map<String, Object?> toRow() => {
    'id': id,
    'name': name,
    'unit': unit.code,
    'amount': amount,
    'created': dateText(created),
    'normalized_key': normalizedKey,
  };
  factory ShoppingItem.fromRow(Map<String, Object?> row) => ShoppingItem(
    id: row['id'] as String,
    name: row['name'] as String,
    unit: FoodUnit.fromCode(row['unit'] as String),
    amount: row['amount'] as int,
    created: DateTime.parse(row['created'] as String),
  );
}
