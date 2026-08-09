import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class StationsPage extends StatelessWidget {
  const StationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: FirebaseFirestore.instance.collection('stations').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data!.docs;

        return ListView(
          children: docs.map((doc) {
            final data = doc.data();

            return Card(
              child: ListTile(
                title: Text(data['name'] ?? 'Station'),
                subtitle: Text("Fuel available: ${data['fuel'] ?? 0} L"),
                trailing: const Icon(Icons.local_gas_station),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}
