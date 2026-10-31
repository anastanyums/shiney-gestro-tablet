import 'package:flutter_test/flutter_test.dart';
import 'package:foodtro_staff/station_board.dart';
import 'package:foodtro_staff/waiter_demo.dart';

void main() {
  test('partially sold-out portions are discoverable without blocking the dish', () {
    final small = VariationOption('test-small', 'Small', 0, available: false);
    final large = VariationOption('test-large', 'Large', 500);
    final dish = Dish('Test curry', 'Mains', '', 1000)
      ..kitchenAvailabilityGroupId = 'test-portions'
      ..allVariations = [VariationGroup('test-portions', 'Portion', required: true, options: [small, large])];
    expect(hasSoldOutKitchenVariants(dish), isTrue);
    expect(demoRestaurant.isSoldOut(dish), isFalse);
    small.available = true;
    expect(hasSoldOutKitchenVariants(dish), isFalse);
    large.available = false;
    small.available = false;
    expect(demoRestaurant.isSoldOut(dish), isTrue);
    small.available = true;
    expect(demoRestaurant.isSoldOut(dish), isFalse);
    expect(hasSoldOutKitchenVariants(dish), isTrue);
  });
  test('preparation tickets preserve food and allergy notes', () {
    expect(
      kitchenPreparationNote('No onions\nAllergy: peanuts'),
      'No onions\nAllergy: peanuts',
    );
  });
  test(
    'commercial notes are omitted without losing preparation instructions',
    () {
      expect(
        kitchenPreparationNote('No onions · Loyalty reward · 20% off Pasta'),
        'No onions',
      );
    },
  );
}
