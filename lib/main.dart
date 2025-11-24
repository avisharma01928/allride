import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'services/pricing_service.dart';

void main() {
  runApp(const AllBookingApp());
}

class AllBookingApp extends StatelessWidget {
  const AllBookingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AllBooking',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF5F5F5),
      ),
      home: const BookingHomePage(),
    );
  }
}

class BookingHomePage extends StatefulWidget {
  const BookingHomePage({super.key});

  @override
  State<BookingHomePage> createState() => _BookingHomePageState();
}

class _BookingHomePageState extends State<BookingHomePage> {
  // Controllers for text inputs
  final TextEditingController _pickupController = TextEditingController();
  final TextEditingController _dropController = TextEditingController();
  
  // Location Data
  Position? _currentPosition;
  String _pickupAddress = "Fetching location...";
  double? _pickupLat;
  double? _pickupLng;
  double? _dropLat;
  double? _dropLng;
  
  // Selected Vehicle Type
  String _selectedVehicle = 'Auto';
  
  // Loading State
  bool _isLoading = false;
  bool _showSuggestions = false;
  
  // Autocomplete Suggestions
  List<PlaceSuggestion> _suggestions = [];
  Timer? _debounce;
  
  // API Keys - IMPORTANT: Replace with your actual API keys
  // Google API Key - Get from: https://console.cloud.google.com/
  final String _googleApiKey = "YOUR_GOOGLE_API_KEY_HERE";
  // OpenWeatherMap API Key - Get from: https://openweathermap.org/api
  final String _openWeatherApiKey = "YOUR_OPENWEATHER_API_KEY_HERE";
  
  // Pricing services
  late WeatherService _weatherService;
  final TimeSurgeCalculator _timeSurge = TimeSurgeCalculator();
  final TrafficSurgeCalculator _trafficSurge = TrafficSurgeCalculator();
  final PlatformPricer _platformPricer = PlatformPricer();
  
  // City pricing data
  CityPricingData? _cityData;
  
  // Estimates with advanced data
  Map<String, dynamic> _estimates = {
    'Uber': {
      'price': 0,
      'eta': 0,
      'surge': 1.0,
      'color': Colors.black,
    },
    'Ola': {
      'price': 0,
      'eta': 0,
      'surge': 1.0,
      'color': const Color(0xFFCDDC39),
    },
    'Rapido': {
      'price': 0,
      'eta': 0,
      'surge': 1.0,
      'color': const Color(0xFFFFC107),
    },
    'Namma Yatri': {
      'price': 0,
      'eta': 0,
      'surge': 1.0,
      'color': const Color(0xFFF44336),
    },
  };

  @override
  void initState() {
    super.initState();
    _weatherService = WeatherService(_openWeatherApiKey);
    _getCurrentLocation();
    _dropController.addListener(_onSearchChanged);
  }

