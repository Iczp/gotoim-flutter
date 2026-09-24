import 'package:flutter/material.dart';

/// 性别徽章小组件
class ProfileGenderBadge extends StatelessWidget {
  const ProfileGenderBadge({required this.gender, super.key});

  final int gender; // 1: 男, 2: 女

  @override
  Widget build(BuildContext context) {
    if (gender == 0) return const SizedBox.shrink();
    final isFemale = gender == 2;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1.5),
      decoration: BoxDecoration(
        color: isFemale ? const Color(0xFFF99788) : const Color(0xFF32BBFB),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Icon(
        isFemale ? Icons.female : Icons.male,
        size: 11.5,
        color: Colors.white,
      ),
    );
  }
}
