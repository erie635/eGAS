// ============================================================
// FILE: pricing_service.dart - COMPLETE PRICING & DISCOUNT SYSTEM
// ============================================================

import 'package:cloud_firestore/cloud_firestore.dart';

// ============================================================
// PRICING SERVICE - Original logic preserved
// ============================================================

class PricingService {
  // ============================================================
  // PRICE CONSTANTS - All original prices preserved
  // ============================================================
  static double petrol = 185.0;
  static double diesel = 172.0;
  static double kerosene = 140.0;
  static double vpower = 205.0;
  
  // Additional fuel types for future expansion
  static double premiumPetrol = 195.0;
  static double biodiesel = 180.0;
  static double ethanol = 160.0;

  // Fuel type constants for consistency
  static const String fuelPetrol = 'petrol';
  static const String fuelDiesel = 'diesel';
  static const String fuelKerosene = 'kerosene';
  static const String fuelVpower = 'v-power';
  static const String fuelPremiumPetrol = 'premium-petrol';
  static const String fuelBiodiesel = 'biodiesel';
  static const String fuelEthanol = 'ethanol';

  // ============================================================
  // CORE CALCULATION - Your original logic preserved
  // ============================================================
  
  /// Calculates total price based on fuel [type] and [litres].
  /// Returns null if fuel type is unknown or invalid.
  static double? calculate(String type, double litres) {
    if (type.isEmpty) {
      print('❌ PricingService: Fuel type cannot be empty');
      return null;
    }
    
    if (litres <= 0) {
      print('❌ PricingService: Litres must be greater than 0');
      return null;
    }

    try {
      final fuelType = type.toLowerCase().trim();
      double? pricePerLiter;
      
      switch (fuelType) {
        case fuelPetrol:
          pricePerLiter = petrol;
          break;
        case fuelDiesel:
          pricePerLiter = diesel;
          break;
        case fuelKerosene:
          pricePerLiter = kerosene;
          break;
        case fuelVpower:
          pricePerLiter = vpower;
          break;
        case fuelPremiumPetrol:
          pricePerLiter = premiumPetrol;
          break;
        case fuelBiodiesel:
          pricePerLiter = biodiesel;
          break;
        case fuelEthanol:
          pricePerLiter = ethanol;
          break;
        default:
          print('⚠️ PricingService: Unknown fuel type: $type');
          return null;
      }

      final total = pricePerLiter * litres;
      return double.parse(total.toStringAsFixed(2));
      
    } catch (e) {
      print('❌ PricingService: Error calculating price: $e');
      return null;
    }
  }

  // ============================================================
  // ADDITIONAL PRICING HELPERS
  // ============================================================
  
  static double? getPricePerLiter(String type) {
    if (type.isEmpty) return null;

    try {
      final fuelType = type.toLowerCase().trim();
      switch (fuelType) {
        case fuelPetrol:
          return petrol;
        case fuelDiesel:
          return diesel;
        case fuelKerosene:
          return kerosene;
        case fuelVpower:
          return vpower;
        case fuelPremiumPetrol:
          return premiumPetrol;
        case fuelBiodiesel:
          return biodiesel;
        case fuelEthanol:
          return ethanol;
        default:
          return null;
      }
    } catch (e) {
      return null;
    }
  }

  static Map<String, double> getAllFuelPrices() {
    return {
      fuelPetrol: petrol,
      fuelDiesel: diesel,
      fuelKerosene: kerosene,
      fuelVpower: vpower,
      fuelPremiumPetrol: premiumPetrol,
      fuelBiodiesel: biodiesel,
      fuelEthanol: ethanol,
    };
  }

  static bool isValidFuelType(String type) {
    if (type.isEmpty) return false;
    
    try {
      final fuelType = type.toLowerCase().trim();
      return [
        fuelPetrol,
        fuelDiesel,
        fuelKerosene,
        fuelVpower,
        fuelPremiumPetrol,
        fuelBiodiesel,
        fuelEthanol,
      ].contains(fuelType);
    } catch (e) {
      return false;
    }
  }

  static String formatPrice(double price, {String currency = 'KES'}) {
    return '$currency ${price.toStringAsFixed(2)}';
  }

