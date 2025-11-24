import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

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
  final TextEditingController _dropController = TextEditingController();
  
  // Selected Vehicle Type
  String _selectedVehicle = 'Auto';
  
  // Mock Estimates (In a real app, these would come from an API)
  // You can adjust these manually to test the "Sort" feature
  final Map<String, dynamic> _estimates = {
    'Uber': {'price': 110, 'eta': 4, 'color': Colors.black},
    'Ola': {'price': 105, 'eta': 6, 'color': const Color(0xFFCDDC39)}, // Lime
    'Rapido': {'price': 95, 'eta': 5, 'color': const Color(0xFFFFC107)}, // Amber
    'Namma Yatri': {'price': 0, 'eta': 8, 'color': const Color(0xFFF44336)}, // Red (Price 0 means unknown)
  };

  // DEEP LINKING LOGIC
  Future<void> _openApp(String platform) async {
    Uri uri;
    
    // Note: Actual deep links often require specific lat/long parameters.
    // For this MVP, we launch the app generally. 
    switch (platform) {
      case 'Uber':
        // Uber Universal Link
        uri = Uri.parse("https://m.uber.com/ul"); 
        break;
      case 'Ola':
        // Ola Scheme
        uri = Uri.parse("olacabs://app");
        break;
      case 'Rapido':
        // Rapido Scheme
        uri = Uri.parse("rapido://"); 
        break;
      case 'Namma Yatri':
        // Namma Yatri Scheme (fallback to store if not installed)
        uri = Uri.parse("nammayatri://");
        break;
      default:
        return;
    }

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        // Fallback: If app isn't installed, open App Store (optional improvement)
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Could not launch $platform. Is it installed?")),
          );
        }
      }
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("AllBooking 🇮🇳"),
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // SECTION 1: INPUTS
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    const TextField(
                      decoration: InputDecoration(
                        icon: Icon(Icons.my_location, color: Colors.blue),
                        labelText: "Pickup",
                        hintText: "Current Location",
                        border: InputBorder.none,
                      ),
                      readOnly: true, // For MVP, assume GPS is automatic
                    ),
                    const Divider(),
                    TextField(
                      controller: _dropController,
                      decoration: const InputDecoration(
                        icon: Icon(Icons.location_on, color: Colors.red),
                        labelText: "Drop Location",
                        hintText: "e.g. Christ University",
                        border: InputBorder.none,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 20),
            
            // SECTION 2: VEHICLE SELECTOR
            const Text("Choose Vehicle", style: TextStyle(fontWeight: FontWeight.bold)),
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
                      },
                    ),
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: 20),

            // SECTION 3: COMPARISON LIST
            const Text("Best Options (Estimated)", style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            
            Expanded(
              child: ListView(
                children: _estimates.entries.map((entry) {
                  String name = entry.key;
                  Map data = entry.value;
                  
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: data['color'],
                        child: Text(name[0], style: const TextStyle(color: Colors.white)),
                      ),
                      title: Text("$name $_selectedVehicle"),
                      subtitle: Text(data['price'] == 0 
                          ? "Metered / App decides" 
                          : "Est. ₹${data['price']} • ${data['eta']} mins"),
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
    );
  }
}
