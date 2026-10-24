import 'package:flutter/material.dart';

import '../theme/theme.dart';
import 'common.dart';
import 'number_pad.dart';

/// Optional supplier and bill details for a delivery (R11). Suppliers are
/// identified by phone number; supplier records come later.
class DeliveryInfo {
  const DeliveryInfo({this.supplierName, this.supplierPhone, this.billNo});

  final String? supplierName;
  final String? supplierPhone;
  final String? billNo;

  bool get isEmpty => (supplierName ?? '').isEmpty && (supplierPhone ?? '').isEmpty && (billNo ?? '').isEmpty;

  /// "राम ट्रेडर्स · 9812345678 · बिल 1452"
  String get summary => [
    if ((supplierName ?? '').isNotEmpty) supplierName!,
    if ((supplierPhone ?? '').isNotEmpty) supplierPhone!,
    if ((billNo ?? '').isNotEmpty) 'बिल $billNo',
  ].join(' · ');
}

/// "+ सप्लायर / बिल नं." line that opens the form; shows the summary once filled.
class DeliveryInfoButton extends StatelessWidget {
  const DeliveryInfoButton({super.key, required this.info, required this.onChanged});

  final DeliveryInfo info;
  final ValueChanged<DeliveryInfo> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      key: const ValueKey('delivery-info'),
      style: TextButton.styleFrom(alignment: Alignment.centerLeft, padding: const EdgeInsets.symmetric(vertical: 10)),
      icon: Icon(info.isEmpty ? Icons.add_rounded : Icons.storefront_outlined, color: BColors.inkSoft),
      label: Text(
        info.isEmpty ? 'सप्लायर / बिल नं. (नभए पनि हुन्छ)' : info.summary,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 16,
          color: info.isEmpty ? BColors.inkSoft : BColors.ink,
          fontWeight: info.isEmpty ? FontWeight.w400 : FontWeight.w700,
        ),
      ),
      onPressed: () async {
        final next = await showBhunteSheet<DeliveryInfo>(context, (_) => _DeliveryInfoSheet(initial: info));
        if (next != null) onChanged(next);
      },
    );
  }
}

class _DeliveryInfoSheet extends StatefulWidget {
  const _DeliveryInfoSheet({required this.initial});

  final DeliveryInfo initial;

  @override
  State<_DeliveryInfoSheet> createState() => _DeliveryInfoSheetState();
}

class _DeliveryInfoSheetState extends State<_DeliveryInfoSheet> {
  late final _name = TextEditingController(text: widget.initial.supplierName);
  late final _bill = TextEditingController(text: widget.initial.billNo);
  late String _phone = widget.initial.supplierPhone ?? '';
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _bill.dispose();
    super.dispose();
  }

  Future<void> _editPhone() async {
    FocusScope.of(context).unfocus();
    final text = await showNumberPad(context, title: 'सप्लायरको फोन नम्बर', initial: _phone, maxDigits: 10);
    if (text != null) setState(() => _phone = text);
  }

  void _save() {
    if (_phone.isNotEmpty && (_phone.length < 7 || _phone.length > 10)) {
      setState(() => _error = 'फोन नम्बर ७ देखि १० अङ्कको हुन्छ');
      return;
    }
    Navigator.pop(
      context,
      DeliveryInfo(supplierName: _name.text.trim(), supplierPhone: _phone, billNo: _bill.text.trim()),
    );
  }

  InputDecoration _decoration(String hint) => InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: BColors.white,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: BColors.line),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('सप्लायर / बिल', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const Text('सबै नभरे पनि हुन्छ', style: TextStyle(fontSize: 15, color: BColors.inkSoft)),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('supplier-name'),
          controller: _name,
          style: const TextStyle(fontSize: 18),
          decoration: _decoration('सप्लायरको नाम'),
        ),
        const SizedBox(height: 8),
        PadField(
          key: const ValueKey('supplier-phone'),
          label: 'सप्लायरको फोन',
          value: _phone.isEmpty ? '—' : _phone,
          onTap: _editPhone,
        ),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('bill-no'),
          controller: _bill,
          style: const TextStyle(fontSize: 18),
          decoration: _decoration('बिल नं.'),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _error!,
              style: const TextStyle(fontSize: 15, color: BColors.warnInk, fontWeight: FontWeight.w700),
            ),
          ),
        const SizedBox(height: 14),
        BigButton(label: 'ठीक छ', trailingIcon: Icons.check_rounded, onPressed: _save),
      ],
    );
  }
}
