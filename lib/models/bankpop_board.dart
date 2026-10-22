import 'dart:convert';

import 'package:flutter/services.dart';

class BankpopSpace {
  final int index;
  final String name;
  final String type; // 'Property' | 'Special'
  final int? price;
  final List<int>? rent;
  final String? color;
  final int? houseCost;
  final int? hotelCost;
  final int? houses;
  final int? hotels;

  const BankpopSpace({
    required this.index,
    required this.name,
    required this.type,
    this.price,
    this.rent,
    this.color,
    this.houseCost,
    this.hotelCost,
    this.houses,
    this.hotels,
  });

  bool get isProperty => type == 'Property';

  factory BankpopSpace.fromMap(Map<String, dynamic> map) {
    return BankpopSpace(
      index: (map['index'] as num).toInt(),
      name: (map['name'] as String?) ?? '',
      type: (map['type'] as String?) ?? 'Special',
      price: (map['price'] as num?)?.toInt(),
      rent: (map['rent'] as List?)?.map((e) => (e as num).toInt()).toList(),
      color: map['color'] as String?,
      houseCost: (map['houseCost'] as num?)?.toInt(),
      hotelCost: (map['hotelCost'] as num?)?.toInt(),
      houses: (map['houses'] as num?)?.toInt(),
      hotels: (map['hotels'] as num?)?.toInt(),
    );
  }
}

class BankpopBoard {
  final List<BankpopSpace> spaces;
  final List<String> chanceOptions;
  final List<String> communityChest;

  const BankpopBoard({
    required this.spaces,
    required this.chanceOptions,
    required this.communityChest,
  });

  static Future<BankpopBoard> loadFromAsset(String path) async {
    final raw = await rootBundle.loadString(path);
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final spaces = (map['spaces'] as List)
        .map((e) => BankpopSpace.fromMap(e as Map<String, dynamic>))
        .toList();
    final cards = (map['cards'] as Map?)?.cast<String, dynamic>() ?? {};
    final chance =
        (cards['chanceOptions'] as List?)?.cast<String>() ?? const [];
    final chest =
        (cards['communityChest'] as List?)?.cast<String>() ?? const [];
    return BankpopBoard(
      spaces: spaces,
      chanceOptions: chance,
      communityChest: chest,
    );
  }

  /// Standard Bankpop visual color per group.
  static int colorForGroup(String? group) {
    switch (group) {
      case 'Brown':
        return 0xFF8D5524;
      case 'Light Blue':
        return 0xFF90CAF9;
      case 'Pink':
        return 0xFFF48FB1;
      case 'Orange':
        return 0xFFFFB74D;
      case 'Red':
        return 0xFFE57373;
      case 'Yellow':
        return 0xFFFFEB3B;
      case 'Green':
        return 0xFF4CAF50;
      case 'Dark Blue':
        return 0xFF1565C0;
      case 'Station':
        return 0xFF5D4037;
      case 'Utility':
        return 0xFF90A4AE;
      default:
        return 0xFFBDBDBD;
    }
  }
}
