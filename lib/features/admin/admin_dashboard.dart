import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _selectedIndex = 0;
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _vehicleTypeController = TextEditingController();
  final _plateController = TextEditingController();
  final _priceController = TextEditingController();

  final List<Widget> _pages = [
    const DriversManagementPage(),
    const PricingManagementPage(),
    const OrdersManagementPage(),
  ];

  final List<String> _titles = ['Drivers', 'Pricing', 'Orders'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Admin • ${_titles[_selectedIndex]}'), backgroundColor: Colors.green),
      drawer: Drawer(
        child: ListView(
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: Colors.green),
              child: Column(
                children: [
                  Icon(Icons.admin_panel_settings, size: 50, color: Colors.white),
                  SizedBox(height: 8),
                  Text('E-Fuel Admin', style: TextStyle(color: Colors.white, fontSize: 18)),
                ],
              ),
            ),
            ListTile(leading: const Icon(Icons.people), title: const Text('Manage Drivers'), onTap: () => setState(() => _selectedIndex = 0)),
            ListTile(leading: const Icon(Icons.attach_money), title: const Text('Pricing'), onTap: () => setState(() => _selectedIndex = 1)),
            ListTile(leading: const Icon(Icons.shopping_cart), title: const Text('Orders'), onTap: () => setState(() => _selectedIndex = 2)),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Logout'),
              onTap: () async {
                await FirebaseAuth.instance.signOut();
                if (mounted) Navigator.pushReplacementNamed(context, '/');
              },
            ),
          ],
        ),
      ),
      body: _pages[_selectedIndex],
      floatingActionButton: _selectedIndex == 0
          ? FloatingActionButton(
              onPressed: _showAddDriverDialog,
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  void _showAddDriverDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add New Driver'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'Driver Name'),),
                const SizedBox(height: 8),
                TextField(controller: _phoneController, decoration: const InputDecoration(labelText: 'Phone Number'),),
                const SizedBox(height: 8),
                TextField(controller: _vehicleTypeController, decoration: const InputDecoration(labelText: 'Vehicle Type (e.g., Fuel Truck)'),),
                const SizedBox(height: 8),
                TextField(controller: _plateController, decoration: const InputDecoration(labelText: 'Number Plate'),),
                const SizedBox(height: 8),
                TextField(controller: _priceController, decoration: const InputDecoration(labelText: 'Price per KM'), keyboardType: TextInputType.number),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                await FirebaseFirestore.instance.collection('drivers').add({
                  'name': _nameController.text,
                  'phone': _phoneController.text,
                  'vehicleType': _vehicleTypeController.text,
                  'numberPlate': _plateController.text,
                  'pricePerKm': double.parse(_priceController.text),
                  'isOnline': false,
                  'lat': 0,
                  'lng': 0,
                  'createdAt': FieldValue.serverTimestamp(),
                });
                _nameController.clear();
                _phoneController.clear();
                _vehicleTypeController.clear();
                _plateController.clear();
                _priceController.clear();
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Driver added successfully')));
              },
              child: const Text('Add Driver'),
            ),
          ],
        );
      },
    );
  }
}

class DriversManagementPage extends StatelessWidget {
  const DriversManagementPage({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: FirebaseFirestore.instance.collection('drivers').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final drivers = snapshot.data!.docs;
        if (drivers.isEmpty) return const Center(child: Text('No drivers added yet'));
        return ListView.builder(
          itemCount: drivers.length,
          itemBuilder: (context, index) {
            final driver = drivers[index];
            return Card(
              margin: const EdgeInsets.all(8),
              child: ListTile(
                leading: const Icon(Icons.local_shipping, color: Colors.green),
                title: Text(driver['name']),
                subtitle: Text('${driver['vehicleType']} • ${driver['numberPlate']} • KES ${driver['pricePerKm']}/km'),
                trailing: Switch(
                  value: driver['isOnline'] ?? false,
                  onChanged: (val) {
                    driver.reference.update({'isOnline': val});
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class PricingManagementPage extends StatelessWidget {
  const PricingManagementPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('Pricing Management - Coming Soon'),
    );
  }
}

class OrdersManagementPage extends StatelessWidget {
  const OrdersManagementPage({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: FirebaseFirestore.instance.collection('orders').orderBy('createdAt', descending: true).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final orders = snapshot.data!.docs;
        if (orders.isEmpty) return const Center(child: Text('No orders yet'));
        return ListView.builder(
          itemCount: orders.length,
          itemBuilder: (context, index) {
            final order = orders[index];
            return Card(
              margin: const EdgeInsets.all(8),
              child: ListTile(
                leading: const Icon(Icons.shopping_cart, color: Colors.green),
                title: Text('${order['fuelType']} - ${order['litres']}L'),
                subtitle: Text('Driver: ${order['driverName']}\nTotal: KES ${order['totalPrice']}\nStatus: ${order['status']}'),
                trailing: order['status'] == 'pending'
                    ? ElevatedButton(
                        onPressed: () => order.reference.update({'status': 'accepted'}),
                        child: const Text('Accept'),
                      )
                    : Chip(label: Text(order['status']), backgroundColor: Colors.green.shade100),
              ),
            );
          },
        );
      },
    );
  }
}

// Add this import at top of admin_dashboard.dart
import 'package:firebase_auth/firebase_auth.dart';
