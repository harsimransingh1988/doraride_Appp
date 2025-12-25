// lib/features/profile/vehicles_page.dart
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class VehiclesPage extends StatefulWidget {
  const VehiclesPage({super.key});

  @override
  State<VehiclesPage> createState() => _VehiclesPageState();
}

class _VehiclesPageState extends State<VehiclesPage> {
  static const kGreen = Color(0xFF279C56);
  static const kNavy = Color(0xFF180D3B); // 👉 DoraRide Blue/Navy

  final make = TextEditingController();
  final model = TextEditingController();
  final color = TextEditingController();
  final plate = TextEditingController();
  int seats = 4;

  String? _photoUrl;
  bool _uploading = false;
  bool _saving = false;
  bool _loadingVehicle = false;

  String? _editingDocId;
  int _vehicleCount = 0;

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      );

  @override
  void initState() {
    super.initState();
    _loadLastSavedVehicle();
  }

  // ---------------- LOAD LAST VEHICLE ----------------

  Future<void> _loadLastSavedVehicle() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      setState(() => _loadingVehicle = true);

      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('vehicles')
          .orderBy('updatedAt', descending: true)
          .limit(1)
          .get();

      if (snap.docs.isEmpty) {
        setState(() => _loadingVehicle = false);
        return;
      }

      final doc = snap.docs.first;
      final v = doc.data();

      setState(() {
        _editingDocId = doc.id;
        make.text = v['make'] ?? '';
        model.text = v['model'] ?? '';
        color.text = v['color'] ?? '';
        plate.text = v['plate'] ?? '';
        seats = v['seats'] ?? 4;
        _photoUrl = v['photoUrl'] ?? '';
        _loadingVehicle = false;
      });
    } catch (e) {
      setState(() => _loadingVehicle = false);
    }
  }

  // ---------------- NEW VEHICLE ----------------

  void _newVehicle() {
    if (_vehicleCount >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Maximum 5 vehicles allowed')),
      );
      return;
    }

    setState(() {
      _editingDocId = null;
      make.clear();
      model.clear();
      color.clear();
      plate.clear();
      seats = 4;
      _photoUrl = null;
    });
  }

  // ---------------- UPLOAD PHOTO ----------------

  Future<void> _pickAndUploadCarPhoto() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to upload a car photo.')),
      );
      return;
    }

    try {
      final picker = ImagePicker();
      final XFile? x = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (x == null) return;

      setState(() => _uploading = true);

      final Uint8List bytes = await x.readAsBytes();

      final safePlate = (plate.text.trim().isEmpty
              ? "unregistered"
              : plate.text.trim())
          .replaceAll('/', '_');

      final ref = FirebaseStorage.instance
          .ref("vehicles/${user.uid}/$safePlate/car.jpg");

      final uploadTask = ref.putData(
        bytes,
        SettableMetadata(contentType: "image/jpeg"),
      );
      await uploadTask;

      final url = await ref.getDownloadURL();

      if (!mounted) return;
      setState(() {
        _photoUrl = url;
        _uploading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Car photo uploaded! Remember to Save vehicle.'),
          duration: Duration(seconds: 2),
        ),
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: ${e.message ?? e.code}')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not upload photo: $e')),
      );
    }
  }

  // ---------------- SAVE VEHICLE ----------------

  Future<void> _saveVehicle() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (make.text.isEmpty ||
        model.text.isEmpty ||
        color.text.isEmpty ||
        plate.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Fill all fields")),
      );
      return;
    }

    try {
      setState(() => _saving = true);

      if (_editingDocId == null) {
        final countSnap = await FirebaseFirestore.instance
            .collection("users")
            .doc(user.uid)
            .collection("vehicles")
            .get();

        if (countSnap.docs.length >= 5) {
          setState(() => _saving = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Maximum 5 vehicles allowed")),
          );
          return;
        }
      }

      final id = _editingDocId ?? plate.text.trim();

      await FirebaseFirestore.instance
          .collection("users")
          .doc(user.uid)
          .collection("vehicles")
          .doc(id)
          .set(
        {
          "make": make.text.trim(),
          "model": model.text.trim(),
          "color": color.text.trim(),
          "plate": plate.text.trim(),
          "seats": seats,
          "photoUrl": _photoUrl ?? "",
          "updatedAt": FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      setState(() {
        _saving = false;
        _editingDocId = id;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Vehicle saved!")),
      );
    } catch (e) {
      setState(() => _saving = false);
    }
  }

  // ---------------- DELETE VEHICLE ----------------

  Future<void> _deleteVehicle(String id) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance
        .collection("users")
        .doc(user.uid)
        .collection("vehicles")
        .doc(id)
        .delete();

    if (_editingDocId == id) {
      _newVehicle();
    }
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: kGreen,
      appBar: AppBar(
        backgroundColor: kGreen,
        foregroundColor: Colors.white,
        title: const Text("Vehicles"),
        actions: [
          if (_vehicleCount < 5)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: ElevatedButton(
                onPressed: _newVehicle,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kNavy, // 🔵 YOUR BLUE COLOR
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  "Add New Vehicle",
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.only(right: 14),
              child: Center(
                child: Text(
                  "Max 5",
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ----- Photo Box -----
          GestureDetector(
            onTap: _uploading ? null : _pickAndUploadCarPhoto,
            child: Container(
              height: 150,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                image: _photoUrl != null && _photoUrl!.isNotEmpty
                    ? DecorationImage(
                        image: NetworkImage(_photoUrl!),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: _uploading
                  ? const Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(kNavy),
                      ),
                    )
                  : (_photoUrl == null || _photoUrl!.isEmpty
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.camera_alt_outlined, color: kNavy),
                            SizedBox(height: 8),
                            Text(
                              "Click here or upload a car picture",
                              style: TextStyle(color: kNavy),
                            ),
                          ],
                        )
                      : null),
            ),
          ),

          const SizedBox(height: 20),

          TextField(controller: make, decoration: _dec("Vehicle make")),
          const SizedBox(height: 12),

          TextField(controller: model, decoration: _dec("Model")),
          const SizedBox(height: 12),

          TextField(controller: color, decoration: _dec("Color")),
          const SizedBox(height: 12),

          TextField(controller: plate, decoration: _dec("License plate")),
          const SizedBox(height: 12),

          DropdownButtonFormField<int>(
            value: seats,
            decoration: _dec("Seats"),
            items: List.generate(8, (i) => i + 1)
                .map((v) => DropdownMenuItem(value: v, child: Text("$v seats")))
                .toList(),
            onChanged: (v) => setState(() => seats = v ?? seats),
          ),

          const SizedBox(height: 20),

          ElevatedButton(
            onPressed: _saving ? null : _saveVehicle,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: kNavy,
            ),
            child: _saving
                ? const CircularProgressIndicator()
                : const Text("Save vehicle"),
          ),

          const SizedBox(height: 30),

          const Text(
            "My vehicles",
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),

          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection("users")
                .doc(user?.uid)
                .collection("vehicles")
                .orderBy("updatedAt", descending: true)
                .snapshots(),
            builder: (context, snap) {
              if (!snap.hasData) return const SizedBox();

              final docs = snap.data!.docs;
              _vehicleCount = docs.length;

              return Column(
                children: docs.map((d) {
                  final v = d.data();

                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      onTap: () {
                        setState(() {
                          _editingDocId = d.id;
                          make.text = v['make'];
                          model.text = v['model'];
                          color.text = v['color'];
                          plate.text = v['plate'];
                          seats = v['seats'];
                          _photoUrl = v['photoUrl'];
                        });
                      },
                      leading: v['photoUrl'] != ""
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                v['photoUrl'],
                                width: 50,
                                height: 50,
                                fit: BoxFit.cover,
                              ),
                            )
                          : const Icon(Icons.car_repair),
                      title: Text("${v['make']} ${v['model']}"),
                      subtitle: Text(
                          "${v['color']} • ${v['plate']} • ${v['seats']} seats"),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _deleteVehicle(d.id),
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}
