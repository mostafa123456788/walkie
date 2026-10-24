import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

class PacketType {
  static const int text = 1;
  static const int audio = 2;
}

class TextMessage {
  TextMessage({required this.from, required this.text, required this.mine})
      : at = DateTime.now();
  final String from;
  final String text;
  final bool mine;
  final DateTime at;
}

class AudioChunk {
  AudioChunk(this.from, this.data);
  final String from;
  final Uint8List data;
}

/// [0] type  [1] channel  [2..5] senderId  [6] nameLen  [7..] name  ثم الحمولة
class RadioService {
  RadioService({required this.name, this.channel = 1});

  static const int port = 45454;
  static const int _maxAudioSlice = 1000;

  final int myId = Random.secure().nextInt(0x7fffffff);
  String name;
  int channel;

  RawDatagramSocket? _socket;
  final _textCtrl = StreamController<TextMessage>.broadcast();
  final _audioCtrl = StreamController<AudioChunk>.broadcast();

  Stream<TextMessage> get onText => _textCtrl.stream;
  Stream<AudioChunk> get onAudio => _audioCtrl.stream;

  Future<void> start() async {
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      port,
      reuseAddress: true,
    );
    socket.broadcastEnabled = true;
    socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      Datagram? d;
      while ((d = socket.receive()) != null) {
        _handle(d!.data);
      }
    });
    _socket = socket;
  }

  void stop() {
    _socket?.close();
    _socket = null;
  }

  void sendText(String text) {
    final t = text.trim();
    if (t.isEmpty) return;
    _send(PacketType.text, Uint8List.fromList(utf8.encode(t)));
    _textCtrl.add(TextMessage(from: name, text: t, mine: true));
  }

  void sendAudio(Uint8List pcm) {
    for (var i = 0; i < pcm.length; i += _maxAudioSlice) {
      final end = min(i + _maxAudioSlice, pcm.length);
      _send(PacketType.audio, Uint8List.sublistView(pcm, i, end));
    }
  }

  void _send(int type, Uint8List payload) {
    final nameBytes = utf8.encode(name);
    final nameLen = min(nameBytes.length, 40);
    final b = BytesBuilder(copy: false)
      ..addByte(type)
      ..addByte(channel)
      ..add((ByteData(4)..setUint32(0, myId)).buffer.asUint8List())
      ..addByte(nameLen)
      ..add(nameBytes.sublist(0, nameLen))
      ..add(payload);
    _socket?.send(b.toBytes(), InternetAddress('255.255.255.255'), port);
  }

  void _handle(Uint8List data) {
    if (data.length < 7) return;
    final type = data[0];
    final ch = data[1];
    final id = ByteData.sublistView(data, 2, 6).getUint32(0);
    if (id == myId || ch != channel) return;
    final nameLen = data[6];
    if (data.length < 7 + nameLen) return;
    final from = utf8.decode(data.sublist(7, 7 + nameLen), allowMalformed: true);
    final payload = Uint8List.sublistView(data, 7 + nameLen);

    if (type == PacketType.text) {
      _textCtrl.add(TextMessage(
        from: from,
        text: utf8.decode(payload, allowMalformed: true),
        mine: false,
      ));
    } else if (type == PacketType.audio) {
      _audioCtrl.add(AudioChunk(from, Uint8List.fromList(payload)));
    }
  }
}
