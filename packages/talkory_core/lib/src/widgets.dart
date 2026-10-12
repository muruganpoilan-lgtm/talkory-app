import 'package:flutter/material.dart';

/// Round profile picture (falls back to the first letter). [url] is a server path like /avatars/x.jpg.
/// Pass [ring] to draw a coloured ring around it (green = online).
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({super.key, required this.baseUrl, required this.name, this.url, this.radius = 28, this.ring});
  final String baseUrl, name;
  final String? url;
  final double radius;
  final Color? ring;

  @override
  Widget build(BuildContext context) {
    final avatar = CircleAvatar(
      radius: radius,
      backgroundImage: url == null ? null : NetworkImage('$baseUrl$url'),
      child: url == null ? Text(name.isEmpty ? '?' : name[0].toUpperCase(), style: TextStyle(fontSize: radius * 0.8)) : null,
    );
    if (ring == null) return avatar;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: ring!, width: 3)),
      child: avatar,
    );
  }
}
