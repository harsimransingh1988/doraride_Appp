import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../common/repos/wallet_repository.dart';
import '../../common/models/wallet_models.dart';

class BankSetupPage extends StatefulWidget {
  const BankSetupPage({super.key});

  @override
  State<BankSetupPage> createState() => _BankSetupPageState();
}

class _BankSetupPageState extends State<BankSetupPage> {
  // DoraRide styling
  static const kGreen = Color(0xFF279C56);
  static const kBg = Color(0xFFF4F7F5);

  final repo = WalletRepository();

  // ---- Controllers (BLANK by default) ----
  final name = TextEditingController();
  final bankName = TextEditingController();
  final acct = TextEditingController();
  final ifsc = TextEditingController();

  final email = TextEditingController();
  final phone = TextEditingController();

  // Address fields
  final address1 = TextEditingController();
  final address2 = TextEditingController();
  final city = TextEditingController();
  final stateProv = TextEditingController();
  final postal = TextEditingController();

  // Notes/description
  final description = TextEditingController();

  // Country (with search)
  String selectedCountry = ''; // empty until user picks
  String _countryQuery = '';

  bool loading = false;

  // Keys for saving extra metadata (address etc.)
  static const _kBankName = 'wallet_bank_name';
  static const _kCountry = 'wallet_bank_country';
  static const _kAddr1 = 'wallet_bank_addr1';
  static const _kAddr2 = 'wallet_bank_addr2';
  static const _kCity = 'wallet_bank_city';
  static const _kState = 'wallet_bank_state';
  static const _kPostal = 'wallet_bank_postal';
  static const _kDesc = 'wallet_bank_desc';

  @override
  void initState() {
    super.initState();
    _loadExtraPrefs();
  }

  @override
  void dispose() {
    name.dispose();
    bankName.dispose();
    acct.dispose();
    ifsc.dispose();
    email.dispose();
    phone.dispose();
    address1.dispose();
    address2.dispose();
    city.dispose();
    stateProv.dispose();
    postal.dispose();
    description.dispose();
    super.dispose();
  }

