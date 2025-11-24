// Pricing Services - Advanced Algorithm
// This file contains all pricing calculation logic

import 'dart:convert';
import 'package:http/http.dart' as http;

/// Weather-based surge calculator
class WeatherService {
  final String apiKey;
  
  WeatherService(this.apiKey);
  
  Future<double> getWeatherSurge(double lat, double lng) async {
    if (apiKey == "YOUR_OPENWEATHER_API_KEY_HERE") {
      return 1.0; // No surge if API key not set
    }
    
    try {
      final url = Uri.parse(
        'https://api.openweathermap.org/data/2.5/weather'
        '?lat=$lat&lon=$lng&appid=$apiKey'
      );
      
      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        // Check for rain
        if (data['weather'] != null && data['weather'].isNotEmpty) {
          final weatherMain = data['weather'][0]['main'] as String;
          final weatherDesc = data['weather'][0]['description'] as String;
          
          // Heavy rain/storm = 1.8x surge
          if (weatherMain == 'Thunderstorm' || weatherDesc.contains('heavy')) {
            return 1.8;
          }
          // Light/moderate rain = 1.5x surge
          if (weatherMain == 'Rain' || weatherMain == 'Drizzle') {
            return 1.5;
          }
        }
        
        // Check for extreme heat
        if (data['main'] != null) {
          final tempKelvin = data['main']['temp'] as double;
          final tempCelsius = tempKelvin - 273.15;
          
          if (tempCelsius > 40) {
            return 1.1; // Hot weather surge
          }
        }
      }
    } catch (e) {
      print('Weather API error: $e');
    }
    
    return 1.0; // No weather surge
  }
}

/// Time-based surge calculator
class TimeSurgeCalculator {
  double calculateSurge(DateTime now) {
    final hour = now.hour;
    final dayOfWeek = now.weekday;
    
    // Morning rush: 7 AM - 10 AM
    if (hour >= 7 && hour < 10) {
      return 1.6; // 1.3x - 1.8x average
    }
    
    // Evening rush: 5 PM - 9 PM
    if (hour >= 17 && hour < 21) {
      return 1.8; // 1.5x - 2.0x average (peak)
    }
    
    // Late night: 11 PM - 5 AM
    if (hour >= 23 || hour < 5) {
      return 1.35; // 1.2x - 1.5x average
    }
    
    // Weekend bonus: Saturday (6) and Sunday (7)
    if (dayOfWeek >= 6) {
      return 1.2; // 1.1x - 1.3x average
    }
    
    return 1.0; // No time surge
  }
  
  bool isNightTime(DateTime now) {
    final hour = now.hour;
    return hour >= 22 || hour < 6; // 10 PM - 6 AM
  }
}

/// Traffic-based surge calculator
class TrafficSurgeCalculator {
  double calculateSurge(int durationSeconds, int durationInTrafficSeconds) {
    if (durationInTrafficSeconds == 0 || durationSeconds == 0) {
      return 1.0;
    }
    
    final ratio = durationInTrafficSeconds / durationSeconds;
    
    // Severe congestion: 2x longer than normal
    if (ratio >= 2.0) {
      return 1.5;
    }
    
    // Heavy traffic: 1.5x longer than normal
    if (ratio >= 1.5) {
      return 1.3;
    }
    
    // Moderate traffic: 1.2x longer than normal
    if (ratio >= 1.2) {
      return 1.1;
    }
    
    return 1.0; // No traffic surge
  }
}

/// City-specific pricing data
class CityPricingData {
  final String cityName;
  final Map<String, VehicleFare> fares;
  
  CityPricingData({
    required this.cityName,
    required this.fares,
  });
  
  static CityPricingData getBangalore() {
    return CityPricingData(
      cityName: 'Bangalore',
      fares: {
        'Auto': VehicleFare(
          baseFare: 25,
          perKm: 14,
          perMinute: 1,
          minimumFare: 40,
          nightChargeMultiplier: 1.5, // +50%
        ),
        'Bike': VehicleFare(
          baseFare: 15,
          perKm: 3,
          perMinute: 0,
          minimumFare: 20,
          nightChargeMultiplier: 1.0,
        ),
        'Cab': VehicleFare(
          baseFare: 100,
          perKm: 24,
          perMinute: 1,
          minimumFare: 100,
          nightChargeMultiplier: 1.1, // +10%
        ),
        'Any': VehicleFare(
          baseFare: 30,
          perKm: 12,
          perMinute: 1,
          minimumFare: 40,
          nightChargeMultiplier: 1.3,
        ),
      },
    );
  }
  
  static CityPricingData getMumbai() {
    return CityPricingData(
      cityName: 'Mumbai',
      fares: {
        'Auto': VehicleFare(
          baseFare: 25,
          perKm: 12,
          perMinute: 1,
          minimumFare: 35,
          nightChargeMultiplier: 1.5,
        ),
        'Bike': VehicleFare(
          baseFare: 18,
          perKm: 4,
          perMinute: 0,
          minimumFare: 25,
          nightChargeMultiplier: 1.0,
        ),
        'Cab': VehicleFare(
          baseFare: 90,
          perKm: 22,
          perMinute: 1,
          minimumFare: 90,
          nightChargeMultiplier: 1.1,
        ),
        'Any': VehicleFare(
          baseFare: 28,
          perKm: 11,
          perMinute: 1,
          minimumFare: 35,
          nightChargeMultiplier: 1.3,
        ),
      },
    );
  }
  