  static void updatePrice(String type, double newPrice) {
    if (type.isEmpty || newPrice <= 0) {
      print('❌ PricingService: Invalid price update request');
      return;
    }

    try {
      final fuelType = type.toLowerCase().trim();
      switch (fuelType) {
        case fuelPetrol:
          petrol = newPrice;
          break;
        case fuelDiesel:
          diesel = newPrice;
          break;
        case fuelKerosene:
          kerosene = newPrice;
          break;
        case fuelVpower:
          vpower = newPrice;
          break;
        case fuelPremiumPetrol:
          premiumPetrol = newPrice;
          break;
        case fuelBiodiesel:
          biodiesel = newPrice;
          break;
        case fuelEthanol:
          ethanol = newPrice;
          break;
        default:
          print('⚠️ PricingService: Unknown fuel type: $type');
          return;
      }
      
      print('✅ PricingService: $type price updated to: $newPrice');
      
    } catch (e) {
      print('❌ PricingService: Error updating price: $e');
    }
  }

  static Map<String, double> getPriceRange() {
    final prices = getAllFuelPrices().values.toList();
    if (prices.isEmpty) {
      return {'min': 0.0, 'max': 0.0};
    }
    
    return {
      'min': prices.reduce((a, b) => a < b ? a : b),
      'max': prices.reduce((a, b) => a > b ? a : b),
    };
  }
}

// ============================================================
// DISCOUNT SERVICE - Complete discount system
// ============================================================

class DiscountService {
  static final db = FirebaseFirestore.instance;
  
  // ============================================================
  // DISCOUNT RULES
  // ============================================================
  static const double baseDiscountPercent = 0.005; // 0.5% per extra order
  static const int baseOrdersThreshold = 3; // 3 orders to start discount
  static const int weeklyResetDay = 7; // Reset every 7 days
  static const double maxDiscountPercent = 20.0; // Maximum 20% discount
  
  // ============================================================
  // ✅ CALCULATE WEEKLY DISCOUNT FOR CUSTOMER
  // ============================================================
  static Future<double> calculateWeeklyDiscount(String userId) async {
    if (userId.isEmpty) {
      print('❌ DiscountService: userId cannot be empty');
      return 0.0;
    }
    
    try {
      // Get this week's orders
      final weekOrders = await getWeeklyOrders(userId);
      final orderCount = weekOrders.length;
      
      // Calculate discount
      double discount = 0.0;
      
      if (orderCount > baseOrdersThreshold) {
        final extraOrders = orderCount - baseOrdersThreshold;
        discount = extraOrders * baseDiscountPercent * 100;
        
        if (discount > maxDiscountPercent) {
          discount = maxDiscountPercent;
        }
      }
      
      discount = double.parse(discount.toStringAsFixed(2));
      
      print('📊 DiscountService: User $userId has $orderCount orders this week → ${discount}% discount');
      
      await updateCustomerDiscount(userId, discount);
      
      return discount;
      
    } catch (e) {
      print('❌ DiscountService: Error calculating discount: $e');
      return 0.0;
    }
  }

  // ============================================================
  // ✅ GET WEEKLY ORDERS FOR A CUSTOMER
  // ============================================================
  static Future<List<Map<String, dynamic>>> getWeeklyOrders(String userId) async {
    if (userId.isEmpty) {
      print('❌ DiscountService: userId cannot be empty');
      return [];
    }
    
    try {
      final now = DateTime.now();
      final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
      final startOfWeekTimestamp = Timestamp.fromDate(startOfWeek);
      
      final orders = await db.collection('orders')
          .where('userId', isEqualTo: userId)
          .where('status', whereIn: ['completed', 'delivered'])
          .where('createdAt', isGreaterThanOrEqualTo: startOfWeekTimestamp)
          .get();
      
      return orders.docs.map((doc) {
        return {
          'id': doc.id,
          ...doc.data() as Map<String, dynamic>,
        };
      }).toList();
      
    } catch (e) {
      print('❌ DiscountService: Error getting weekly orders: $e');
      return [];
    }
  }

