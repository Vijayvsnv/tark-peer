import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/theme.dart';
import '../data/avatars.dart';
import '../services/profile_service.dart';

/// Bottom sheet that lets the user either upload a real photo or pick one
/// of the preset avatars. Returns the resulting avatar URL (from Supabase
/// Storage for uploads, from DiceBear for presets) via [Navigator.pop].
class AvatarPickerSheet extends StatefulWidget {
  const AvatarPickerSheet({super.key});

  @override
  State<AvatarPickerSheet> createState() => _AvatarPickerSheetState();
}

class _AvatarPickerSheetState extends State<AvatarPickerSheet> {
  final _picker = ImagePicker();
  final _profileService = ProfileService();
  bool _uploading = false;
  bool _showingAvatars = false;

  Future<void> _pickAndUpload(ImageSource source) async {
    try {
      final xfile = await _picker.pickImage(
        source: source,
        imageQuality: 70,
        maxWidth: 512,
        maxHeight: 512,
      );
      if (xfile == null) return;

      setState(() => _uploading = true);
      final url = await _profileService.uploadAvatar(File(xfile.path));
      if (!mounted) return;
      Navigator.pop(context, url);
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: _uploading ? _uploadingView() : (_showingAvatars ? _avatarGridView() : _menuView()),
      ),
    );
  }

  Widget _uploadingView() {
    return const SizedBox(
      height: 200,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: kPrimary),
            SizedBox(height: 14),
            Text('Uploading…', style: TextStyle(color: kTextSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _menuView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(color: kBorder, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(height: 18),
        const Text(
          'Change profile picture',
          style: TextStyle(color: kTextPrimary, fontSize: 17, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 18),
        _menuTile(
          icon: Icons.photo_library_outlined,
          label: 'Upload from Gallery',
          onTap: () => _pickAndUpload(ImageSource.gallery),
        ),
        const SizedBox(height: 10),
        _menuTile(
          icon: Icons.camera_alt_outlined,
          label: 'Take a Photo',
          onTap: () => _pickAndUpload(ImageSource.camera),
        ),
        const SizedBox(height: 10),
        _menuTile(
          icon: Icons.emoji_emotions_outlined,
          label: 'Choose an Avatar',
          onTap: () => setState(() => _showingAvatars = true),
        ),
      ],
    );
  }

  Widget _menuTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: kSurface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: kPrimary.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: kPrimary, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: kTextPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right, color: kTextSecondary, size: 22),
            ],
          ),
        ),
      ),
    );
  }

  Widget _avatarGridView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: kTextPrimary),
              onPressed: () => setState(() => _showingAvatars = false),
            ),
            const Expanded(
              child: Text(
                'Pick an avatar',
                style: TextStyle(color: kTextPrimary, fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 48),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 400,
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1,
            ),
            itemCount: kPresetAvatars.length,
            itemBuilder: (_, i) {
              final url = kPresetAvatars[i];
              return GestureDetector(
                onTap: () => Navigator.pop(context, url),
                child: Container(
                  decoration: BoxDecoration(
                    color: kSurface,
                    shape: BoxShape.circle,
                  ),
                  child: ClipOval(
                    child: CachedNetworkImage(
                      imageUrl: url,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: kPrimary),
                        ),
                      ),
                      errorWidget: (_, __, ___) =>
                          const Icon(Icons.person, color: kTextSecondary),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