  static CityPricingData getDelhi() {
    return CityPricingData(
      cityName: 'Delhi',
      fares: {
        'Auto': VehicleFare(
          baseFare: 40,
          perKm: 15,
          perMinute: 1,
          minimumFare: 50,
          nightChargeMultiplier: 1.25, // +25%
        ),
        'Bike': VehicleFare(
          baseFare: 20,
          perKm: 5,
          perMinute: 0,
          minimumFare: 30,
          nightChargeMultiplier: 1.0,
        ),
        'Cab': VehicleFare(
          baseFare: 110,
          perKm: 26,
          perMinute: 1,
          minimumFare: 110,
          nightChargeMultiplier: 1.25,
        ),
        'Any': VehicleFare(
          baseFare: 35,
          perKm: 13,
          perMinute: 1,
          minimumFare: 45,
          nightChargeMultiplier: 1.25,
        ),
      },
    );
  }
  
  static CityPricingData getDefault() {
    return CityPricingData(
      cityName: 'India',
      fares: {
        'Auto': VehicleFare(
          baseFare: 30,
          perKm: 13,
          perMinute: 1,
          minimumFare: 40,
          nightChargeMultiplier: 1. 4,
        ),
        'Bike': VehicleFare(
          baseFare: 17,
          perKm: 4,
          perMinute: 0,
          minimumFare: 25,
          nightChargeMultiplier: 1.0,
        ),
        'Cab': VehicleFare(
          baseFare: 95,
          perKm: 23,
          perMinute: 1,
          minimumFare: 95,
          nightChargeMultiplier: 1.15,
        ),
        'Any': VehicleFare(
          baseFare: 30,
          perKm: 12,
          perMinute: 1,
          minimumFare: 40,
          nightChargeMultiplier: 1.3,
        ),
      },
    );
  }
  
  /// Detect city from location name
  static CityPricingData detectCity(String locationName) {
    final lowerName = locationName.toLowerCase();
    
    if (lowerName.contains('bangalore') || lowerName.contains('bengaluru')) {
      return getBangalore();
    }
    if (lowerName.contains('mumbai')) {
      return getMumbai();
    }
    if (lowerName.contains('delhi') || lowerName.contains('new delhi')) {
      return getDelhi();
    }
    
    return getDefault();
  }
}

/// Vehicle fare structure
class VehicleFare {
  final double baseFare;
  final double perKm;
  final double perMinute;
  final double minimumFare;
  final double nightChargeMultiplier;
  
  VehicleFare({
    required this.baseFare,
    required this.perKm,
    required this.perMinute,
    required this.minimumFare,
    required this.nightChargeMultiplier,
  });
}

/// Platform-specific pricing engine
class PlatformPricer {
  /// Calculate prices for all platforms
  Map<String, PriceEstimate> calculateAllPrices({
    required double distanceKm,
    required int durationMinutes,
    required String vehicleType,
    required double surgeFactor, // Maximum of all surges
    required bool isNight,
    required CityPricingData cityData,
  }) {
    final fare = cityData.fares[vehicleType]!;
    
    // Base calculation
    double basePrice = fare.baseFare +
        (distanceKm * fare.perKm) +
        (durationMinutes * fare.perMinute);
    
    // Apply night charge if applicable
    if (isNight) {
      basePrice *= fare.nightChargeMultiplier;
    }
    
    // Apply surge
    basePrice *= surgeFactor;
    
    // Ensure minimum fare
    basePrice = basePrice < fare.minimumFare ? fare.minimumFare : basePrice;
    
    // Platform-specific multipliers and calculations
    return {
      'Uber': PriceEstimate(
        platform: 'Uber',
        price: (basePrice * 1.10).round(), // Uber 10% higher
        surgeFactor: surgeFactor,
        isNight: isNight,
      ),
      'Ola': PriceEstimate(
        platform: 'Ola',
        price: (basePrice * 1.05).round(), // Ola 5% higher
        surgeFactor: surgeFactor,
        isNight: isNight,
      ),
      'Rapido': PriceEstimate(
        platform: 'Rapido',
        price: vehicleType == 'Bike' 
            ? (basePrice * 0.75).round() // Rapido bikes much cheaper
            : (basePrice * 0.90).round(), // Other vehicles 10% cheaper
        surgeFactor: surgeFactor,
        isNight: isNight,
      ),
      'Namma Yatri': PriceEstimate(
        platform: 'Namma Yatri',
        price: 0, // Metered/driver quote
        surgeFactor: 1.0,
        isNight: isNight,
        note: 'Metered / Driver decides',
      ),
    };
  }
}

/// Price estimate result
class PriceEstimate {
  final String platform;
  final int price;
  final double surgeFactor;
  final bool isNight;
  final String? note;
  
  PriceEstimate({
    required this.platform,
    required this.price,
    required this.surgeFactor,
    required this.isNight,
    this.note,
  });
  
  bool get hasSurge => surgeFactor > 1.15; // 15%+ is notable surge
}