  // ============================================================
  // ✅ UPDATE CUSTOMER DISCOUNT IN FIRESTORE
  // ============================================================
  static Future<void> updateCustomerDiscount(String userId, double discount) async {
    if (userId.isEmpty) return;
    
    try {
      await db.collection('customers').doc(userId).update({
        'discount': discount,
        'discountUpdatedAt': FieldValue.serverTimestamp(),
        'discountPercentage': discount,
        'lastDiscountCalculation': FieldValue.serverTimestamp(),
      });
      
      print('✅ DiscountService: Customer $userId discount updated to: ${discount}%');
      
    } catch (e) {
      print('❌ DiscountService: Error updating customer discount: $e');
    }
  }

  // ============================================================
  // ✅ APPLY DISCOUNT TO ORDER TOTAL
  // ============================================================
  static double applyDiscount(double originalPrice, double discountPercent) {
    if (discountPercent <= 0) return originalPrice;
    if (discountPercent > maxDiscountPercent) {
      discountPercent = maxDiscountPercent;
    }
    
    final discountAmount = originalPrice * (discountPercent / 100);
    final finalPrice = originalPrice - discountAmount;
    
    return double.parse(finalPrice.toStringAsFixed(2));
  }

  // ============================================================
  // ✅ GET CUSTOMER'S CURRENT DISCOUNT
  // ============================================================
  static Future<double> getCustomerDiscount(String userId) async {
    if (userId.isEmpty) {
      print('❌ DiscountService: userId cannot be empty');
      return 0.0;
    }
    
    try {
      final doc = await db.collection('customers').doc(userId).get();
      
      if (doc.exists) {
        final data = doc.data()!;
        final discount = data['discount'] ?? data['discountPercentage'] ?? 0.0;
        return double.parse(discount.toStringAsFixed(2));
      }
      
      return 0.0;
      
    } catch (e) {
      print('❌ DiscountService: Error getting customer discount: $e');
      return 0.0;
    }
  }

  // ============================================================
  // ✅ CHECK IF DISCOUNT IS STILL VALID
  // ============================================================
  static Future<bool> isDiscountValid(String userId) async {
    if (userId.isEmpty) return false;
    
    try {
      final doc = await db.collection('customers').doc(userId).get();
      
      if (!doc.exists) return false;
      
      final data = doc.data()!;
      final lastCalculation = data['lastDiscountCalculation'] as Timestamp?;
      
      if (lastCalculation == null) return false;
      
      final now = DateTime.now();
      final lastCalcDate = lastCalculation.toDate();
      final daysSince = now.difference(lastCalcDate).inDays;
      
      if (daysSince > 7) {
        print('🔄 DiscountService: Discount is stale, recalculating...');
        await calculateWeeklyDiscount(userId);
        return true;
      }
      
      return true;
      
    } catch (e) {
      print('❌ DiscountService: Error checking discount validity: $e');
      return false;
    }
  }

  // ============================================================
  // ✅ GET DISCOUNT DETAILS FOR UI DISPLAY
  // ============================================================
  static Future<Map<String, dynamic>> getDiscountDetails(String userId) async {
    if (userId.isEmpty) {
      return {
        'discount': 0.0,
        'ordersThisWeek': 0,
        'ordersNeeded': baseOrdersThreshold,
        'nextTierOrders': baseOrdersThreshold + 1,
        'message': 'Place ${baseOrdersThreshold} orders to start getting discounts',
      };
    }
    
    try {
      final weekOrders = await getWeeklyOrders(userId);
      final orderCount = weekOrders.length;
      final discount = await calculateWeeklyDiscount(userId);
      
      final ordersNeeded = baseOrdersThreshold;
      final nextTierOrders = orderCount < baseOrdersThreshold 
          ? baseOrdersThreshold - orderCount 
          : 0;
      
      String message;
      if (orderCount >= baseOrdersThreshold) {
        message = '🎉 You have $discount% discount on your next order!';
      } else {
        final ordersToGo = baseOrdersThreshold - orderCount;
        message = '📊 Place $ordersToGo more orders this week to get discounts!';
      }
      
      return {
        'discount': discount,
        'ordersThisWeek': orderCount,
        'ordersNeeded': ordersNeeded,
        'nextTierOrders': nextTierOrders,
        'message': message,
        'hasDiscount': orderCount >= baseOrdersThreshold,
        'maxDiscount': maxDiscountPercent,
        'baseDiscountPercent': baseDiscountPercent * 100,
      };
      
    } catch (e) {
      print('❌ DiscountService: Error getting discount details: $e');
      return {
        'discount': 0.0,
        'ordersThisWeek': 0,
        'ordersNeeded': baseOrdersThreshold,
        'nextTierOrders': baseOrdersThreshold,
        'message': 'Error loading discount details',
        'hasDiscount': false,
        'maxDiscount': maxDiscountPercent,
        'baseDiscountPercent': baseDiscountPercent * 100,
      };
    }
  }

