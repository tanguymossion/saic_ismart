import 'package:saic_ismart/saic_ismart.dart';
import 'package:test/test.dart';

void main() {
  group('saic_ismart', () {
    test('Vehicle can be instantiated', () {
      const vehicle = Vehicle(vin: 'LSJA24B19NB123456', modelName: 'MG ZS EV');
      expect(vehicle.vin, 'LSJA24B19NB123456');
      expect(vehicle.modelName, 'MG ZS EV');
    });
  });
}
