import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
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
  final _formKey = GlobalKey<FormState>();
  final _profileService = ProfileService();
  String? _gender;
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
        setState(() {
          _gender = p.gender;
          _initialLoading = false;
        });
      } else {
        if (mounted) setState(() => _initialLoading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _initialLoading = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_gender == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select your gender'), backgroundColor: Colors.red),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      await _profileService.updateProfile(
        name: _nameCtrl.text.trim(),
        age: int.parse(_ageCtrl.text),
        gender: _gender,
        bio: _bioCtrl.text.trim().isEmpty ? null : _bioCtrl.text.trim(),
      );
      if (!mounted) return;
      context.go('/home');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_initialLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F0A1E),
        body: Center(child: CircularProgressIndicator(color: Color(0xFF7C3AED))),
      );
    }
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
                dropdownColor: kSurface,
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
              const SizedBox(height: 16),
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

  @override
  void dispose() {
    _nameCtrl.dispose();
    _ageCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }
}
