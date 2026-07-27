// ============================================================
// FILE: customer_login_page.dart - WITH STRICT SEPARATION
// ============================================================

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../home/home_map_page.dart';

class CustomerLoginPage extends StatefulWidget {
  const CustomerLoginPage({super.key});

  @override
  State<CustomerLoginPage> createState() => _CustomerLoginPageState();
}

class _CustomerLoginPageState extends State<CustomerLoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _isLoading = false;
  bool _isRegistering = false;
  bool _obscurePassword = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isRegistering ? 'Create Account' : 'Customer Login'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
      ),
      body: Container(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.green.shade100,
                    borderRadius: BorderRadius.circular(40),
                  ),
                  child: const Icon(
                    Icons.person,
                    size: 50,
                    color: Colors.green,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  _isRegistering ? 'Create Customer Account' : 'Welcome Back',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _isRegistering ? 'Join us for fuel delivery services' : 'Login to order fuel and track purchases',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 30),
                if (_isRegistering) ...[
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Full Name',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Phone Number (e.g., 0712345678)',
                      hintText: '0712345678',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.phone),
                      helperText: 'Enter your phone number starting with 0',
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.email),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Password (min 6 characters)',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.lock),
                    helperText: 'Minimum 6 characters',
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _isLoading ? null : _handleAuth,
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            _isRegistering ? 'Create Account' : 'Login',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _isRegistering = !_isRegistering;
                      if (!_isRegistering) {
                        _nameController.clear();
                        _phoneController.clear();
                      }
                    });
                  },
                  child: Text(
                    _isRegistering ? 'Already have an account? Login' : 'New customer? Create account',
                    style: TextStyle(
                      color: Colors.green.shade700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // ✅ STRICT EMAIL UNIQUENESS CHECK - ACROSS BOTH COLLECTIONS
  // ============================================================
  Future<bool> _emailAlreadyUsed(String email) async {
    try {
      // Check in customers collection
      final customerQuery = await FirebaseFirestore.instance
          .collection('customers')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (customerQuery.docs.isNotEmpty) {
        return true;
      }

      // Check in drivers collection
      final driverQuery = await FirebaseFirestore.instance
          .collection('drivers')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (driverQuery.docs.isNotEmpty) {
        return true;
      }

      return false;
    } catch (e) {
      print('❌ Error checking email: $e');
      return false;
    }
  }

  // ============================================================
  // ✅ STRICT ROLE VERIFICATION AFTER LOGIN
  // ============================================================
  Future<bool> _verifyCustomerRole(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('customers')
          .doc(uid)
          .get();

      if (!doc.exists) {
        return false;
      }

      final data = doc.data()!;
      
      // ✅ CRITICAL: Verify userType is 'customer'
      if (data['userType'] != 'customer') {
        return false;
      }

      return true;
    } catch (e) {
      print('❌ Error verifying customer role: $e');
      return false;
    }
  }

  // ============================================================
  // ✅ STRICT DRIVER CHECK - PREVENT DRIVER LOGIN
  // ============================================================
  Future<bool> _isDriverAccount(String email) async {
    try {
      final query = await FirebaseFirestore.instance
          .collection('drivers')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();
      
      return query.docs.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  Future<void> _handleAuth() async {
    // Validate fields
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields')),
      );
      return;
    }

    if (_isRegistering && _nameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your name')),
      );
      return;
    }

    if (_isRegistering && _phoneController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your phone number')),
      );
      return;
    }

    if (_isRegistering) {
      String phone = _phoneController.text.trim();
      if (!RegExp(r'^0[0-9]{9,}$').hasMatch(phone)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter a valid phone number (e.g., 0712345678)'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    }

    setState(() => _isLoading = true);

    try {
      final String email = _emailController.text.trim();
      final String password = _passwordController.text.trim();

      if (_isRegistering) {
        // ============================================================
        // ✅ CUSTOMER REGISTRATION - WITH STRICT UNIQUENESS CHECK
        // ============================================================

        // ✅ Step 1: Check if email is already used ANYWHERE
        if (await _emailAlreadyUsed(email)) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ This email is already registered. Please use a different email or login.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 4),
            ),
          );
          return;
        }

        // ✅ Step 2: Create Firebase Auth account
        UserCredential userCredential = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(
              email: email,
              password: password,
            );

        // ✅ Step 3: Verify no duplicate was created (edge case)
        final verifyDoc = await FirebaseFirestore.instance
            .collection('customers')
            .doc(userCredential.user!.uid)
            .get();

        if (verifyDoc.exists) {
          await FirebaseAuth.instance.signOut();
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ Account already exists. Please login.'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        // ✅ Step 4: Save customer data to CUSTOMERS collection ONLY
        String phoneNumber = _phoneController.text.trim();
        String formattedPhone = _formatPhoneNumber(phoneNumber);

        await FirebaseFirestore.instance
            .collection('customers')
            .doc(userCredential.user!.uid)
            .set({
          'userId': userCredential.user!.uid,
          'name': _nameController.text.trim(),
          'phone': formattedPhone,
          'email': email,
          'totalSpent': 0,
          'totalOrders': 0,
          'lastOrderDate': null,
          'createdAt': FieldValue.serverTimestamp(),
          'discountRate': 0,
          'feedbackCount': 0,
          'avgRating': 0,
          'userType': 'customer', // ✅ CRITICAL: Explicitly set as customer
          'phoneVerified': false,
        });

        // ✅ Step 5: Update Firebase Auth profile
        await userCredential.user!.updateDisplayName(_nameController.text.trim());

        setState(() => _isLoading = false);

        // ✅ Step 6: Show success and switch to login
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Account created! Please login with your credentials.'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
        }

        // ✅ Step 7: Clear fields and switch to login
        setState(() {
          _isRegistering = false;
          _emailController.clear();
          _passwordController.clear();
          _nameController.clear();
          _phoneController.clear();
        });

        return;
      }

      // ============================================================
      // ✅ CUSTOMER LOGIN - WITH STRICT ROLE VERIFICATION
      // ============================================================

      // ✅ Step 1: Check if email is in DRIVERS collection (BLOCK)
      if (await _isDriverAccount(email)) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ This email is registered as a DRIVER. Please use the Driver Login page.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
          ),
        );
        return;
      }

      // ✅ Step 2: Attempt Firebase Auth sign-in
      UserCredential userCredential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(
            email: email,
            password: password,
          );

      // ✅ Step 3: STRICT ROLE VERIFICATION
      final bool isCustomer = await _verifyCustomerRole(userCredential.user!.uid);

      if (!isCustomer) {
        // ❌ Not a customer - sign out immediately
        await FirebaseAuth.instance.signOut();
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ This account is not registered as a customer. Please register first.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
          ),
        );
        return;
      }

      // ✅ Step 4: Success - Navigate to home
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => const HomeMapPage(),
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      String message = 'Authentication failed';
      if (e.code == 'user-not-found') {
        message = 'No account found. Please register first.';
      } else if (e.code == 'wrong-password') {
        message = 'Incorrect password. Please try again.';
      } else if (e.code == 'email-already-in-use') {
        message = 'This email is already registered. Please login.';
      } else if (e.code == 'weak-password') {
        message = 'Password too weak. Use at least 6 characters.';
      } else if (e.code == 'invalid-email') {
        message = 'Invalid email address.';
      } else if (e.code == 'too-many-requests') {
        message = 'Too many attempts. Please try again later.';
      } else if (e.code == 'network-request-failed') {
        message = 'Network error. Check your connection.';
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatPhoneNumber(String phone) {
    String cleaned = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleaned.startsWith('0') && cleaned.length >= 10) {
      return cleaned;
    }
    if (cleaned.startsWith('254') && cleaned.length >= 12) {
      return '0${cleaned.substring(3)}';
    }
    if (cleaned.length >= 9) {
      return '0$cleaned';
    }
    return phone;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }
}