  // ============================================================
  // ✅ GET DISCOUNT TIERS FOR UI DISPLAY
  // ============================================================
  static List<Map<String, dynamic>> getDiscountTiers() {
    return [
      {
        'orders': 3,
        'discount': (baseDiscountPercent * 1) * 100,
        'label': '3 orders → ${(baseDiscountPercent * 1 * 100).toStringAsFixed(1)}% off',
        'icon': '🟢',
      },
      {
        'orders': 4,
        'discount': (baseDiscountPercent * 2) * 100,
        'label': '4 orders → ${(baseDiscountPercent * 2 * 100).toStringAsFixed(1)}% off',
        'icon': '🟡',
      },
      {
        'orders': 5,
        'discount': (baseDiscountPercent * 3) * 100,
        'label': '5 orders → ${(baseDiscountPercent * 3 * 100).toStringAsFixed(1)}% off',
        'icon': '🟠',
      },
      {
        'orders': 6,
        'discount': (baseDiscountPercent * 4) * 100,
        'label': '6 orders → ${(baseDiscountPercent * 4 * 100).toStringAsFixed(1)}% off',
        'icon': '🔵',
      },
      {
        'orders': 7,
        'discount': (baseDiscountPercent * 5) * 100,
        'label': '7+ orders → ${(baseDiscountPercent * 5 * 100).toStringAsFixed(1)}% off',
        'icon': '💎',
      },
    ];
  }

  // ============================================================
  // ✅ UPDATE ALL CUSTOMERS' DISCOUNTS (Admin/Background Task)
  // ============================================================
  static Future<void> updateAllCustomersDiscounts() async {
    try {
      final customers = await db.collection('customers').get();
      
      print('🔄 Updating discounts for ${customers.docs.length} customers...');
      
      for (var doc in customers.docs) {
        final userId = doc.id;
        await calculateWeeklyDiscount(userId);
        await Future.delayed(const Duration(milliseconds: 100));
      }
      
      print('✅ DiscountService: All customers discounts updated');
      
    } catch (e) {
      print('❌ DiscountService: Error updating all customers: $e');
    }
  }

  // ============================================================
  // ✅ GET ORDER HISTORY FOR DISCOUNT CALCULATION
  // ============================================================
  static Future<List<Map<String, dynamic>>> getOrderHistoryForDiscount(
    String userId,
    {int limit = 30}
  ) async {
    if (userId.isEmpty) {
      return [];
    }
    
    try {
      final orders = await db.collection('orders')
          .where('userId', isEqualTo: userId)
          .where('status', isEqualTo: 'completed')
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();
      
      return orders.docs.map((doc) {
        return {
          'id': doc.id,
          ...doc.data() as Map<String, dynamic>,
        };
      }).toList();
      
    } catch (e) {
      print('❌ DiscountService: Error getting order history: $e');
      return [];
    }
  }

  // ============================================================
  // ✅ CALCULATE DISCOUNT BASED ON TOTAL SPENT - UPDATED VALUES
  // ============================================================
  static double calculateDiscountBySpent(double totalSpent) {
    if (totalSpent >= 50000) return 3.0;
    if (totalSpent >= 30000) return 1.8;
    if (totalSpent >= 20000) return 1.3;
    if (totalSpent >= 10000) return 1.0;
    return 0.0;
  }

