import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kiit_ui/kiit_ui.dart';

/// The composer pinned to the bottom of a topic room.
///
/// Details that matter in practice: it grows to 5 lines then scrolls, it sends
/// on the keyboard action without dismissing focus, and the send button only
/// animates in when there is something to send. A disabled-looking button that
/// does nothing is worse than no button at all.
class MessageComposer extends StatefulWidget {
  const MessageComposer({
    super.key,
    required this.topicTitle,
    required this.onSend,
  });

  final String topicTitle;
  final void Function(String text) onSend;

  @override
  State<MessageComposer> createState() => _MessageComposerState();
}

class _MessageComposerState extends State<MessageComposer> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final has = _controller.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSend(text);
    _controller.clear();
    // Keep focus: people send several short messages in a row in a live room.
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.viewInsetsOf(context).bottom;
    return Container(
      decoration: const BoxDecoration(
        color: PulsePalette.deepObsidian,
        border: Border(top: BorderSide(color: PulsePalette.borderGrey)),
      ),
      padding: EdgeInsets.fromLTRB(12, 9, 12, 9 + insets * 0),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: PulsePalette.elevatedSurface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: PulsePalette.borderGrey),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                child: TextField(
                  controller: _controller,
                  focusNode: _focus,
                  minLines: 1,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.newline,
                  keyboardType: TextInputType.multiline,
                  inputFormatters: [LengthLimitingTextInputFormatter(500)],
                  style: PulseType.body(14)
                      .copyWith(color: PulsePalette.textPrimary),
                  cursorColor: PulsePalette.kiitEmerald,
                  decoration: InputDecoration(
                    isDense: true,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    hintText: 'Reply in #${widget.topicTitle}',
                    hintMaxLines: 1,
                    hintStyle: PulseType.body(13.5)
                        .copyWith(color: PulsePalette.textTertiary),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            AnimatedScale(
              scale: _hasText ? 1 : 0.85,
              duration: PulseMotion.fast,
              curve: PulseMotion.emphasis,
              child: AnimatedOpacity(
                opacity: _hasText ? 1 : 0.4,
                duration: PulseMotion.fast,
                child: GestureDetector(
                  onTap: _hasText ? _send : null,
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: _hasText
                          ? PulsePalette.kiitEmerald
                          : PulsePalette.raisedSurface,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.arrow_upward_rounded,
                      size: 19,
                      color: _hasText
                          ? const Color(0xFF00160A)
                          : PulsePalette.textTertiary,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
