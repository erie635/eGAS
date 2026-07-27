
import 'package:cloud_firestore/cloud_firestore.dart';

class DriversPage extends StatelessWidget {
  const DriversPage({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: FirebaseFirestore.instance.collection('drivers').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data!.docs;

        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final data = docs[i].data();

            return Card(
              child: ListTile(
                leading: const Icon(Icons.local_shipping),
                title: Text(data['name'] ?? 'Driver'),
                subtitle: Text("Status: ${data['status'] ?? 'offline'}"),
                trailing: Text(
                  "KSh ${data['price'] ?? 0}",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            );
          },
        );
      },
    );
  }
}