  // ============================================================
  // ✅ GET SPENDING DISCOUNT TIERS FOR UI DISPLAY
  // ============================================================
  static List<Map<String, dynamic>> getSpendingDiscountTiers() {
    return [
      {
        'spent': 10000,
        'discount': 1.0,
        'label': 'KES 10,000+ → 1.0% off',
        'icon': '💫',
      },
      {
        'spent': 20000,
        'discount': 1.3,
        'label': 'KES 20,000+ → 1.3% off',
        'icon': '⭐',
      },
      {
        'spent': 30000,
        'discount': 1.8,
        'label': 'KES 30,000+ → 1.8% off',
        'icon': '🌟',
      },
      {
        'spent': 50000,
        'discount': 3.0,
        'label': 'KES 50,000+ → 3.0% off',
        'icon': '🏆',
      },
    ];
  }

  // ============================================================
  // ✅ COMBINE DISCOUNTS (Weekly + Spending)
  // ============================================================
  static Future<double> getCombinedDiscount(String userId) async {
    try {
      final weeklyDiscount = await calculateWeeklyDiscount(userId);
      
      final doc = await db.collection('customers').doc(userId).get();
      if (!doc.exists) return weeklyDiscount;
      
      final totalSpent = (doc.data()?['totalSpent'] ?? 0.0).toDouble();
      final spendingDiscount = calculateDiscountBySpent(totalSpent);
      
      double combined = weeklyDiscount + spendingDiscount;
      
      final finalDiscount = combined > maxDiscountPercent 
          ? maxDiscountPercent 
          : combined;
      
      final roundedDiscount = double.parse(finalDiscount.toStringAsFixed(2));
      
      print('📊 Combined Discount: Weekly: ${weeklyDiscount}% + Spending: ${spendingDiscount}% = ${roundedDiscount}%');
      
      await updateCustomerDiscount(userId, roundedDiscount);
      
      return roundedDiscount;
      
    } catch (e) {
      print('❌ DiscountService: Error calculating combined discount: $e');
      return 0.0;
    }
  }

  // ============================================================
  // ✅ GET COMPLETE DISCOUNT SUMMARY FOR UI
  // ============================================================
  static Future<Map<String, dynamic>> getDiscountSummary(String userId) async {
    if (userId.isEmpty) {
      return {
        'totalDiscount': 0.0,
        'weeklyDiscount': 0.0,
        'spendingDiscount': 0.0,
        'ordersThisWeek': 0,
        'totalSpent': 0.0,
        'message': 'No discounts available',
      };
    }
    
    try {
      final weeklyOrders = await getWeeklyOrders(userId);
      final orderCount = weeklyOrders.length;
      final weeklyDiscount = await calculateWeeklyDiscount(userId);
      
      final doc = await db.collection('customers').doc(userId).get();
      final totalSpent = (doc.data()?['totalSpent'] ?? 0.0).toDouble();
      final spendingDiscount = calculateDiscountBySpent(totalSpent);
      
      final totalDiscount = weeklyDiscount + spendingDiscount;
      final finalDiscount = totalDiscount > maxDiscountPercent 
          ? maxDiscountPercent 
          : totalDiscount;
      
      String message;
      if (finalDiscount > 0) {
        message = '🎉 You have ${finalDiscount.toStringAsFixed(1)}% total discount!';
        if (weeklyDiscount > 0 && spendingDiscount > 0) {
          message += ' (${weeklyDiscount.toStringAsFixed(1)}% weekly + ${spendingDiscount.toStringAsFixed(1)}% spending)';
        } else if (weeklyDiscount > 0) {
          message += ' (${weeklyDiscount.toStringAsFixed(1)}% from weekly orders)';
        } else if (spendingDiscount > 0) {
          message += ' (${spendingDiscount.toStringAsFixed(1)}% from lifetime spending)';
        }
      } else {
        final ordersNeeded = baseOrdersThreshold - orderCount;
        final spendingNeeded = totalSpent < 10000 ? 10000 - totalSpent : 0;
        
        if (ordersNeeded > 0 && spendingNeeded > 0) {
          message = '📊 Place $ordersNeeded more orders this week OR spend KES ${spendingNeeded.toStringAsFixed(0)} more to get discounts!';
        } else if (ordersNeeded > 0) {
          message = '📊 Place $ordersNeeded more orders this week to get discounts!';
        } else if (spendingNeeded > 0) {
          message = '💰 Spend KES ${spendingNeeded.toStringAsFixed(0)} more to get spending discounts!';
        } else {
          message = 'Place 3 orders this week or spend KES 10,000 to get discounts!';
        }
      }
      
      return {
        'totalDiscount': double.parse(finalDiscount.toStringAsFixed(2)),
        'weeklyDiscount': double.parse(weeklyDiscount.toStringAsFixed(2)),
        'spendingDiscount': double.parse(spendingDiscount.toStringAsFixed(2)),
        'ordersThisWeek': orderCount,
        'totalSpent': totalSpent,
        'message': message,
        'hasDiscount': finalDiscount > 0,
        'maxDiscount': maxDiscountPercent,
        'ordersNeeded': baseOrdersThreshold,
        'spendingNeeded': totalSpent < 10000 ? 10000 - totalSpent : 0,
      };
      
    } catch (e) {
      print('❌ DiscountService: Error getting discount summary: $e');
      return {
        'totalDiscount': 0.0,
        'weeklyDiscount': 0.0,
        'spendingDiscount': 0.0,
        'ordersThisWeek': 0,
        'totalSpent': 0.0,
        'message': 'Error loading discount details',
        'hasDiscount': false,
        'maxDiscount': maxDiscountPercent,
        'ordersNeeded': baseOrdersThreshold,
        'spendingNeeded': 0,
      };
    }
  }
}

