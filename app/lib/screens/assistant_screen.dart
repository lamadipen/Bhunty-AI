import 'package:flutter/material.dart';

import '../ai/answers.dart';
import '../ai/assistant_service.dart';
import '../app_scope.dart';
import '../core/money.dart';
import '../core/qty.dart';
import '../data/proposed_action.dart';
import '../theme/theme.dart';
import '../widgets/common.dart';

enum _Status { pending, yes, no }

sealed class _Msg {}

class _UserMsg extends _Msg {
  _UserMsg(this.text);
  final String text;
}

class _AnswerMsg extends _Msg {
  _AnswerMsg(this.answer);
  Answer answer;
}

class _ConfirmMsg extends _Msg {
  _ConfirmMsg(this.action);
  final ProposedAction action;
  _Status status = _Status.pending;
}

/// "Talk to Bhunte": questions are answered in code; changes need a ✓ tap.
class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final List<_Msg> _msgs = [];
  bool _listening = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _msgs
        ..add(_UserMsg('आज कति बिक्यो?'))
        ..add(_AnswerMsg(answerQuery(const QueryIntent(QueryMetric.salesToday), context.readStore)));
    }
  }

  Future<void> _talk() async {
    if (_listening) return;
    final store = context.readStore;
    setState(() => _listening = true);
    final heard = await context.assistant.listen(VoiceContext.chat);
    if (!mounted) return;
    setState(() {
      _listening = false;
      _msgs.add(_UserMsg(heard.transcript));
      switch (heard.intent) {
        case QueryIntent q:
          _msgs.add(_AnswerMsg(answerQuery(q, store)));
        case ActionIntent(:final action) when store.validate(action) == null:
          _msgs.add(_ConfirmMsg(action));
        case ActionIntent():
        case UnclearIntent():
          _msgs.add(_AnswerMsg(const TextAnswer('बुझिनँ। फेरि भन्नुस् न।')));
      }
    });
  }

  void _resolve(_ConfirmMsg m, bool yes) {
    final store = context.readStore;
    if (yes) {
      final problem = store.validate(m.action);
      if (problem != null) {
        showToast(context, problem);
        return;
      }
      store.apply(m.action);
    }
    setState(() => m.status = yes ? _Status.yes : _Status.no);
  }

  @override
  Widget build(BuildContext context) {
    context.store; // rebuild confirm cards when balances change
    final reversed = _msgs.reversed.toList();
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                ScreenHeader(
                  title: 'भुन्टे',
                  subtitle: 'तपाईंको हिसाब सहायक',
                  subtitleColor: BColors.green,
                  badge: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: Image.asset('assets/brand/bhunte-logo.png', width: 44, height: 44),
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    reverse: true,
                    padding: const EdgeInsets.all(14),
                    itemCount: reversed.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (c, i) => _bubble(reversed[i]),
                  ),
                ),
                Container(
                  decoration: const BoxDecoration(
                    color: BColors.white,
                    border: Border(top: BorderSide(color: BColors.line)),
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                  child: Column(
                    children: [
                      const Text(
                        'जे पनि सोध्नुस्: बिक्री, स्टक, उधारो',
                        style: TextStyle(fontSize: 14, color: BColors.inkSoft),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          RoundIconButton(
                            icon: Icons.photo_camera_outlined,
                            label: 'फोटो पठाउनुस्',
                            size: 60,
                            border: BColors.line,
                            onPressed: () => showToast(context, 'फोटो पठाउने सुविधा चाँडै आउँदैछ'),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: BigButton(
                              label: 'थिचेर बोल्नुस्',
                              icon: Icons.mic_none_rounded,
                              color: BColors.orange,
                              height: 76,
                              radius: 38,
                              onPressed: _talk,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_listening)
              const BusyOverlay(icon: Icons.mic_none_rounded, title: 'सुन्दैछु…', subtitle: 'छोडेपछि पठाइन्छ'),
          ],
        ),
      ),
    );
  }

  Widget _bubble(_Msg m) {
    return switch (m) {
      _UserMsg(:final text) => Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: BColors.green,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(6),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.graphic_eq_rounded, color: Color(0xFFBFE3CC), size: 22),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    '“$text”',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: BColors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      _AnswerMsg(:final answer) => _BotBubble(child: _answer(m, answer)),
      _ConfirmMsg() => _BotBubble(
        borderColor: switch (m.status) {
          _Status.pending => BColors.orange,
          _Status.yes => BColors.green,
          _Status.no => BColors.line,
        },
        child: _confirm(m),
      ),
    };
  }

  Widget _answer(_AnswerMsg m, Answer a) {
    switch (a) {
      case TextAnswer(:final text, :final offerOrderList):
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(text, style: const TextStyle(fontSize: 17, height: 1.4)),
            if (offerOrderList) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  _Chip(
                    label: 'हुन्छ',
                    filled: true,
                    onTap: () => setState(() {
                      m.answer = TextAnswer(text);
                      _msgs.add(_AnswerMsg(const TextAnswer('अर्डर लिस्ट तयार भयो। हिसाबमा हेर्न सकिन्छ।')));
                    }),
                  ),
                  _Chip(label: 'पछि', onTap: () => setState(() => m.answer = TextAnswer(text))),
                ],
              ),
            ],
          ],
        );
      case StatAnswer(:final stats):
        final top = stats.topItems.isEmpty ? null : stats.topItems.first;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('आजको बिक्री', style: TextStyle(fontSize: 16, color: BColors.inkSoft)),
            Text(
              formatRs(stats.totalPaisa),
              style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w800, height: 1.1),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _StatTile(
                    label: 'बिक्री',
                    value: '${stats.saleCount} पटक',
                    bg: BColors.greenTint,
                    fg: BColors.greenDark,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StatTile(
                    label: 'धेरै बिकेको',
                    value: top == null ? '—' : '${top.product.nameNe} ×${formatQty(top.qtyMilli)}',
                    bg: BColors.goldTint,
                    fg: BColors.gold,
                  ),
                ),
              ],
            ),
          ],
        );
    }
  }

  Widget _confirm(_ConfirmMsg m) {
    final store = context.readStore;
    final action = m.action;
    final (String initial, String title, String amount, String after) = switch (action) {
      RecordCredit(:final customerId, :final amountPaisa) => (
        store.customer(customerId).initial,
        '${store.customer(customerId).name} · उधारो',
        '+ ${formatRs(amountPaisa)}',
        m.status == _Status.pending
            ? 'नयाँ बाँकी: ${formatRs(store.customer(customerId).balancePaisa + amountPaisa)}'
            : 'बाँकी: ${formatRs(store.customer(customerId).balancePaisa)}',
      ),
      RecordPayment(:final customerId, :final amountPaisa) => (
        store.customer(customerId).initial,
        '${store.customer(customerId).name} · तिर्यो',
        '− ${formatRs(amountPaisa)}',
        'बाँकी: ${formatRs(store.customer(customerId).balancePaisa)}',
      ),
      AddStock(:final lines) => ('स्ट', 'स्टक थप', '${lines.length} सामान', ''),
      AddToCart() => ('', '', '', ''),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('यो लेखुँ?', style: TextStyle(fontSize: 16, color: BColors.inkSoft)),
        const SizedBox(height: 8),
        Row(
          children: [
            LetterTile(letter: initial, bg: BColors.warnBg, ink: BColors.warnInk, size: 48, circle: true),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, height: 1.15)),
                  Text(
                    amount,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: BColors.orange),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (after.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(after, style: const TextStyle(fontSize: 15, color: BColors.inkSoft)),
        ],
        const SizedBox(height: 10),
        switch (m.status) {
          _Status.pending => ConfirmButtons(height: 56, onNo: () => _resolve(m, false), onYes: () => _resolve(m, true)),
          _Status.yes => const _StatusLine(
            icon: Icons.check_rounded,
            text: 'लेखियो · खातामा',
            color: BColors.greenDark,
          ),
          _Status.no => const _StatusLine(icon: Icons.close_rounded, text: 'रद्द गरियो', color: BColors.inkSoft),
        },
      ],
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.icon, required this.text, required this.color});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color),
        ),
      ],
    );
  }
}

class _BotBubble extends StatelessWidget {
  const _BotBubble({required this.child, this.borderColor = BColors.line});

  final Widget child;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: 0.88,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: BColors.white,
            border: Border.all(color: borderColor, width: borderColor == BColors.line ? 1 : 2),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
              bottomRight: Radius.circular(20),
              bottomLeft: Radius.circular(6),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value, required this.bg, required this.fg});

  final String label;
  final String value;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: fg)),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: fg),
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.onTap, this.filled = false});

  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: BigButton(
        label: label,
        height: 44,
        radius: 22,
        fontSize: 17,
        outlineColor: filled ? null : BColors.line,
        foreground: filled ? BColors.white : BColors.ink,
        onPressed: onTap,
      ),
    );
  }
}
