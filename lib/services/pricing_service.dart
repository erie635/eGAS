class PricingService {
  static double petrol = 185;
  static double diesel = 172;
  static double kerosene = 140;
  static double vpower = 205;

  static double calculate(String type, double litres) {
    switch (type.toLowerCase()) {
      case "diesel":
        return diesel * litres;
      case "kerosene":
        return kerosene * litres;
      case "v-power":
        return vpower * litres;
      default:
        return petrol * litres;
    }
  }
}