// ============================================================
// ✅ DISCOUNT WIDGET HELPER
// ============================================================
class DiscountUIHelper {
  static String getDiscountMessage(int orderCount, double discount) {
    if (discount > 0) {
      return '🎉 You have $discount% discount on this order!';
    }
    
    final ordersNeeded = 3 - orderCount;
    if (ordersNeeded > 0) {
      return '📊 Place $ordersNeeded more orders this week to get discounts!';
    }
    
    return 'Place 3 orders to get discounts!';
  }
  
  static String getDiscountColor(double discount) {
    if (discount >= 10) return '#4CAF50';
    if (discount >= 5) return '#FF9800';
    if (discount > 0) return '#2196F3';
    return '#9E9E9E';
  }
  
  static String getSpendingDiscountMessage(double totalSpent) {
    if (totalSpent >= 50000) return '🏆 3.0% off - Loyalty Master!';
    if (totalSpent >= 30000) return '🌟 1.8% off - Elite Spender!';
    if (totalSpent >= 20000) return '⭐ 1.3% off - Valued Customer!';
    if (totalSpent >= 10000) return '💫 1.0% off - Regular Customer!';
    return '💰 Spend KES 10,000 to get 1.0% off';
  }
}

// ============================================================
// ✅ FUEL TYPE ENUM for type safety
// ============================================================
enum FuelType {
  petrol,
  diesel,
  kerosene,
  vpower,
  premiumPetrol,
  biodiesel,
  ethanol,
}

extension FuelTypeExtension on FuelType {
  String get displayName {
    switch (this) {
      case FuelType.petrol:
        return 'Petrol';
      case FuelType.diesel:
        return 'Diesel';
      case FuelType.kerosene:
        return 'Kerosene';
      case FuelType.vpower:
        return 'V-Power';
      case FuelType.premiumPetrol:
        return 'Premium Petrol';
      case FuelType.biodiesel:
        return 'Biodiesel';
      case FuelType.ethanol:
        return 'Ethanol';
    }
  }
  
  String get icon {
    switch (this) {
      case FuelType.petrol:
        return '⛽';
      case FuelType.diesel:
        return '🛢️';
      case FuelType.kerosene:
        return '🔥';
      case FuelType.vpower:
        return '⚡';
      case FuelType.premiumPetrol:
        return '🏎️';
      case FuelType.biodiesel:
        return '🌿';
      case FuelType.ethanol:
        return '🌽';
    }
  }
  
  double get price {
    switch (this) {
      case FuelType.petrol:
        return PricingService.petrol;
      case FuelType.diesel:
        return PricingService.diesel;
      case FuelType.kerosene:
        return PricingService.kerosene;
      case FuelType.vpower:
        return PricingService.vpower;
      case FuelType.premiumPetrol:
        return PricingService.premiumPetrol;
      case FuelType.biodiesel:
        return PricingService.biodiesel;
      case FuelType.ethanol:
        return PricingService.ethanol;
    }
  }
  
  double calculate(double litres) {
    return price * litres;
  }
}
