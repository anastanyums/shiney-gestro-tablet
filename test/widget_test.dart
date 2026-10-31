import 'package:flutter_test/flutter_test.dart';
import 'package:foodtro_staff/station_board.dart';

void main() {
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
