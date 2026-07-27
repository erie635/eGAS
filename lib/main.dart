import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'features/home/home_map_page.dart';
import 'features/driver/driver_login_page.dart';
import 'features/auth/customer_login_page.dart';
import 'features/customer/customer_dashboard.dart'; // ✅ KEEP ONLY ONE

// ✅ REMOVED duplicate import of customer_dashboard.dart
// ✅ REMOVED customer_profile_page.dart import (using customer_dashboard instead)

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'E-Fuel Delivery',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: Colors.green,
        scaffoldBackgroundColor: Colors.white,
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),
      // ✅ NAMED ROUTES - Using CustomerDashboard consistently
      routes: {
        '/login': (context) => const CustomerLoginPage(),
        '/home': (context) => const HomeMapPage(),
        '/profile': (context) => const CustomerDashboard(), // ✅ Using CustomerDashboard
        '/driver_login': (context) => const DriverLoginPage(),
        '/customer_dashboard': (context) => const CustomerDashboard(),
      },
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.active) {
            final user = snapshot.data;
            if (user != null) {
              return const HomePage();
            }
          }
          return const HomePage();
        },
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('⛽ E-Fuel Delivery'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        actions: [
          if (user != null)
            PopupMenuButton<String>(
              icon: const Icon(Icons.account_circle),
              onSelected: (value) {
                if (value == 'profile') {
                  // ✅ NAVIGATE TO CUSTOMER DASHBOARD
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const CustomerDashboard(),
                    ),
                  );
                } else if (value == 'dashboard') {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const CustomerDashboard(),
                    ),
                  );
                } else if (value == 'logout') {
                  FirebaseAuth.instance.signOut();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'profile',
                  child: Row(
                    children: [
                      Icon(Icons.person),
                      SizedBox(width: 8),
                      Text('My Profile'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'dashboard',
                  child: Row(
                    children: [
                      Icon(Icons.dashboard),
                      SizedBox(width: 8),
                      Text('Dashboard'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'logout',
                  child: Row(
                    children: [
                      Icon(Icons.logout),
                      SizedBox(width: 8),
                      Text('Logout'),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.local_gas_station,
              size: 80,
              color: Colors.green,
            ),
            const SizedBox(height: 20),
            const Text(
              'Fuel Delivery Service',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Order fuel or become a driver',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 40),

            // 👤 Customer button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () {
                  if (user != null) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const HomeMapPage(),
                      ),
                    );
                  } else {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const CustomerLoginPage(),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.person, color: Colors.white),
                label: Text(
                  user != null ? 'Order Fuel' : 'Continue as Customer',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // 🚚 Driver Mode - Simple clickable word
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const DriverLoginPage(),
                  ),
                );
              },
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 8.0),
                child: Text(
                  'Driver Mode',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.orange,
                  ),
                ),
              ),
            ),

            // ✅ PROFILE BUTTON AT BOTTOM
            if (user != null) ...[
              const SizedBox(height: 30),
              const Divider(),
              const SizedBox(height: 10),
              Text(
                'Logged in as: ${user.email}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const CustomerDashboard(),
                    ),
                  );
                },
                child: const Text(
                  'View My Profile',
                  style: TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}