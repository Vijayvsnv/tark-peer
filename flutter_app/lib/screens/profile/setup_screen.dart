import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../data/locations.dart';
import '../../services/profile_service.dart';
import '../../widgets/custom_button.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _nameCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _occupationCtrl = TextEditingController();
  final _stateFreeCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _profileService = ProfileService();
  String? _gender;
  String? _sector;
  String? _country;
  String? _state;
  String? _motherTongue;
  bool _loading = false;
  bool _initialLoading = true;

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  Future<void> _loadExisting() async {
    try {
      final p = await _profileService.getMyProfile();
      if (p != null && mounted) {
        _nameCtrl.text = p.name;
        if (p.age != null) _ageCtrl.text = '${p.age}';
        if (p.bio != null) _bioCtrl.text = p.bio!;
        if (p.occupation != null) _occupationCtrl.text = p.occupation!;
        setState(() {
          _gender = p.gender;
          _sector = _sectorInList(p.sector);
          _country = _countryInMap(p.country);
          _state = _stateForCountry(_country, p.state);
          if (_country != null && !kCountryStates[_country]!.contains(p.state) && p.state != null) {
            _stateFreeCtrl.text = p.state!;
          }
          _motherTongue = (p.motherTongue != null && kLanguages.contains(p.motherTongue))
              ? p.motherTongue
              : null;
          _initialLoading = false;
        });
      } else {
        if (mounted) setState(() => _initialLoading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _initialLoading = false);
    }
  }

  String? _sectorInList(String? s) => (s != null && kSectors.contains(s)) ? s : null;
  String? _countryInMap(String? c) => (c != null && kCountryStates.containsKey(c)) ? c : null;
  String? _stateForCountry(String? country, String? s) {
    if (country == null || s == null) return null;
    final list = kCountryStates[country] ?? const [];
    return list.contains(s) ? s : null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_gender == null) {
      _showError('Please select your gender');
      return;
    }
    if (_country == null) {
      _showError('Please select your country');
      return;
    }

    final states = kCountryStates[_country] ?? const [];
    String? finalState;
    if (states.isEmpty) {
      final txt = _stateFreeCtrl.text.trim();
      if (txt.isEmpty) {
        _showError('Please enter your state/region');
        return;
      }
      finalState = txt;
    } else {
      if (_state == null) {
        _showError('Please select your state');
        return;
      }
      finalState = _state;
    }

    setState(() => _loading = true);
    try {
      await _profileService.updateProfile(
        name: _nameCtrl.text.trim(),
        age: int.parse(_ageCtrl.text),
        gender: _gender,
        bio: _bioCtrl.text.trim().isEmpty ? null : _bioCtrl.text.trim(),
        occupation: _occupationCtrl.text.trim().isEmpty ? null : _occupationCtrl.text.trim(),
        sector: _sector,
        country: _country,
        state: finalState,
        motherTongue: _motherTongue,
      );
      if (!mounted) return;
      context.go('/home');
    } catch (e) {
      if (!mounted) return;
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_initialLoading) {
      return const Scaffold(
        backgroundColor: kBackground,
        body: Center(child: CircularProgressIndicator(color: kPrimary)),
      );
    }
    final states = _country == null ? const <String>[] : (kCountryStates[_country] ?? const <String>[]);
    final hasStateList = states.isNotEmpty;

    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(title: const Text('Setup Profile')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Tell us about yourself',
                style: TextStyle(color: kTextPrimary, fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text('This helps us find better matches', style: TextStyle(color: kTextSecondary)),
              const SizedBox(height: 32),
              TextFormField(
                controller: _nameCtrl,
                style: const TextStyle(color: kTextPrimary),
                decoration: const InputDecoration(
                  labelText: 'Display Name',
                  prefixIcon: Icon(Icons.person_outline, color: kTextSecondary),
                ),
                validator: (v) => v!.trim().length >= 2 ? null : 'Min 2 characters',
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _ageCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: kTextPrimary),
                decoration: const InputDecoration(
                  labelText: 'Age',
                  prefixIcon: Icon(Icons.cake_outlined, color: kTextSecondary),
                ),
                validator: (v) {
                  final age = int.tryParse(v ?? '');
                  if (age == null || age < 13 || age > 100) return 'Enter valid age (13-100)';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _gender,
                dropdownColor: Colors.white,
                style: const TextStyle(color: kTextPrimary),
                decoration: const InputDecoration(
                  labelText: 'Gender',
                  prefixIcon: Icon(Icons.people_outline, color: kTextSecondary),
                ),
                items: const [
                  DropdownMenuItem(value: 'male', child: Text('Male')),
                  DropdownMenuItem(value: 'female', child: Text('Female')),
                  DropdownMenuItem(value: 'other', child: Text('Other')),
                ],
                onChanged: (v) => setState(() => _gender = v),
              ),
              const SizedBox(height: 24),
              const Text(
                'Location',
                style: TextStyle(color: kTextPrimary, fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _country,
                isExpanded: true,
                dropdownColor: Colors.white,
                style: const TextStyle(color: kTextPrimary),
                decoration: const InputDecoration(
                  labelText: 'Country',
                  prefixIcon: Icon(Icons.public_outlined, color: kTextSecondary),
                ),
                items: kCountryStates.keys
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) => setState(() {
                  _country = v;
                  _state = null;
                  _stateFreeCtrl.clear();
                }),
              ),
              const SizedBox(height: 16),
              if (_country == null)
                _disabledStatePlaceholder()
              else if (hasStateList)
                DropdownButtonFormField<String>(
                  value: _state,
                  isExpanded: true,
                  dropdownColor: Colors.white,
                  style: const TextStyle(color: kTextPrimary),
                  decoration: const InputDecoration(
                    labelText: 'State / Region',
                    prefixIcon: Icon(Icons.location_on_outlined, color: kTextSecondary),
                  ),
                  items: states
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (v) => setState(() => _state = v),
                )
              else
                TextFormField(
                  controller: _stateFreeCtrl,
                  style: const TextStyle(color: kTextPrimary),
                  decoration: const InputDecoration(
                    labelText: 'State / Region',
                    prefixIcon: Icon(Icons.location_on_outlined, color: kTextSecondary),
                  ),
                ),
              const SizedBox(height: 24),
              const Text(
                'Work',
                style: TextStyle(color: kTextPrimary, fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _occupationCtrl,
                style: const TextStyle(color: kTextPrimary),
                decoration: const InputDecoration(
                  labelText: 'Occupation (e.g., Software Engineer, Student)',
                  prefixIcon: Icon(Icons.work_outline, color: kTextSecondary),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _sector,
                isExpanded: true,
                dropdownColor: Colors.white,
                style: const TextStyle(color: kTextPrimary),
                decoration: const InputDecoration(
                  labelText: 'Sector / Industry',
                  prefixIcon: Icon(Icons.business_center_outlined, color: kTextSecondary),
                ),
                items: kSectors
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (v) => setState(() => _sector = v),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _motherTongue,
                isExpanded: true,
                dropdownColor: Colors.white,
                style: const TextStyle(color: kTextPrimary),
                decoration: const InputDecoration(
                  labelText: 'Mother Tongue',
                  prefixIcon: Icon(Icons.translate_outlined, color: kTextSecondary),
                ),
                items: kLanguages
                    .map((l) => DropdownMenuItem(value: l, child: Text(l)))
                    .toList(),
                onChanged: (v) => setState(() => _motherTongue = v),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _bioCtrl,
                maxLines: 3,
                style: const TextStyle(color: kTextPrimary),
                decoration: const InputDecoration(
                  labelText: 'Bio (optional)',
                  prefixIcon: Icon(Icons.info_outline, color: kTextSecondary),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 32),
              CustomButton(label: 'Save & Continue', onPressed: _save, isLoading: _loading),
            ],
          ),
        ),
      ),
    );
  }

  Widget _disabledStatePlaceholder() {
    return Opacity(
      opacity: 0.5,
      child: IgnorePointer(
        child: TextFormField(
          enabled: false,
          decoration: const InputDecoration(
            labelText: 'State / Region',
            hintText: 'Select country first',
            prefixIcon: Icon(Icons.location_on_outlined, color: kTextSecondary),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _ageCtrl.dispose();
    _bioCtrl.dispose();
    _occupationCtrl.dispose();
    _stateFreeCtrl.dispose();
    super.dispose();
  }
}
