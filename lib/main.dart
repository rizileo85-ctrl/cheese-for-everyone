import 'package:flutter/material.dart';
import 'package:flutter_chess_board/flutter_chess_board.dart';
import 'package:chess/chess.dart' as chess;
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:web_socket_channel/io.dart';

void main() {
  runApp(const CheeseApp());
}

class CheeseApp extends StatelessWidget {
  const CheeseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cheese for Everyone',
      theme: ThemeData(primarySwatch: Colors.indigo),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String playerName = "";

  void _editName() async {
    final controller = TextEditingController(text: playerName);
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Set Profile Name"),
        content: TextField(controller: controller),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text("Save"),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      setState(() => playerName = name);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Cheese for Everyone"),
        actions: [
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: _editName,
          )
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(playerName.isEmpty ? "Guest" : playerName,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const GamePage(mode: "local")),
                ),
                child: const Text("Play Local Two-Player"),
              ),
              ElevatedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const GamePage(mode: "ai")),
                ),
                child: const Text("Play vs AI"),
              ),
              ElevatedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const GamePage(mode: "assistant")),
                ),
                child: const Text("Play with Assistant"),
              ),
              ElevatedButton(
                onPressed: () {},
                child: const Text("Create Room / Join Room"),
              ),
              ElevatedButton(
                onPressed: () {},
                child: const Text("Explain Pieces"),
              ),
              ElevatedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const HistoryPage()),
                ),
                child: const Text("View Game History"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class GamePage extends StatefulWidget {
  final String mode; // local | ai | assistant
  const GamePage({super.key, required this.mode});

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> {
  final boardController = ChessBoardController();
  final FlutterTts tts = FlutterTts();
  final stt.SpeechToText speech = stt.SpeechToText();
  final chess.Chess game = chess.Chess();
  IOWebSocketChannel? channel;

  @override
  void initState() {
    super.initState();
    if (widget.mode == "ai" || widget.mode == "assistant") {
      channel = IOWebSocketChannel.connect("ws://localhost:8080");
    }
  }

  void sendMove(String move) {
    if (channel != null) {
      final fen = game.fen; // ✅ FIXED: getter used instead of function call
      if (widget.mode == "ai") {
        channel!.sink.add('{"type":"ai_move","fen":"$fen","level":"beginner"}');
      } else if (widget.mode == "assistant") {
        channel!.sink.add('{"type":"assistant_move","fen":"$fen"}');
      }
    }
  }

  void onMove() {
    final last = game.history.isNotEmpty ? game.history.last : "";
    if (last.isNotEmpty) {
      tts.speak("Move played: $last");
      if (widget.mode == "ai" || widget.mode == "assistant") {
        sendMove(last);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Mode: ${widget.mode}")),
      body: Column(
        children: [
          Expanded(
            child: ChessBoard(
              controller: boardController,
              boardColor: BoardColor.brown,
              boardOrientation: PlayerColor.white,
              onMove: () {
                game.load(boardController.getFen());
                onMove();
              },
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed: () => tts.speak("Explain Rook: moves straight lines horizontally or vertically"),
                child: const Text("Explain Rook"),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PGNViewPage(pgn: game.pgn()),
                    ),
                  );
                },
                child: const Text("View Game Replay"),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    channel?.sink.close();
    super.dispose();
  }
}

class PGNViewPage extends StatelessWidget {
  final String pgn;
  const PGNViewPage({super.key, required this.pgn});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Game Replay")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Text(pgn, style: const TextStyle(fontSize: 16)),
        ),
      ),
    );
  }
}

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Game History")),
      body: const Center(
        child: Text("Past games will be listed here (Firestore integration pending)."),
      ),
    );
  }
}