import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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

  // ✅ Check if user is a driver by checking Firestore
  Future<bool> _isDriver(User user) async {
    try {
      final driverDoc = await FirebaseFirestore.instance
          .collection('drivers')
          .doc(user.uid)
          .get();
      return driverDoc.exists;
    } catch (e) {
      print('Error checking driver status: $e');
      return false;
    }
  }

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
      body: FutureBuilder<bool>(
        future: user != null ? _isDriver(user) : Future.value(false),
        builder: (context, snapshot) {
          // Handle loading state
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          final isDriver = snapshot.data ?? false;
          final isCustomer = user != null && !isDriver;

          return Container(
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

                // 👤 CUSTOMER MODE
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          isDriver ? Colors.grey.shade400 : Colors.green,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: isDriver
                        ? null
                        : () {
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
                    icon: Icon(
                      Icons.person,
                      color: isDriver ? Colors.grey.shade600 : Colors.white,
                    ),
                    label: Text(
                      isDriver
                          ? 'Customer Mode Unavailable'
                          : user != null
                              ? 'Order Fuel'
                              : 'Continue as Customer',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDriver ? Colors.grey.shade700 : Colors.white,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                //  DRIVER MODE - Simple clickable word
                GestureDetector(
                  onTap: isCustomer
                      ? null
                      : () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const DriverLoginPage(),
                            ),
                          );
                        },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Text(
                      isCustomer
                          ? 'Driver Mode Unavailable'
                          : user != null && isDriver
                              ? ' Driver Mode Active'
                              : 'Driver Mode',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isCustomer
                            ? Colors.grey.shade400
                            : user != null && isDriver
                                ? Colors.green
                                : Colors.orange,
                      ),
                    ),
                  ),
                ),

                // ✅ PROFILE BUTTON AT BOTTOM - Only for customers
                if (user != null && !isDriver) ...[
                  const SizedBox(height: 30),
                  const Divider(),
                  const SizedBox(height: 10),
                  Text(
                    'You are logged in as: ${user.email}',
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

                // ✅ DRIVER STATUS - Show when driver is logged in
                if (user != null && isDriver) ...[
                  const SizedBox(height: 30),
                  const Divider(),
                  const SizedBox(height: 10),
                  Text(
                    'You are logged in as: ${user.email}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: const Text(
                      'Driver mode is active',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.green,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}