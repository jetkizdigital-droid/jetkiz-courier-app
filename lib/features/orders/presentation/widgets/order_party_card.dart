import 'package:flutter/material.dart';

class OrderPartyCard extends StatelessWidget {
  const OrderPartyCard({
    super.key,
    required this.title,
    required this.name,
    required this.address,
    required this.phone,
    required this.onCallTap,
    required this.onRouteTap,
    this.comment,
    this.leaveAtDoor = false,
  });

  final String title;
  final String? name;
  final String? address;
  final String? phone;
  final VoidCallback onCallTap;
  final VoidCallback onRouteTap;
  final String? comment;
  final bool leaveAtDoor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if ((name ?? '').trim().isNotEmpty)
                Text(
                  name!,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Colors.black,
                  ),
                ),
              if ((address ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                _Line(icon: Icons.location_on_outlined, text: address!),
              ],
              if ((phone ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                _Line(icon: Icons.phone_outlined, text: phone!),
              ],
              if ((comment ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    comment!,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF475467),
                    ),
                  ),
                ),
              ],
              if (leaveAtDoor) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7ED),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Оставить у двери',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFF59E0B),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onCallTap,
                      icon: const Icon(Icons.phone_outlined),
                      label: const Text('Позвонить'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onRouteTap,
                      icon: const Icon(Icons.navigation_outlined),
                      label: const Text('Маршрут'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: const Color(0xFF667085)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Color(0xFF475467),
            ),
          ),
        ),
      ],
    );
  }
}
