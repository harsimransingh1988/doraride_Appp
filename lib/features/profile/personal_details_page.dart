// lib/features/profile/personal_details_page.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PersonalDetailsPage extends StatefulWidget {
  const PersonalDetailsPage({super.key});

  @override
  State<PersonalDetailsPage> createState() => _PersonalDetailsPageState();
}

class _PersonalDetailsPageState extends State<PersonalDetailsPage> {
  static const kGreen = Color(0xFF279C56);
  static const kNavy  = Color(0xFF180D3B);

  final _first = TextEditingController(text: '');
  final _last  = TextEditingController(text: '');
  final _desc  = TextEditingController(text: 'Hello! I love carpooling and meeting new people.');

  String _month = 'Jan';
  int _day = 1;
  int _year = 1990;
  String _gender = 'Male';
  bool _isDriver = false;

  final _months = const ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadFromFirestore();
  }

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _desc.dispose();
    super.dispose();
  }

  // ---------- UI helpers ----------
  InputDecoration _dec(String hint) => InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
  );

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      t,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 16,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  // ---------- Data I/O ----------
  int _monthToIndex(String m) => _months.indexOf(m) + 1;
  String _indexToMonth(int i) => _months[(i - 1).clamp(0, 11)];

  Future<void> _loadFromFirestore() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final snap = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final data = snap.data() ?? {};

      _first.text = (data['firstName'] as String?)?.trim() ?? _first.text;
      _last.text  = (data['lastName']  as String?)?.trim() ?? _last.text;
      _desc.text  = (data['bio']       as String?)?.trim() ?? _desc.text;

      _gender     = (data['gender']    as String?)?.trim() ?? _gender;
      _isDriver   = (data['isDriver']  as bool?) ?? _isDriver;

      // Prefer dobTs (Timestamp). Fallback to structured map {year,month,day}.
      DateTime? dob;
      final dobTs = data['dobTs'];
      if (dobTs is Timestamp) {
        dob = dobTs.toDate();
      } else {
        final dobMap = data['dob'];
        if (dobMap is Map) {
          final y = (dobMap['year'] as num?)?.toInt();
          final m = (dobMap['month'] as num?)?.toInt();
          final d = (dobMap['day'] as num?)?.toInt();
          if (y != null && m != null && d != null) {
            dob = DateTime(y, m, d);
          }
        }
      }

      if (dob != null) {
        _year = dob.year;
        _month = _indexToMonth(dob.month);
        _day = dob.day;
      }
    } catch (_) {
      // ignore & keep defaults
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _calcAge(DateTime dob) {
    final now = DateTime.now();
    var age = now.year - dob.year;
    if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) {
      age--;
    }
    return age;
  }

  Future<void> _save() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No user session')),
      );
      return;
    }

    final dob = DateTime(_year, _monthToIndex(_month), _day);
    final age = _calcAge(dob);

    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'firstName': _first.text.trim(),
        'lastName' : _last.text.trim(),
        'bio'      : _desc.text.trim(),
        'gender'   : _gender,
        'isDriver' : _isDriver,

        // Save DOB as Timestamp (authoritative) and as parts (back-compat)
        'dobTs'    : Timestamp.fromDate(dob),
        'dob'      : {'year': dob.year, 'month': dob.month, 'day': dob.day},

        'age'      : age,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Optional: keep auth displayName in sync
      final name = '${_first.text.trim()} ${_last.text.trim()}'.trim();
      if (name.isNotEmpty) {
        await FirebaseAuth.instance.currentUser?.updateDisplayName(name);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final years = List<int>.generate(100, (i) => DateTime.now().year - i);
    final days  = List<int>.generate(31, (i) => i + 1);

    return Scaffold(
      backgroundColor: kGreen,
      appBar: AppBar(
        title: const Text('Personal details'),
        backgroundColor: kGreen,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label('First Name'),
                  TextField(controller: _first, decoration: _dec('Enter your first name')),

                  const SizedBox(height: 14),
                  _label('Last Name'),
                  TextField(controller: _last, decoration: _dec('Enter your last name')),

                  const SizedBox(height: 14),
                  _label('Date of birth'),
                  Row(
                    children: [
                      Expanded(
                        flex: 4,
                        child: DropdownButtonFormField<String>(
                          value: _month,
                          items: _months.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                          onChanged: (v) => setState(() => _month = v ?? _month),
                          decoration: _dec('Month'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 3,
                        child: DropdownButtonFormField<int>(
                          value: _day,
                          items: days.map((d) => DropdownMenuItem(value: d, child: Text('$d'))).toList(),
                          onChanged: (v) => setState(() => _day = v ?? _day),
                          decoration: _dec('Day'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 4,
                        child: DropdownButtonFormField<int>(
                          value: _year,
                          items: years.map((y) => DropdownMenuItem(value: y, child: Text('$y'))).toList(),
                          onChanged: (v) => setState(() => _year = v ?? _year),
                          decoration: _dec('Year'),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),
                  _label('Description'),
                  TextField(
                    controller: _desc,
                    maxLines: 5,
                    decoration: _dec('Write something about yourself'),
                  ),

                  const SizedBox(height: 14),
                  _label('Gender'),
                  DropdownButtonFormField<String>(
                    value: _gender,
                    items: const ['Male', 'Female', 'Other']
                        .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                        .toList(),
                    onChanged: (v) => setState(() => _gender = v ?? _gender),
                    decoration: _dec('Select gender'),
                  ),

                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Switch(
                        value: _isDriver,
                        onChanged: (v) => setState(() => _isDriver = v),
                        activeColor: Colors.white,
                        activeTrackColor: kNavy,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        "I'm a driver",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: kNavy,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Update profile',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