  Future<void> _loadExtraPrefs() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      bankName.text = p.getString(_kBankName) ?? bankName.text;
      selectedCountry = p.getString(_kCountry) ?? selectedCountry;
      address1.text = p.getString(_kAddr1) ?? address1.text;
      address2.text = p.getString(_kAddr2) ?? address2.text;
      city.text = p.getString(_kCity) ?? city.text;
      stateProv.text = p.getString(_kState) ?? stateProv.text;
      postal.text = p.getString(_kPostal) ?? postal.text;
      description.text = p.getString(_kDesc) ?? description.text;
      // Core repo-backed fields (if user saved them previously)
      // Note: We only overwrite if repo has data — otherwise leave blank.
    });
    final info = await repo.getBankInfo();
    if (!mounted || info == null) return;
    setState(() {
      name.text = info.accountHolder;
      acct.text = info.accountNumberMasked;
      ifsc.text = info.ifscOrRouting;
      email.text = info.email;
      phone.text = info.phone;
    });
  }

  Future<void> _saveExtraPrefs() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kBankName, bankName.text.trim());
    await p.setString(_kCountry, selectedCountry);
    await p.setString(_kAddr1, address1.text.trim());
    await p.setString(_kAddr2, address2.text.trim());
    await p.setString(_kCity, city.text.trim());
    await p.setString(_kState, stateProv.text.trim());
    await p.setString(_kPostal, postal.text.trim());
    await p.setString(_kDesc, description.text.trim());
  }

  Future<void> _save() async {
    setState(() => loading = true);

    // Save base info via repository (works with your current model)
    final info = BankInfo(
      accountHolder: name.text.trim(),
      accountNumberMasked: acct.text.trim(),
      ifscOrRouting: ifsc.text.trim(),
      email: email.text.trim(),
      phone: phone.text.trim(),
    );
    await repo.saveBankInfo(info);

    // Save additional address fields locally
    await _saveExtraPrefs();

    if (!mounted) return;
    setState(() => loading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Bank details saved')),
    );
    Navigator.of(context).pop();
  }

  InputDecoration _dec(String placeholder) => InputDecoration(
        hintText: placeholder,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kGreen,
        foregroundColor: Colors.white,
        title: const Text('Bank details'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          const Text(
            'Your bank details',
            style: TextStyle(
              color: kGreen,
              fontWeight: FontWeight.w900,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: 12),

          // --- Account/Bank info ---
          TextField(controller: name, decoration: _dec('Account holder name')),
          const SizedBox(height: 12),
          TextField(controller: bankName, decoration: _dec('Bank name')),
          const SizedBox(height: 12),
          TextField(controller: acct, decoration: _dec('Account number (masked)')),
          const SizedBox(height: 12),
          TextField(controller: ifsc, decoration: _dec('IFSC / Routing / BIC / SWIFT')),
          const SizedBox(height: 12),

          // --- Country (searchable) ---
          InkWell(
            onTap: _openCountryPicker,
            child: InputDecorator(
              decoration: _dec('Country'),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      selectedCountry.isEmpty ? 'Select country' : selectedCountry,
                      style: TextStyle(
                        color: selectedCountry.isEmpty
                            ? Colors.black54
                            : Colors.black87,
                      ),
                    ),
                  ),
                  const Icon(Icons.search, color: Colors.black54),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // --- Address block ---
          TextField(controller: address1, decoration: _dec('Address line 1')),
          const SizedBox(height: 12),
          TextField(controller: address2, decoration: _dec('Address line 2 (optional)')),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: TextField(controller: city, decoration: _dec('City'))),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                    controller: stateProv,
                    decoration: _dec('State / Province / Region')),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(controller: postal, decoration: _dec('Postal / ZIP code')),
          const SizedBox(height: 12),

          // --- Contact for payouts ---
          TextField(controller: email, decoration: _dec('Payout email address')),
          const SizedBox(height: 12),
          TextField(controller: phone, decoration: _dec('Payout phone number')),
          const SizedBox(height: 12),

          // --- Notes/Description ---
          TextField(
            controller: description,
            maxLines: 3,
            decoration: _dec('Any additional information related to your bank details'),
          ),

          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: loading ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: kGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                textStyle:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              child: Text(loading ? 'Saving…' : 'Save'),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- Country picker (searchable, no extra packages) ----------
  Future<void> _openCountryPicker() async {
    _countryQuery = '';
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final searchCtrl = TextEditingController();
        List<String> list = countries;

        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            void filter(String q) {
              setSheetState(() {
                _countryQuery = q;
                list = countries
                    .where((c) => c.toLowerCase().contains(q.toLowerCase()))
                    .toList();
              });
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
                  top: 8,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: searchCtrl,
                      onChanged: filter,
                      decoration: InputDecoration(
                        hintText: 'Search country',
                        prefixIcon: const Icon(Icons.search),
                        filled: true,
                        fillColor: Colors.grey.shade100,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: list.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final c = list[i];
                          return ListTile(
                            title: Text(c),
                            trailing: c == selectedCountry
                                ? const Icon(Icons.check, color: kGreen)
                                : null,
                            onTap: () {
                              setState(() => selectedCountry = c);
                              Navigator.of(ctx).pop();
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ------------- Full countries list -------------
  final List<String> countries = const [
    'Afghanistan','Albania','Algeria','Andorra','Angola','Antigua and Barbuda','Argentina','Armenia',
    'Australia','Austria','Azerbaijan','Bahamas','Bahrain','Bangladesh','Barbados','Belarus','Belgium',
    'Belize','Benin','Bhutan','Bolivia','Bosnia and Herzegovina','Botswana','Brazil','Brunei','Bulgaria',
    'Burkina Faso','Burundi','Cabo Verde','Cambodia','Cameroon','Canada','Central African Republic','Chad',
    'Chile','China','Colombia','Comoros','Congo (Congo-Brazzaville)','Costa Rica','Croatia','Cuba','Cyprus',
    'Czech Republic','Democratic Republic of the Congo','Denmark','Djibouti','Dominica','Dominican Republic',
    'Ecuador','Egypt','El Salvador','Equatorial Guinea','Eritrea','Estonia','Eswatini','Ethiopia','Fiji',
    'Finland','France','Gabon','Gambia','Georgia','Germany','Ghana','Greece','Grenada','Guatemala','Guinea',
    'Guinea-Bissau','Guyana','Haiti','Honduras','Hungary','Iceland','India','Indonesia','Iran','Iraq',
    'Ireland','Israel','Italy','Jamaica','Japan','Jordan','Kazakhstan','Kenya','Kiribati','Kuwait','Kyrgyzstan',
    'Laos','Latvia','Lebanon','Lesotho','Liberia','Libya','Liechtenstein','Lithuania','Luxembourg','Madagascar',
    'Malawi','Malaysia','Maldives','Mali','Malta','Marshall Islands','Mauritania','Mauritius','Mexico',
    'Micronesia','Moldova','Monaco','Mongolia','Montenegro','Morocco','Mozambique','Myanmar (Burma)','Namibia',
    'Nauru','Nepal','Netherlands','New Zealand','Nicaragua','Niger','Nigeria','North Korea','North Macedonia',
    'Norway','Oman','Pakistan','Palau','Palestine','Panama','Papua New Guinea','Paraguay','Peru','Philippines',
    'Poland','Portugal','Qatar','Romania','Russia','Rwanda','Saint Kitts and Nevis','Saint Lucia',
    'Saint Vincent and the Grenadines','Samoa','San Marino','Sao Tome and Principe','Saudi Arabia','Senegal',
    'Serbia','Seychelles','Sierra Leone','Singapore','Slovakia','Slovenia','Solomon Islands','Somalia',
    'South Africa','South Korea','South Sudan','Spain','Sri Lanka','Sudan','Suriname','Sweden','Switzerland',
    'Syria','Taiwan','Tajikistan','Tanzania','Thailand','Timor-Leste','Togo','Tonga','Trinidad and Tobago',
    'Tunisia','Turkey','Turkmenistan','Tuvalu','Uganda','Ukraine','United Arab Emirates','United Kingdom',
    'United States','Uruguay','Uzbekistan','Vanuatu','Vatican City','Venezuela','Vietnam','Yemen','Zambia',
    'Zimbabwe',
  ];
}
