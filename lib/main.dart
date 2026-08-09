import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'features/home/home_map_page.dart';
import 'features/driver/driver_login_page.dart';
import 'features/auth/customer_login_page.dart';
import 'features/customer/customer_dashboard.dart';
import 'features/driver/driver_dashboard.dart';

// Global variable to track initialization
bool _isFirebaseInitialized = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // ✅ Prevent duplicate initialization
  if (!_isFirebaseInitialized) {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      _isFirebaseInitialized = true;
    } catch (e) {
      print('Firebase initialization error: $e');
      if (e.toString().contains('duplicate-app')) {
        print('Firebase already initialized, continuing...');
        _isFirebaseInitialized = true;
      } else {
        rethrow;
      }
    }
  }
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'eGAS',
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
      routes: {
        '/login': (context) => const CustomerLoginPage(),
        '/home': (context) => const HomeMapPage(),
        '/profile': (context) => const CustomerDashboard(),
        '/driver_login': (context) => const DriverLoginPage(),
        '/customer_dashboard': (context) => const CustomerDashboard(),
        '/driver_dashboard': (context) => const DriverDashboard(),
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

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Map<String, dynamic>? _userData;
  bool _isDriver = false;
  bool _isLoading = true;
  String _displayName = 'User';
  String _userEmail = 'No email';
  
  // Stream subscriptions for real-time updates
  StreamSubscription<DocumentSnapshot>? _driverSubscription;
  StreamSubscription<DocumentSnapshot>? _customerSubscription;
  StreamSubscription<User?>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _setupAuthListener();
    _loadUserData();
    _listenToUserData();
  }

  @override
  void dispose() {
    _driverSubscription?.cancel();
    _customerSubscription?.cancel();
    _authSubscription?.cancel();
    super.dispose();
  }

  // Listen to auth state changes
  void _setupAuthListener() {
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        // User logged in, load data
        _loadUserData();
        _listenToUserData();
      } else {
        // User logged out, reset state
        setState(() {
          _isDriver = false;
          _userData = null;
          _displayName = 'User';
          _userEmail = 'No email';
          _isLoading = false;
        });
      }
    });
  }

  // Real-time listener for user data
  void _listenToUserData() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Cancel existing subscriptions
    _driverSubscription?.cancel();
    _customerSubscription?.cancel();

    // Listen to driver collection
    _driverSubscription = FirebaseFirestore.instance
        .collection('drivers')
        .doc(user.uid)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists && mounted) {
        setState(() {
          _isDriver = true;
          _userData = snapshot.data();
          _updateDisplayInfo(snapshot.data()!);
          _isLoading = false;
        });
      } else {
        // If driver doesn't exist, check customer
        _checkCustomerData(user.uid);
      }
    }, onError: (error) {
      print('Error listening to driver data: $error');
    });

    // Also listen to customer collection as fallback
    _customerSubscription = FirebaseFirestore.instance
        .collection('customers')
        .doc(user.uid)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists && mounted && !_isDriver) {
        setState(() {
          _userData = snapshot.data();
          _updateDisplayInfo(snapshot.data()!);
          _isLoading = false;
        });
      }
    }, onError: (error) {
      print('Error listening to customer data: $error');
    });
  }

  void _checkCustomerData(String uid) {
    // This is called when driver doesn't exist
    // The customer stream will handle the update
  }

  void _updateDisplayInfo(Map<String, dynamic> data) {
    final user = FirebaseAuth.instance.currentUser;
    String displayName = user?.displayName ?? 'User';
    String userEmail = user?.email ?? 'No email';
    
    if (data['firstName'] != null && data['lastName'] != null) {
      displayName = '${data['firstName']} ${data['lastName']}';
    } else if (data['fullName'] != null) {
      displayName = data['fullName'];
    } else if (data['name'] != null) {
      displayName = data['name'];
    }
    if (data['email'] != null) {
      userEmail = data['email'];
    }
    
    _displayName = displayName;
    _userEmail = userEmail;
  }

  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final driverDoc = await FirebaseFirestore.instance
            .collection('drivers')
            .doc(user.uid)
            .get();
        
        final isDriverNow = driverDoc.exists;
        
        final customerDoc = await FirebaseFirestore.instance
            .collection('customers')
            .doc(user.uid)
            .get();
        
        Map<String, dynamic>? userData;
        if (isDriverNow) {
          userData = driverDoc.data();
        } else if (customerDoc.exists) {
          userData = customerDoc.data();
        }
        
        String displayName = user.displayName ?? 'User';
        String userEmail = user.email ?? 'No email';
        
        if (userData != null) {
          if (userData['firstName'] != null && userData['lastName'] != null) {
            displayName = '${userData['firstName']} ${userData['lastName']}';
          } else if (userData['fullName'] != null) {
            displayName = userData['fullName'];
          } else if (userData['name'] != null) {
            displayName = userData['name'];
          }
          if (userData['email'] != null) {
            userEmail = userData['email'];
          }
        }
        
        if (mounted) {
          setState(() {
            _isDriver = isDriverNow;
            _userData = userData;
            _displayName = displayName;
            _userEmail = userEmail;
            _isLoading = false;
          });
        }
      } catch (e) {
        print('Error loading user data: $e');
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    } else {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<bool> _isDriverCheck(User user) async {
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
        title: const Text('⛽ eGAS'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        actions: [
          // Use a Builder to ensure the menu rebuilds with latest state
          Builder(
            builder: (context) {
              return PopupMenuButton<String>(
                icon: const Icon(Icons.account_circle),
                onSelected: (value) {
                  if (user == null) {
                    if (value == 'account' || value == 'profile') {
                      _showNoUserMessage(context, 'No profile to display. Please login first.');
                    } else if (value == 'change_password') {
                      _showNoUserMessage(context, 'No account to change password. Please login first.');
                    } else if (value == 'delete_account') {
                      _showNoUserMessage(context, 'No account to delete. Please login first.');
                    } else if (value == 'logout') {
                      _showNoUserMessage(context, 'No user logged in to sign out.');
                    } else if (value == 'refresh') {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Refreshing app state...'),
                          backgroundColor: Colors.blue,
                        ),
                      );
                      _loadUserData();
                    } else if (value == 'driver_login') {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const DriverLoginPage(),
                        ),
                      );
                    }
                    return;
                  }

                  if (value == 'account' || value == 'profile') {
                    if (!_isDriver) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const CustomerDashboard(),
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Drivers do not have a customer profile.'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                    }
                  } else if (value == 'refresh') {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Refreshing profile data...'),
                        backgroundColor: Colors.green,
                      ),
                    );
                    _loadUserData();
                  } else if (value == 'change_password') {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Change password functionality coming soon...'),
                        backgroundColor: Colors.orange,
                      ),
                    );
                  } else if (value == 'delete_account') {
                    _showDeleteAccountDialog(context);
                  } else if (value == 'logout') {
                    FirebaseAuth.instance.signOut();
                  } else if (value == 'driver_login') {
                    // If user is already a driver, navigate to driver dashboard
                    if (_isDriver) {
                      // Show message and navigate to driver dashboard
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('You are already logged in as a driver.'),
                          backgroundColor: Colors.green,
                          duration: Duration(seconds: 1),
                        ),
                      );
                      // Navigate to driver dashboard
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const DriverDashboard(),
                        ),
                      );
                    } else {
                      // If not a driver, navigate to driver login page
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const DriverLoginPage(),
                        ),
                      );
                    }
                  }
                },
                itemBuilder: (context) {
                  List<PopupMenuEntry<String>> menuItems = [];
                  final isLoggedIn = user != null;

                  // 1. Account Info Section (Header)
                  if (isLoggedIn) {
                    menuItems.add(
                      PopupMenuItem<String>(
                        value: 'header',
                        enabled: false,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.account_circle, color: Colors.green, size: 28),
                                const SizedBox(width: 8),
                                Text(
                                  _displayName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _userEmail,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Account created: ${user!.metadata.creationTime != null ? _formatDate(user.metadata.creationTime!) : 'N/A'}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: _isDriver ? Colors.green.shade100 : Colors.blue.shade100,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                _isDriver ? 'Driver' : 'Customer',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: _isDriver ? Colors.green.shade800 : Colors.blue.shade800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  } else {
                    menuItems.add(
                      const PopupMenuItem<String>(
                        value: 'header',
                        enabled: false,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.account_circle, color: Colors.grey, size: 28),
                                SizedBox(width: 8),
                                Text(
                                  'Not Logged In',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Please login to access your account',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  menuItems.add(const PopupMenuDivider());

                  // 2. Account Settings Section
                  menuItems.add(
                    const PopupMenuItem<String>(
                      value: 'settings_header',
                      enabled: false,
                      child: Text(
                        'Account Settings',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  );

                  // My Profile - DISABLED for drivers (greyed out with lock)
                  final isDriverUser = isLoggedIn && _isDriver;
                  final isCustomerUser = isLoggedIn && !_isDriver;
                  
                  menuItems.add(
                    PopupMenuItem<String>(
                      value: 'profile',
                      enabled: isCustomerUser,
                      child: Row(
                        children: [
                          Icon(
                            Icons.person,
                            color: isCustomerUser ? Colors.green : Colors.grey.shade400,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'My Profile',
                            style: TextStyle(
                              color: isCustomerUser ? null : Colors.grey.shade400,
                            ),
                          ),
                          if (isDriverUser) ...[
                            const Spacer(),
                            Icon(
                              Icons.lock,
                              color: Colors.grey.shade400,
                              size: 16,
                            ),
                          ],
                          if (!isLoggedIn) ...[
                            const Spacer(),
                            Icon(
                              Icons.lock,
                              color: Colors.grey.shade400,
                              size: 16,
                            ),
                          ],
                        ],
                      ),
                    ),
                  );

                  menuItems.add(
                    const PopupMenuItem<String>(
                      value: 'refresh',
                      child: Row(
                        children: [
                          Icon(Icons.refresh, color: Colors.blue),
                          SizedBox(width: 12),
                          Text('Refresh Profile Data'),
                        ],
                      ),
                    ),
                  );

                  menuItems.add(
                    PopupMenuItem<String>(
                      value: 'change_password',
                      enabled: true,
                      child: Row(
                        children: [
                          Icon(
                            Icons.lock_outline,
                            color: isLoggedIn ? Colors.orange : Colors.grey.shade600,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Change Password',
                            style: TextStyle(
                              color: isLoggedIn ? null : Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );

                  menuItems.add(
                    PopupMenuItem<String>(
                      value: 'delete_account',
                      enabled: true,
                      child: Row(
                        children: [
                          Icon(
                            Icons.delete_outline,
                            color: isLoggedIn ? Colors.red : Colors.grey.shade600,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Delete Account',
                            style: TextStyle(
                              color: isLoggedIn ? null : Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );

                  menuItems.add(const PopupMenuDivider());

                  // 3. Driver Section - ENABLED for drivers and when no user is logged in
                  // DISABLED for customers only
                  final isDriverUser2 = isLoggedIn && _isDriver;
                  final isCustomerUser2 = isLoggedIn && !_isDriver;
                  final isNotLoggedIn = !isLoggedIn;
                  
                  menuItems.add(
                    PopupMenuItem<String>(
                      value: 'driver_login',
                      enabled: isDriverUser2 || isNotLoggedIn, // Enabled for drivers AND when no user
                      child: Row(
                        children: [
                          Icon(
                            Icons.directions_car,
                            color: (isDriverUser2 || isNotLoggedIn) ? Colors.orange : Colors.grey.shade400,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            isDriverUser2 ? 'Already a Driver' : 'Login as a Driver',
                            style: TextStyle(
                              color: (isDriverUser2 || isNotLoggedIn) ? null : Colors.grey.shade400,
                              fontWeight: (isDriverUser2 || isNotLoggedIn) ? FontWeight.normal : FontWeight.normal,
                            ),
                          ),
                          if (isDriverUser2) ...[
                            const Spacer(),
                            Icon(
                              Icons.check_circle,
                              color: Colors.green,
                              size: 16,
                            ),
                          ],
                          if (isCustomerUser2) ...[
                            const Spacer(),
                            Icon(
                              Icons.lock,
                              color: Colors.grey.shade400,
                              size: 16,
                            ),
                          ],
                        ],
                      ),
                    ),
                  );

                  menuItems.add(const PopupMenuDivider());

                  // 4. Logout Section
                  menuItems.add(
                    PopupMenuItem<String>(
                      value: 'logout',
                      enabled: true,
                      child: Row(
                        children: [
                          Icon(
                            Icons.logout,
                            color: isLoggedIn ? Colors.red : Colors.grey.shade600,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Sign Out',
                            style: TextStyle(
                              color: isLoggedIn ? null : Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );

                  return menuItems;
                },
              );
            },
          ),
        ],
      ),
      body: FutureBuilder<bool>(
        future: user != null ? _isDriverCheck(user) : Future.value(false),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && _isLoading) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          final isDriver = _isDriver || (snapshot.data ?? false);

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

                if (user != null && isDriver) ...[
                  const SizedBox(height: 30),
                  const Divider(),
                  const SizedBox(height: 10),
                  Text(
                    'You are logged in as: $_displayName',
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

  void _showNoUserMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showDeleteAccountDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Account'),
          content: const Text(
            'Are you sure you want to permanently delete your account? This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Account deletion functionality coming soon...'),
                    backgroundColor: Colors.red,
                  ),
                );
              },
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}