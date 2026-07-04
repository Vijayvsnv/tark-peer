import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../data/avatars.dart';

/// Bottom sheet that shows the preset avatar grid. Picking one pops the
/// sheet with the chosen avatar URL.
class AvatarPickerSheet extends StatelessWidget {
  const AvatarPickerSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: kBorder, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 18),
            const Text(
              'Pick an avatar',
              style: TextStyle(color: kTextPrimary, fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'This will be your profile picture',
              style: TextStyle(color: kTextSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: size.height * 0.55,
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
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
                              width: 22,
                              height: 22,
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
        ),
      ),
    );
  }
}
