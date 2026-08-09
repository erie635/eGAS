// ============================================================
// FILE: customer_dashboard.dart - COMPLETE WITH FRIENDLY PROFILE COLORS
// ============================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../home/home_map_page.dart';

// ✅ IMPORT: Discount Service
import '../../services/discount_service.dart';

class CustomerDashboard extends StatefulWidget {
  const CustomerDashboard({super.key});

  @override
  State<CustomerDashboard> createState() => _CustomerDashboardState();
}

class _CustomerDashboardState extends State<CustomerDashboard> with WidgetsBindingObserver {
  Map<String, dynamic>? _customerData;
  List<Map<String, dynamic>> _orderHistory = [];
  bool _isLoading = true;
  double _selectedRating = 0;
  final TextEditingController _feedbackCommentController = TextEditingController();
  
  // ✅ ADDED: Disposal flags for stability
  bool _isDisposed = false;
  bool _isDisposing = false;
  
  // ✅ ADDED: Debounce timer for refresh
  Timer? _refreshDebounceTimer;
  
  // ✅ ADDED: Track if data has been loaded once
  bool _initialLoadDone = false;

  // ✅ ADDED: Discount related variables
  double _currentDiscount = 0.0;
  double _discountedPrice = 0.0;
  bool _isDiscountLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadCustomerData();
  }

  @override
  void dispose() {
    if (_isDisposed || _isDisposing) {
      super.dispose();
      return;
    }
    
    _isDisposing = true;
    
    try {
      WidgetsBinding.instance.removeObserver(this);
    } catch (e) {
      // Ignore
    }
    
    try {
      _refreshDebounceTimer?.cancel();
      _refreshDebounceTimer = null;
    } catch (e) {
      // Ignore
    }
    
    try {
      _feedbackCommentController.dispose();
    } catch (e) {
      // Ignore
    }
    
    _isDisposed = true;
    _isDisposing = false;
    super.dispose();
  }

  // ✅ ADDED: Lifecycle observer
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isDisposed || _isDisposing) return;
    
    switch (state) {
      case AppLifecycleState.resumed:
        _debounceRefresh();
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        break;
    }
  }

  // ✅ ADDED: Debounced refresh
  void _debounceRefresh() {
    if (_isDisposed || _isDisposing) return;
    
    _refreshDebounceTimer?.cancel();
    _refreshDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted && !_isDisposed && !_isDisposing) {
        _loadCustomerData();
      }
    });
  }

  // ============================================================
  // LOAD CUSTOMER DATA - HIDDEN STATS
  // ============================================================
  Future<void> _loadCustomerData() async {
    if (_isDisposed || _isDisposing) return;
    
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted && !_isDisposed && !_isDisposing) {
        setState(() => _isLoading = false);
      }
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Load customer data
      final doc = await FirebaseFirestore.instance
          .collection('customers')
          .doc(user.uid)
          .get();

      if (doc.exists) {
        if (mounted && !_isDisposed && !_isDisposing) {
          setState(() {
            _customerData = doc.data();
          });
        }
      } else {
        // Create customer document if it doesn't exist
        await FirebaseFirestore.instance
            .collection('customers')
            .doc(user.uid)
            .set({
          'userId': user.uid,
          'name': user.displayName ?? 'Customer',
          'email': user.email ?? '',
          'phone': '',
          'location': '',
          'off': 0,
          'totalOrders': 0,
          'totalSpent': 0.0,
          'star': 0.0,
          'feedbackCount': 0,
          'createdAt': FieldValue.serverTimestamp(),
        });
        
        final newDoc = await FirebaseFirestore.instance
            .collection('customers')
            .doc(user.uid)
            .get();
        
        if (newDoc.exists && mounted && !_isDisposed && !_isDisposing) {
          setState(() {
            _customerData = newDoc.data();
          });
        }
      }

      // ✅ Load order history (hidden from UI but used for calculations)
      await _loadOrderHistory(user.uid);
      
      // ✅ Calculate discount from database
      await _loadCustomerDiscount(user.uid);
      
      if (mounted && !_isDisposed && !_isDisposing) {
        setState(() {
          _isLoading = false;
          _initialLoadDone = true;
        });
      }
    } catch (e) {
      print('Error loading customer data: $e');
      
      if (mounted && !_isDisposed && !_isDisposing) {
        setState(() => _isLoading = false);
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading data. Please try again.'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: _loadCustomerData,
            ),
          ),
        );
      }
    }
  }

  // ✅ Load order history (hidden calculation)
  Future<void> _loadOrderHistory(String userId) async {
    if (_isDisposed || _isDisposing) return;
    
    try {
      final orders = await FirebaseFirestore.instance
          .collection('orders')
          .where('userId', isEqualTo: userId)
          .orderBy('createdAt', descending: true)
          .limit(50)
          .get();

      if (mounted && !_isDisposed && !_isDisposing) {
        setState(() {
          _orderHistory = orders.docs.map((doc) {
            final data = doc.data();
            return {
              'id': doc.id,
              ...data,
            };
          }).toList();
        });
      }
    } catch (e) {
      if (e.toString().contains('index')) {
        try {
          final orders = await FirebaseFirestore.instance
              .collection('orders')
              .where('userId', isEqualTo: userId)
              .limit(50)
              .get();

          if (mounted && !_isDisposed && !_isDisposing) {
            setState(() {
              _orderHistory = orders.docs.map((doc) {
                final data = doc.data();
                return {
                  'id': doc.id,
                  ...data,
                };
              }).toList();
              
              _orderHistory.sort((a, b) {
                final aDate = a['createdAt'] as Timestamp?;
                final bDate = b['createdAt'] as Timestamp?;
                if (aDate == null && bDate == null) return 0;
                if (aDate == null) return 1;
                if (bDate == null) return -1;
                return bDate.compareTo(aDate);
              });
            });
          }
        } catch (fallbackError) {
          print('Fallback error: $fallbackError');
          if (mounted && !_isDisposed && !_isDisposing) {
            setState(() {
              _orderHistory = [];
            });
          }
        }
      }
    }
  }

  // ✅ NEW: Load customer discount from database
  Future<void> _loadCustomerDiscount(String userId) async {
    if (_isDisposed || _isDisposing) return;
    
    try {
      setState(() => _isDiscountLoading = true);
      
      // Get discount from DiscountService
      final discount = await DiscountService.getCombinedDiscount(userId);
      
      if (mounted && !_isDisposed && !_isDisposing) {
        setState(() {
          _currentDiscount = discount;
          
          // Calculate discounted price if there's a base price
          if (_customerData?['lastOrderAmount'] != null) {
            final originalPrice = (_customerData?['lastOrderAmount'] ?? 0.0).toDouble();
            _discountedPrice = DiscountService.applyDiscount(originalPrice, discount);
          }
          _isDiscountLoading = false;
        });
      }
      
      print('✅ Loaded discount: $discount% for user $userId');
      
    } catch (e) {
      print('❌ Error loading discount: $e');
      if (mounted && !_isDisposed && !_isDisposing) {
        setState(() => _isDiscountLoading = false);
      }
    }
  }

  // ============================================================
  // HELPER: Get order display number
  // ============================================================
  String _getOrderDisplayNumber(Map<String, dynamic> order) {
    if (order['orderNumber'] != null && order['orderNumber'].toString().isNotEmpty) {
      return order['orderNumber'].toString();
    }
    
    final orderId = order['id'];
    if (orderId != null && orderId.toString().isNotEmpty) {
      final idStr = orderId.toString();
      if (idStr.length >= 6) {
        return 'ORD-${idStr.substring(0, 6)}';
      } else {
        return 'ORD-${idStr.padLeft(6, '0')}';
      }
    }
    
    return 'N/A';
  }

  // ============================================================
  // HELPER: Safe name initial
  // ============================================================
  String _getNameInitial(String? name) {
    if (name == null || name.isEmpty) {
      return 'U';
    }
    final firstChar = name.substring(0, 1);
    return firstChar.toUpperCase();
  }

  // ============================================================
  // HELPER: Validate phone number
  // ============================================================
  bool _isValidPhoneNumber(String phone) {
    if (phone.isEmpty) return true;
    return RegExp(r'^0[0-9]{9,}$').hasMatch(phone);
  }

  // ============================================================
  // HELPER: Validate discount
  // ============================================================
  bool _isValidDiscount(double discount) {
    return discount >= 0 && discount <= 100;
  }

  // ============================================================
  // SHOW FEEDBACK DIALOG - SAVES TO DB
  // ============================================================
  void _showFeedbackDialog() {
    if (_isDisposed || _isDisposing) return;
    
    _selectedRating = 0;
    _feedbackCommentController.clear();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.star, color: Colors.amber),
                  SizedBox(width: 8),
                  Text('Rate Your Experience'),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.amber.shade200),
                      ),
                      child: Column(
                        children: [
                          const Text(
                            'How was your experience?',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 8),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(5, (index) {
                                return IconButton(
                                  icon: Icon(
                                    index < _selectedRating 
                                        ? Icons.star 
                                        : Icons.star_border,
                                    color: Colors.amber,
                                    size: 38,
                                  ),
                                  onPressed: () {
                                    setStateDialog(() {
                                      _selectedRating = index + 1;
                                    });
                                  },
                                );
                              }),
                            ),
                          ),
                          if (_selectedRating > 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                _getRatingLabel(_selectedRating),
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Colors.amber.shade700,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _feedbackCommentController,
                      decoration: const InputDecoration(
                        labelText: 'Your feedback (optional)',
                        hintText: 'Tell us about your experience...',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.comment),
                      ),
                      maxLines: 3,
                      onChanged: (value) {
                        if (value.startsWith(' ')) {
                          _feedbackCommentController.text = value.trimLeft();
                          _feedbackCommentController.selection = TextSelection.fromPosition(
                            TextPosition(offset: _feedbackCommentController.text.length),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    if (mounted) Navigator.pop(context);
                  },
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                  ),
                  onPressed: () async {
                    if (_isDisposed || _isDisposing) return;
                    
                    if (_selectedRating == 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please select a rating'),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }

                    final user = FirebaseAuth.instance.currentUser;
                    if (user == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please login first'),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }

                    final comment = _feedbackCommentController.text.trim();
                    final sanitizedComment = comment.length > 500 
                        ? comment.substring(0, 500) 
                        : comment;

                    try {
                      // ✅ Save feedback to database
                      await FirebaseFirestore.instance.collection('feedback').add({
                        'userId': user.uid,
                        'customerName': _customerData?['name'] ?? 'Customer',
                        'customerEmail': _customerData?['email'] ?? user.email ?? 'N/A',
                        'customerPhone': _customerData?['phone'] ?? 'N/A',
                        'rating': _selectedRating,
                        'comment': sanitizedComment,
                        'createdAt': FieldValue.serverTimestamp(),
                        'timestamp': DateTime.now().toIso8601String(),
                      });

                      // ✅ Update customer rating in database
                      final feedbacks = await FirebaseFirestore.instance
                          .collection('feedback')
                          .where('userId', isEqualTo: user.uid)
                          .get();

                      double avgRating = 0;
                      if (feedbacks.docs.isNotEmpty) {
                        for (var doc in feedbacks.docs) {
                          avgRating += (doc.data()['rating'] ?? 0).toDouble();
                        }
                        avgRating = avgRating / feedbacks.docs.length;
                      }

                      await FirebaseFirestore.instance
                          .collection('customers')
                          .doc(user.uid)
                          .update({
                        'star': avgRating,
                        'feedbackCount': feedbacks.docs.length,
                        'lastFeedbackDate': FieldValue.serverTimestamp(),
                      });

                      if (mounted && !_isDisposed && !_isDisposing) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('✅ Thank you for your feedback! Rating: ${_selectedRating.toInt()}/5'),
                            backgroundColor: Colors.green,
                          ),
                        );
                        _debounceRefresh();
                      }
                    } catch (e) {
                      if (mounted && !_isDisposed && !_isDisposing) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Error submitting feedback. Please try again.'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                  child: const Text('Submit Feedback'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _getRatingLabel(double rating) {
    switch (rating.round()) {
      case 1:
        return '⭐ Very Poor';
      case 2:
        return '⭐⭐ Poor';
      case 3:
        return '⭐⭐⭐ Good';
      case 4:
        return '⭐⭐⭐⭐ Very Good';
      case 5:
        return '⭐⭐⭐⭐⭐ Excellent!';
      default:
        return '';
    }
  }

  // ============================================================
  // SHOW DISCOUNT INFO - WITH DISCOUNTED PRICE
  // ============================================================
  void _showDiscountInfo() {
    if (_isDisposed || _isDisposing) return;
    
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final discountController = TextEditingController(
      text: (_customerData?['off'] ?? 0).toString(),
    );
    final totalOrders = _customerData?['totalOrders'] ?? 0;
    final totalSpent = _customerData?['totalSpent'] ?? 0.0;
    final phoneController = TextEditingController(
      text: _customerData?['phone'] ?? '',
    );
    final locationController = TextEditingController(
      text: _customerData?['location'] ?? '',
    );
    final starRating = _customerData?['star'] ?? 0.0;
    final currentDiscount = _currentDiscount;
    
    // ✅ Calculate discounted price from last order
    final lastOrderAmount = _customerData?['lastOrderAmount'] ?? 0.0;
    final discountedAmount = DiscountService.applyDiscount(lastOrderAmount, currentDiscount);
    final savings = lastOrderAmount - discountedAmount;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.discount, color: Colors.purple),
                  SizedBox(width: 8),
                  Text('Discount & Profile Info'),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ✅ DISCOUNT DISPLAY WITH PRICE
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.purple.shade100, Colors.purple.shade50],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.purple.shade200),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.local_offer,
                                color: Colors.purple,
                                size: 32,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Your Discount',
                                      style: TextStyle(
                                        color: Colors.purple.shade700,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    Text(
                                      '${currentDiscount.toStringAsFixed(1)}% OFF',
                                      style: const TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.purple,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (lastOrderAmount > 0 && currentDiscount > 0) ...[
                            const Divider(),
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Original Price',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                      Text(
                                        'KES ${lastOrderAmount.toStringAsFixed(2)}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(
                                  Icons.arrow_forward,
                                  color: Colors.purple,
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        'You Pay',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.green.shade700,
                                        ),
                                      ),
                                      Text(
                                        'KES ${discountedAmount.toStringAsFixed(2)}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: Colors.green.shade700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              margin: const EdgeInsets.only(top: 8),
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.green.shade200),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.savings,
                                    color: Colors.green,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'You saved KES ${savings.toStringAsFixed(2)}!',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          if (currentDiscount == 0)
                            Container(
                              margin: const EdgeInsets.only(top: 8),
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'Place 3 orders this week to get discounts!',
                                style: TextStyle(
                                  fontWeight: FontWeight.w500,
                                  color: Colors.orange,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Rating display
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.amber.shade200),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.star, color: Colors.amber, size: 28),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Your Rating',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w500,
                                    fontSize: 12,
                                  ),
                                ),
                                Row(
                                  children: [
                                    Text(
                                      starRating.toStringAsFixed(1),
                                      style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.amber,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    const Text(
                                      '/ 5.0',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade100,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${(_customerData?['feedbackCount'] ?? 0)} reviews',
                              style: TextStyle(
                                color: Colors.amber.shade700,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Profile Edit
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Edit Your Profile Details',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: phoneController,
                            decoration: const InputDecoration(
                              labelText: 'Phone Number',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.phone),
                              hintText: 'Enter your phone number',
                              helperText: 'Format: 0712345678',
                            ),
                            keyboardType: TextInputType.phone,
                            onChanged: (value) {},
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: locationController,
                            decoration: const InputDecoration(
                              labelText: 'Location',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.location_on),
                              hintText: 'Enter your location',
                            ),
                            onChanged: (value) {},
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Discount tiers
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '🎯 Discount Tiers',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Colors.orange,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text('• 3 orders → 0.5% off'),
                          const Text('• 4 orders → 1.0% off'),
                          const Text('• 5 orders → 1.5% off'),
                          const Text('• 6 orders → 2.0% off'),
                          const Text('• 7+ orders → 2.5% off'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    if (mounted) Navigator.pop(context);
                  },
                  child: const Text('Close'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple,
                  ),
                  onPressed: () async {
                    if (_isDisposed || _isDisposing) return;
                    
                    try {
                      final newPhone = phoneController.text.trim();
                      final newLocation = locationController.text.trim();

                      final updates = <String, dynamic>{};
                      
                      if (newPhone.isNotEmpty && _isValidPhoneNumber(newPhone)) {
                        updates['phone'] = newPhone;
                      }
                      if (newLocation.isNotEmpty) {
                        updates['location'] = newLocation;
                      }

                      if (updates.isNotEmpty) {
                        await FirebaseFirestore.instance
                            .collection('customers')
                            .doc(user.uid)
                            .update(updates);

                        if (mounted && !_isDisposed && !_isDisposing) {
                          setState(() {
                            if (newPhone.isNotEmpty) _customerData?['phone'] = newPhone;
                            if (newLocation.isNotEmpty) _customerData?['location'] = newLocation;
                          });

                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('✅ Profile updated successfully!'),
                              backgroundColor: Colors.green,
                            ),
                          );
                          _debounceRefresh();
                        }
                      } else {
                        Navigator.pop(context);
                      }
                    } catch (e) {
                      if (mounted && !_isDisposed && !_isDisposing) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Error updating profile. Please try again.'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                  child: const Text('Save Changes'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ============================================================
  // BUILD METHOD - HIDDEN STATS WITH FRIENDLY COLORS
  // ============================================================
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('👤 My Profile'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (mounted && !_isDisposed && !_isDisposing) {
                Navigator.pushReplacementNamed(context, '/');
              }
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadCustomerData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ============================================================
                    // PROFILE CARD - With friendly gradient colors (bg-red-100 style)
                    // ============================================================
                    Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        width: double.infinity,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color(0xFFFFF5F5), // Very light red (bg-red-50)
                              Color(0xFFFFE8E8), // Light red (bg-red-100)
                              Color(0xFFFFD4D4), // Slightly deeper red
                              Color(0xFFFFF0F0), // Soft pink-red
                            ],
                          ),
                        ),
                        child: Column(
                          children: [
                            // ✅ Friendly profile avatar with gradient
                            Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0xFF4CAF50), // Green
                                    Color(0xFF2E7D32), // Dark Green
                                    Color(0xFF66BB6A), // Light Green
                                  ],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.green.withOpacity(0.4),
                                    blurRadius: 15,
                                    spreadRadius: 3,
                                  ),
                                ],
                              ),
                              child: CircleAvatar(
                                radius: 40,
                                backgroundColor: Colors.transparent,
                                child: Text(
                                  _getNameInitial(_customerData?['name']),
                                  style: const TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    shadows: [
                                      Shadow(
                                        color: Colors.black26,
                                        blurRadius: 4,
                                        offset: Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            // ✅ Friendly name with gradient text
                            ShaderMask(
                              shaderCallback: (bounds) => const LinearGradient(
                                colors: [
                                  Color(0xFF2E7D32), // Dark Green
                                  Color(0xFF4CAF50), // Green
                                  Color(0xFF66BB6A), // Light Green
                                ],
                              ).createShader(bounds),
                              child: Text(
                                _customerData?['name'] ?? 'Customer',
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _customerData?['email'] ?? user?.email ?? '',
                              style: TextStyle(
                                color: Colors.grey.shade700,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 12),
                            // ✅ Friendly stats chips with colors
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              alignment: WrapAlignment.center,
                              children: [
                                // Discount chip - Purple
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFF7B1FA2), // Purple
                                        Color(0xFF9C27B0),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(20),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.purple.withOpacity(0.3),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.local_offer,
                                        color: Colors.white,
                                        size: 14,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${_currentDiscount.toStringAsFixed(1)}% off',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Rating chip - Amber
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFFF9A825), // Amber
                                        Color(0xFFFF6F00),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(20),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.amber.withOpacity(0.3),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.star,
                                        color: Colors.white,
                                        size: 14,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${(_customerData?['star'] ?? 0.0).toStringAsFixed(1)}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Feedback count chip - Blue
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFF1565C0), // Blue
                                        Color(0xFF1E88E5),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(20),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.blue.withOpacity(0.3),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.comment,
                                        color: Colors.white,
                                        size: 14,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${_customerData?['feedbackCount'] ?? 0} reviews',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ============================================================
                    // QUICK ACTIONS - With friendly gradient colors
                    // ============================================================
                    Row(
                      children: [
                        Expanded(
                          child: _buildActionCard(
                            icon: Icons.shopping_cart,
                            label: 'Order Fuel',
                            color: Colors.green,
                            gradientColors: const [
                              Color(0xFFE8F5E9), // Very light green (bg-green-50)
                              Color(0xFFC8E6C9), // Light green (bg-green-100)
                              Color(0xFFA5D6A7),
                            ],
                            onTap: () {
                              if (_isDisposed || _isDisposing) return;
                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const HomeMapPage(),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildActionCard(
                            icon: Icons.star,
                            label: 'Give Feedback',
                            color: Colors.amber,
                            gradientColors: const [
                              Color(0xFFFFF8E1), // Very light amber (bg-amber-50)
                              Color(0xFFFFECB3), // Light amber (bg-amber-100)
                              Color(0xFFFFE082),
                            ],
                            onTap: _showFeedbackDialog,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildActionCard(
                            icon: Icons.discount,
                            label: 'Discount Info',
                            color: Colors.purple,
                            gradientColors: const [
                              Color(0xFFF3E5F5), // Very light purple (bg-purple-50)
                              Color(0xFFE1BEE7), // Light purple (bg-purple-100)
                              Color(0xFFCE93D8),
                            ],
                            onTap: _showDiscountInfo,
                          ),
                        ),
                      ],
                    ),

                    // ============================================================
                    // ORDER HISTORY SECTION - REMOVED FROM UI
                    // ============================================================
                    // ✅ ORDER HISTORY IS HIDDEN FROM UI
                    // ✅ _orderHistory is still loaded for calculations
                    // ✅ Discount calculations still work
                    // ✅ Total orders still tracked in background
                    
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required String label,
    required Color color,
    required List<Color> gradientColors,
    required VoidCallback onTap,
  }) {
    // ✅ Get the shade700 color from the color
    Color textColor;
    if (color == Colors.green) {
      textColor = Colors.green.shade700;
    } else if (color == Colors.amber) {
      textColor = Colors.amber.shade700;
    } else if (color == Colors.purple) {
      textColor = Colors.purple.shade700;
    } else {
      textColor = color;
    }

    return Card(
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: gradientColors,
            ),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withOpacity(0.2),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
