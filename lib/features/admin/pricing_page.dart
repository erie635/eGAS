import 'package:flutter/material.dart';

class PricingPage extends StatelessWidget {
  const PricingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pricing Management'),
        backgroundColor: Colors.green,
      ),
      body: const Center(
        child: Text(
          'Pricing Page - Under Construction',
          style: TextStyle(fontSize: 18),
        ),
      ),
    );
  }
}
