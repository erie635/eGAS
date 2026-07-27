class FuelRequest {
  final String fuelType;
  final double litres;
  final double lat;
  final double lng;
  final String status;

  FuelRequest({
    required this.fuelType,
    required this.litres,
    required this.lat,
    required this.lng,
    this.status = "pending",
  });

  Map<String, dynamic> toMap() {
    return {
      "fuel_type": fuelType,
      "litres": litres,
      "lat": lat,
      "lng": lng,
      "status": status,
    };
  }
}