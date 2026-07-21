import 'package:flutter/material.dart';

import '../services/capsule_address_service.dart';
import '../utils/hivra_id_format.dart';

class InvitationRecipientField extends StatelessWidget {
  final TextEditingController controller;
  final List<CapsuleAddressCard> contacts;
  final String? errorText;
  final ValueChanged<String>? onChanged;

  const InvitationRecipientField({
    super.key,
    required this.controller,
    required this.contacts,
    this.errorText,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (contacts.isNotEmpty) ...[
          DropdownButtonFormField<String>(
            decoration: const InputDecoration(
              labelText: 'Saved capsule contact',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.contact_page_outlined),
            ),
            hint: const Text('Choose contact'),
            items: [
              for (final card in contacts)
                DropdownMenuItem(
                  value: card.rootKey,
                  child: Text(HivraIdFormat.short(card.rootKey)),
                ),
            ],
            onChanged: (value) {
              if (value == null) return;
              controller.text = value;
              onChanged?.call(value);
            },
          ),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: 'Capsule contact',
            hintText: 'Paste a contact card, QR payload, or h...',
            border: const OutlineInputBorder(),
            errorText: errorText,
          ),
          minLines: 1,
          maxLines: 5,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
