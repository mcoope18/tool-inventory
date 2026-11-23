import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'theme.dart';

final SpeechToText _stt = SpeechToText();
bool _sttReady = false;

/// Opens a sheet that listens and shows the words live. Returns the final
/// text (editable before it's used), or null if cancelled.
Future<String?> listenSheet(BuildContext context, {String title = 'Tell me about it', String hint = ''}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: kSurface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (_) => _VoiceSheet(title: title, hint: hint),
  );
}

class _VoiceSheet extends StatefulWidget {
  final String title;
  final String hint;
  const _VoiceSheet({required this.title, required this.hint});
  @override
  State<_VoiceSheet> createState() => _VoiceSheetState();
}

class _VoiceSheetState extends State<_VoiceSheet> {
  final _ctrl = TextEditingController();
  bool _listening = false;
  String _status = '';

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    if (!_sttReady) {
      _sttReady = await _stt.initialize(
        onStatus: (s) {
          if (!mounted) return;
          if (s == 'done' || s == 'notListening') setState(() => _listening = false);
        },
        onError: (e) {
          if (!mounted) return;
          setState(() {
            _listening = false;
            _status = 'Didn’t catch that. Tap the mic to try again, or type it.';
          });
        },
      );
    }
    if (!_sttReady) {
      setState(() => _status = 'Voice isn’t available. Allow the microphone in Settings, or type it below.');
      return;
    }
    final before = _ctrl.text.trim();
    setState(() {
      _listening = true;
      _status = '';
    });
    await _stt.listen(
      onResult: (r) {
        if (!mounted) return;
        final words = r.recognizedWords;
        _ctrl.text = before.isEmpty ? words : '$before $words';
        _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
        setState(() {});
      },
      listenFor: const Duration(seconds: 60),
      pauseFor: const Duration(seconds: 5),
      listenOptions: SpeechListenOptions(partialResults: true, listenMode: ListenMode.dictation),
    );
  }

  Future<void> _stop() async {
    await _stt.stop();
    if (mounted) setState(() => _listening = false);
  }

  @override
  void dispose() {
    _stt.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: Container(width: 40, height: 5, decoration: BoxDecoration(color: const Color(0xFF3A3F46), borderRadius: BorderRadius.circular(3)))),
          const SizedBox(height: 14),
          Text(widget.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          if (widget.hint.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(widget.hint, style: const TextStyle(fontSize: 13, color: kText2)),
          ],
          const SizedBox(height: 14),
          Row(children: [
            _MicButton(listening: _listening, onTap: _listening ? _stop : _start),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _status.isNotEmpty ? _status : (_listening ? 'Listening… talk normally.' : 'Tap the mic to add more.'),
                style: TextStyle(fontSize: 13, color: _listening ? kAmber : kText2, fontWeight: FontWeight.w600),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            minLines: 3,
            maxLines: 6,
            style: const TextStyle(fontSize: 16, height: 1.4),
            decoration: inputDeco('What you say shows up here. You can fix it before saving.'),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), style: ghostBtn(), child: const Text('Cancel'))),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: () async {
                  await _stt.stop();
                  if (context.mounted) Navigator.pop(context, _ctrl.text.trim());
                },
                style: amberBtn(),
                child: const Text('Use this'),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

class _MicButton extends StatelessWidget {
  final bool listening;
  final VoidCallback onTap;
  const _MicButton({required this.listening, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: kAmber,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 56,
          height: 56,
          child: Icon(listening ? Icons.stop_rounded : Icons.mic_rounded, color: Colors.black, size: 28),
        ),
      ),
    );
  }
}
