import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../services/room_service.dart';
import '../../widgets/custom_button.dart';

class JoinRoomScreen extends StatefulWidget {
  const JoinRoomScreen({super.key});

  @override
  State<JoinRoomScreen> createState() => _JoinRoomScreenState();
}

class _JoinRoomScreenState extends State<JoinRoomScreen> {
  final _roomService = RoomService();
  final _codeCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final room = await _roomService.joinRoom(_codeCtrl.text.trim().toUpperCase());
      if (mounted) context.pushReplacement('/rooms/lobby', extra: room);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: kBackground,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: kTextPrimary),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Join Room',
          style: TextStyle(color: kTextPrimary, fontWeight: FontWeight.w700, fontSize: 18),
        ),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 32),
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: const Color(0xFF7C3AED).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.vpn_key_rounded, color: Color(0xFF7C3AED), size: 40),
              ),
              const SizedBox(height: 24),
              const Text(
                'Enter Room Code',
                style: TextStyle(color: kTextPrimary, fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Ask your friend for the 6-character\nroom code to join their room.',
                textAlign: TextAlign.center,
                style: TextStyle(color: kTextSecondary, fontSize: 14),
              ),
              const SizedBox(height: 36),
              TextFormField(
                controller: _codeCtrl,
                maxLength: 6,
                textAlign: TextAlign.center,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                  UpperCaseTextFormatter(),
                ],
                style: const TextStyle(
                  color: kTextPrimary,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 10,
                ),
                validator: (v) {
                  if (v == null || v.trim().length != 6) {
                    return 'Enter the complete 6-character code';
                  }
                  return null;
                },
                decoration: InputDecoration(
                  hintText: 'XXXXXX',
                  hintStyle: TextStyle(
                    color: kTextMuted.withOpacity(0.4),
                    fontSize: 32,
                    letterSpacing: 10,
                    fontWeight: FontWeight.bold,
                  ),
                  filled: true,
                  fillColor: kSurface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: kBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: kBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: Color(0xFF7C3AED), width: 2),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: kDanger, width: 1.5),
                  ),
                  focusedErrorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: kDanger, width: 1.5),
                  ),
                  counterText: '',
                ),
                onChanged: (v) {
                  if (v.length == 6) FocusScope.of(context).unfocus();
                },
              ),
              const SizedBox(height: 32),
              CustomButton(
                label: 'Join Room',
                isLoading: _loading,
                onPressed: _join,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue old, TextEditingValue next) {
    return next.copyWith(text: next.text.toUpperCase());
  }
}
