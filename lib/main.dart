import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:record/record.dart';

import 'radio_service.dart';

void main() => runApp(const WalkieApp());

class WalkieApp extends StatelessWidget {
  const WalkieApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'لاسلكي',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF2E7D32),
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const WalkieScreen(),
    );
  }
}

class WalkieScreen extends StatefulWidget {
  const WalkieScreen({super.key});

  @override
  State<WalkieScreen> createState() => _WalkieScreenState();
}

class _WalkieScreenState extends State<WalkieScreen> {
  static const int _sampleRate = 16000;

  late final RadioService _radio;
  final AudioRecorder _rec = AudioRecorder();
  final FlutterSoundPlayer _player = FlutterSoundPlayer();
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<TextMessage> _messages = [];

  StreamSubscription<Uint8List>? _micSub;
  bool _talking = false;
  bool _playerReady = false;
  String? _speaker;
  Timer? _speakerTimer;
  String? _error;

  @override
  void initState() {
    super.initState();
    _radio = RadioService(name: 'صاحبي ${DateTime.now().millisecond}');
    _init();
  }

  Future<void> _init() async {
    try {
      await _player.openPlayer();
      await _radio.start();
      _radio.onText.listen((m) {
        setState(() => _messages.add(m));
        _scrollDown();
      });
      _radio.onAudio.listen(_onAudio);
    } catch (e) {
      setState(() => _error = 'مشكلة في التشغيل: $e');
    }
  }

  Future<void> _onAudio(AudioChunk c) async {
    if (_talking) return;
    if (!_playerReady) {
      _playerReady = true;
      await _player.startPlayerFromStream(
        codec: Codec.pcm16,
        numChannels: 1,
        sampleRate: _sampleRate,
        interleaved: true,
        bufferSize: 4096,
      );
    }
    await _player.feedUint8FromStream(c.data);
    setState(() => _speaker = c.from);
    _speakerTimer?.cancel();
    _speakerTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _speaker = null);
    });
  }

  Future<void> _startTalking() async {
    if (_talking) return;
    if (!await _rec.hasPermission()) {
      setState(() => _error = 'لازم تسمح للتطبيق باستخدام الميكروفون');
      return;
    }
    setState(() {
      _talking = true;
      _error = null;
    });
    final stream = await _rec.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: _sampleRate,
      numChannels: 1,
    ));
    _micSub = stream.listen(_radio.sendAudio);
  }

  Future<void> _stopTalking() async {
    if (!_talking) return;
    await _micSub?.cancel();
    _micSub = null;
    await _rec.stop();
    if (mounted) setState(() => _talking = false);
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  void _sendText() {
    _radio.sendText(_input.text);
    _input.clear();
  }

  Future<void> _openSettings() async {
    final nameCtrl = TextEditingController(text: _radio.name);
    var ch = _radio.channel;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('الإعدادات'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'اسمك'),
              ),
              const SizedBox(height: 16),
              Text('القناة: $ch'),
              Slider(
                min: 1,
                max: 16,
                divisions: 15,
                value: ch.toDouble(),
                label: '$ch',
                onChanged: (v) => setLocal(() => ch = v.round()),
              ),
              const Text('لازم كل الصحاب يكونوا على نفس القناة.',
                  style: TextStyle(fontSize: 12)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                final n = nameCtrl.text.trim();
                setState(() {
                  if (n.isNotEmpty) _radio.name = n;
                  _radio.channel = ch;
                });
                Navigator.pop(ctx);
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _speakerTimer?.cancel();
    _micSub?.cancel();
    _rec.dispose();
    _player.closePlayer();
    _radio.stop();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('لاسلكي • قناة ${_radio.channel}'),
        actions: [
          IconButton(icon: const Icon(Icons.settings), onPressed: _openSettings),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_error != null)
              MaterialBanner(
                content: Text(_error!),
                actions: [
                  TextButton(
                    onPressed: () => setState(() => _error = null),
                    child: const Text('تمام'),
                  ),
                ],
              ),
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.all(12),
                itemCount: _messages.length,
                itemBuilder: (_, i) {
                  final m = _messages[i];
                  return Align(
                    alignment:
                        m.mine ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: m.mine
                            ? cs.primaryContainer
                            : cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!m.mine)
                            Text(m.from,
                                style: TextStyle(
                                    fontSize: 11, color: cs.primary)),
                          Text(m.text),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            SizedBox(
              height: 28,
              child: Center(
                child: Text(
                  _speaker != null
                      ? '🔊 $_speaker بيتكلم...'
                      : (_talking ? '🎙️ إنت بتتكلم...' : ''),
                  style: TextStyle(color: cs.primary),
                ),
              ),
            ),
            Listener(
              onPointerDown: (_) => _startTalking(),
              onPointerUp: (_) => _stopTalking(),
              onPointerCancel: (_) => _stopTalking(),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: _talking ? 150 : 130,
                height: _talking ? 150 : 130,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _talking ? Colors.redAccent : cs.primary,
                  boxShadow: _talking
                      ? [
                          BoxShadow(
                              color: Colors.redAccent.withOpacity(0.5),
                              blurRadius: 24,
                              spreadRadius: 6)
                        ]
                      : null,
                ),
                child: Icon(_talking ? Icons.mic : Icons.mic_none,
                    size: 56, color: Colors.white),
              ),
            ),
            const SizedBox(height: 4),
            const Text('اضغط واستمر وتكلم', style: TextStyle(fontSize: 12)),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendText(),
                      decoration: InputDecoration(
                        hintText: 'اكتب رسالة...',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sendText,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