  // Handle search text changes with debouncing
  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (_dropController.text.isNotEmpty) {
        _searchPlaces(_dropController.text);
      } else {
        setState(() {
          _suggestions = [];
          _showSuggestions = false;
        });
      }
    });
  }

  // Search places using Google Places API
  Future<void> _searchPlaces(String query) async {
    if (query.isEmpty || _googleApiKey == "YOUR_GOOGLE_API_KEY_HERE") {
      return;
    }

    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/autocomplete/json'
        '?input=${Uri.encodeComponent(query)}'
        '&components=country:in'
        '&key=$_googleApiKey'
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['status'] == 'OK') {
          final predictions = data['predictions'] as List;
          setState(() {
            _suggestions = predictions.map((p) => PlaceSuggestion(
              placeId: p['place_id'],
              description: p['description'],
              mainText: p['structured_formatting']['main_text'],
              secondaryText: p['structured_formatting']['secondary_text'],
            )).toList();
            _showSuggestions = true;
          });
        }
      }
    } catch (e) {
      debugPrint("Error searching places: $e");
    }
  }

  // Get place details from place ID
  Future<void> _getPlaceDetails(String placeId, String description) async {
    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/details/json'
        '?place_id=$placeId'
        '&fields=geometry'
        '&key=$_googleApiKey'
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['status'] == 'OK') {
          final location = data['result']['geometry']['location'];
          setState(() {
            _dropLat = location['lat'];
            _dropLng = location['lng'];
            _dropController.text = description;
            _showSuggestions = false;
            
            // Detect city from location
            _cityData = CityPricingData.detectCity(description);
          });

          // Calculate estimates with advanced pricing
          _calculateAdvancedEstimates();
        }
      }
    } catch (e) {
      debugPrint("Error getting place details: $e");
    }
  }

  // Get current GPS location
  Future<void> _getCurrentLocation() async {
    try {
      // Check permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _pickupAddress = "Location permission denied";
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _pickupAddress = "Location permissions are permanently denied";
        });
        return;
      }

      // Get current position
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        _currentPosition = position;
        _pickupLat = position.latitude;
        _pickupLng = position.longitude;
      });

      // Get address from coordinates
      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        setState(() {
          _pickupAddress = "${place.name}, ${place.locality}";
          _pickupController.text = _pickupAddress;
          
          // Detect city from pickup location
          _cityData = CityPricingData.detectCity("${place.locality}");
        });
      }
    } catch (e) {
      debugPrint("Error getting location: $e");
      setState(() {
        _pickupAddress = "Error getting location";
      });
    }
  }

  // ADVANCED PRICING CALCULATION
  Future<void> _calculateAdvancedEstimates() async {
    if (_pickupLat == null || _pickupLng == null || 
        _dropLat == null || _dropLng == null ||
        _googleApiKey == "YOUR_GOOGLE_API_KEY_HERE") {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final now = DateTime.now();
      
      // Use default city data if not detected
      final cityData = _cityData ?? CityPricingData.getDefault();
      
      // 1. Get distance and duration with TRAFFIC data
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/distancematrix/json'
        '?origins=$_pickupLat,$_pickupLng'
        '&destinations=$_dropLat,$_dropLng'
        '&mode=driving'
        '&departure_time=now' // Real-time traffic
        '&traffic_model=best_guess'
        '&key=$_googleApiKey'
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['status'] == 'OK' && data['rows'].isNotEmpty) {
          final element = data['rows'][0]['elements'][0];

          if (element['status'] == 'OK') {
            final distanceInMeters = element['distance']['value'];
            final durationInSeconds = element['duration']['value'];
            
            // Check for traffic-adjusted duration
            final durationInTrafficSeconds = element['duration_in_traffic'] != null
                ? element['duration_in_traffic']['value']
                : durationInSeconds;

            final distanceKm = distanceInMeters / 1000.0;
            final durationMinutes = (durationInSeconds / 60).round();
            final etaInMinutes = (durationInTrafficSeconds / 60).round();

            // 2. Calculate surge factors
            final timeSurgeFactor = _timeSurge.calculateSurge(now);
            final trafficSurgeFactor = _trafficSurge.calculateSurge(
              durationInSeconds,
              durationInTrafficSeconds,
            );
            
            // 3. Get weather surge
            double weatherSurgeFactor = 1.0;
            try {
              weatherSurgeFactor = await _weatherService.getWeatherSurge(
                _pickupLat!,
                _pickupLng!,
              );
            } catch (e) {
              debugPrint("Weather surge error: $e");
            }

            // 4. Combine surge factors (take maximum, not additive)
            final combinedSurge = [
              timeSurgeFactor,
              trafficSurgeFactor,
              weatherSurgeFactor,
            ].reduce((a, b) => a > b ? a : b);
            
            // Clamp surge to regulatory limits (0.5x - 2.0x)
            final finalSurge = combinedSurge.clamp(0.5, 2.0);

            // 5. Check if night time
            final isNight = _timeSurge.isNightTime(now);

            // 6. Calculate platform-specific prices
            final priceEstimates = _platformPricer.calculateAllPrices(
              distanceKm: distanceKm,
              durationMinutes: durationMinutes,
              vehicleType: _selectedVehicle,
              surgeFactor: finalSurge,
              isNight: isNight,
              cityData: cityData,
            );

            // 7. Update UI
            setState(() {
              _estimates = {
                'Uber': {
                  'price': priceEstimates['Uber']!.price,
                  'eta': etaInMinutes + 4, // Uber wait time
                  'surge': finalSurge,
                  'color': Colors.black,
                },
                'Ola': {
                  'price': priceEstimates['Ola']!.price,
                  'eta': etaInMinutes + 6, // Ola wait time
                  'surge': finalSurge,
                  'color': const Color(0xFFCDDC39),
                },
                'Rapido': {
                  'price': priceEstimates['Rapido']!.price,
                  'eta': etaInMinutes + 5, // Rapido wait time
                  'surge': finalSurge,
                  'color': const Color(0xFFFFC107),
                },
                'Namma Yatri': {
                  'price': priceEstimates['Namma Yatri']!.price,
                  'eta': etaInMinutes + 8,
                  'surge': 1.0, // No surge for Namma Yatri
                  'color': const Color(0xFFF44336),
                },
              };
            });

            // Show surge notification if significant
            if (finalSurge >= 1.5 && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    "⚡ ${((finalSurge - 1) * 100).round()}% surge pricing active "
                    "${weatherSurgeFactor > 1.2 ? '(Weather)' : ''}"
                    "${timeSurgeFactor > 1.2 ? '(Peak Hour)' : ''}"
                    "${trafficSurgeFactor > 1.2 ? '(Traffic)' : ''}",
                  ),
                  backgroundColor: Colors.orange[700],
                  duration: const Duration(seconds: 4),
                ),
              );
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Error calculating advanced estimates: $e");
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // ENHANCED DEEP LINKING with coordinates
  Future<void> _openApp(String platform) async {
    if (_pickupLat == null || _pickupLng == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please wait for location to be detected")),
        );
      }
      return;
    }

    Uri uri;

    // Format coordinates for deep links
    final pickup = "$_pickupLat,$_pickupLng";
    final drop = _dropLat != null && _dropLng != null 
        ? "$_dropLat,$_dropLng" 
        : "";

    switch (platform) {
      case 'Uber':
        // Uber Universal Link with pickup and dropoff
        if (drop.isNotEmpty) {
          uri = Uri.parse(
            "https://m.uber.com/ul/?action=setPickup"
            "&pickup[latitude]=$_pickupLat"
            "&pickup[longitude]=$_pickupLng"
            "&dropoff[latitude]=$_dropLat"
            "&dropoff[longitude]=$_dropLng"
          );
        } else {
          uri = Uri.parse("https://m.uber.com/ul");
        }
        break;

      case 'Ola':
        // Ola deep link with coordinates
        if (drop.isNotEmpty) {
          uri = Uri.parse(
            "olacabs://app/launch?lat=$_pickupLat&lng=$_pickupLng"
            "&drop_lat=$_dropLat&drop_lng=$_dropLng"
          );
        } else {
          uri = Uri.parse("olacabs://app");
        }
        break;

      case 'Rapido':
        // Rapido deep link
        if (drop.isNotEmpty) {
          uri = Uri.parse(
            "rapido://ride?pickup=$pickup&drop=$drop"
          );
        } else {
          uri = Uri.parse("rapido://");
        }
        break;

      case 'Namma Yatri':
        // Namma Yatri deep link
        if (drop.isNotEmpty) {
          uri = Uri.parse(
            "nammayatri://book?pickupLat=$_pickupLat&pickupLon=$_pickupLng"
            "&dropLat=$_dropLat&dropLon=$_dropLng"
          );
        } else {
          uri = Uri.parse("nammayatri://");
        }
        break;

      default:
        return;
    }

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        // Fallback: Try to open app store or show error
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Could not launch $platform. Is it installed?"),
              action: SnackBarAction(
                label: 'Install',
                onPressed: () => _openAppStore(platform),
              ),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("Error launching $platform: $e");
    }
  }

  // Open app store for installation
  void _openAppStore(String platform) async {
    String url = '';
    switch (platform) {
      case 'Uber':
        url = 'https://play.google.com/store/apps/details?id=com.ubercab';
        break;
      case 'Ola':
        url = 'https://play.google.com/store/apps/details?id=com.olacabs.customer';
        break;
      case 'Rapido':
        url = 'https://play.google.com/store/apps/details?id=com.rapido.passenger';
        break;
      case 'Namma Yatri':
        url = 'https://play.google.com/store/apps/details?id=in.juspay.nammayatri';
        break;
    }

    if (url.isNotEmpty) {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("AllBooking 🇮🇳"),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _getCurrentLocation,
            tooltip: 'Refresh location',
          ),
        ],
      ),
      body: GestureDetector(
        onTap: () {
          // Hide suggestions when tapping outside
          setState(() {
            _showSuggestions = false;
          });
          FocusScope.of(context).unfocus();
        },
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // City indicator
              if (_cityData != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Row(
                    children: [
                      const Icon(Icons.location_city, size: 16, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(
                        "Pricing for: ${_cityData!.cityName}",
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              
              // SECTION 1: LOCATION INPUTS WITH AUTOCOMPLETE
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          // Pickup Location (Current GPS)
                          TextField(
                            controller: _pickupController,
                            decoration: InputDecoration(
                              icon: const Icon(Icons.my_location, color: Colors.blue),
                              labelText: "Pickup",
                              hintText: "Current Location",
                              border: InputBorder.none,
                              suffixIcon: _currentPosition == null
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: Padding(
                                        padding: EdgeInsets.all(12.0),
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      ),
                                    )
                                  : null,
                            ),
                            readOnly: true,
                          ),
                          const Divider(),

                          // Drop Location with Autocomplete
                          TextField(
                            controller: _dropController,
                            decoration: InputDecoration(
                              icon: const Icon(Icons.location_on, color: Colors.red),
                              labelText: "Drop Location",
                              hintText: "e.g., Prestige Tech Park",
                              border: InputBorder.none,
                              suffixIcon: _dropController.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear),
                                      onPressed: () {
                                        _dropController.clear();
                                        setState(() {
                                          _dropLat = null;
                                          _dropLng = null;
                                          _suggestions = [];
                                          _showSuggestions = false;
                                          _estimates = {
                                            'Uber': {'price': 0, 'eta': 0, 'surge': 1.0, 'color': Colors.black},
                                            'Ola': {'price': 0, 'eta': 0, 'surge': 1.0, 'color': const Color(0xFFCDDC39)},
                                            'Rapido': {'price': 0, 'eta': 0, 'surge': 1.0, 'color': const Color(0xFFFFC107)},
                                            'Namma Yatri': {'price': 0, 'eta': 0, 'surge': 1.0, 'color': const Color(0xFFF44336)},
                                          };
                                        });
                                      },
                                    )
                                  : null,
                            ),
                            onTap: () {
                              if (_suggestions.isNotEmpty) {
                                setState(() {
                                  _showSuggestions = true;
                                });
                              }
                            },
                          ),
                        ],
                      ),
                    ),

                    // Suggestions List
                    if (_showSuggestions && _suggestions.isNotEmpty)
                      Container(
                        constraints: const BoxConstraints(maxHeight: 200),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: _suggestions.length,
                          separatorBuilder: (context, index) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final suggestion = _suggestions[index];
                            return ListTile(
                              leading: const Icon(Icons.location_on, color: Colors.grey),
                              title: Text(
                                suggestion.mainText,
                                style: const TextStyle(fontWeight: FontWeight.w500),
                              ),
                              subtitle: Text(
                                suggestion.secondaryText,
                                style: const TextStyle(fontSize: 12),
                              ),
                              onTap: () {
                                _getPlaceDetails(suggestion.placeId, suggestion.description);
                              },
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // SECTION 2: VEHICLE SELECTOR
              const Text(
                "Choose Vehicle",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: ['Auto', 'Bike', 'Cab', 'Any'].map((type) {
                    bool isSelected = _selectedVehicle == type;
                    return Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: ChoiceChip(
                        label: Text(type),
                        selected: isSelected,
                        onSelected: (selected) {
                          setState(() {
                            _selectedVehicle = type;
                          });
                          // Recalculate prices when vehicle type changes
                          if (_dropLat != null && _dropLng != null) {
                            _calculateAdvancedEstimates();
                          }
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),

              const SizedBox(height: 20),

              // SECTION 3: COMPARISON LIST
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Best Options",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  if (_isLoading)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
              const SizedBox(height: 10),

              if (_dropController.text.isEmpty)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.location_searching,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          "Enter your drop location to see estimates",
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView(
                    children: _estimates.entries.map((entry) {
                      String name = entry.key;
                      Map data = entry.value;
                      double surge = data['surge'] ?? 1.0;
                      bool hasSurge = surge > 1.15;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: data['color'],
                            child: Text(
                              name[0],
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                          title: Row(
                            children: [
                              Text("$name $_selectedVehicle"),
                              if (hasSurge)
                                Padding(
                                  padding: const EdgeInsets.only(left: 8.0),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.orange[100],
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      "${((surge - 1) * 100).round()}%⚡",
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.orange[900],
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          subtitle: Text(
                            data['price'] == 0
                                ? "Metered / App decides"
                                : "Est. ₹${data['price']} • ${data['eta']} mins",
                          ),
                          trailing: ElevatedButton(
                            onPressed: () => _openApp(name),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue[50],
                              foregroundColor: Colors.blue,
                            ),
                            child: const Text("OPEN"),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pickupController.dispose();
    _dropController.dispose();
    _debounce?.cancel();
    super.dispose();
  }
}

// Model class for place suggestions
class PlaceSuggestion {
  final String placeId;
  final String description;
  final String mainText;
  final String secondaryText;

  PlaceSuggestion({
    required this.placeId,
    required this.description,
    required this.mainText,
    required this.secondaryText,
  });
}
