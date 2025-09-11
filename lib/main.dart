import 'package:flutter/material.dart';
import 'package:flutter_chess_board/flutter_chess_board.dart';
import 'package:chess/chess.dart' as chess;
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';

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

  bool listening = false;

  @override
  void initState() {
    super.initState();
  }

  void onMove() {
    final fen = boardController.getFen();
    game.load(fen);
    setState(() {});

    if (game.history.isNotEmpty) {
      final last = game.history.last.toString();
      tts.speak("Move played: $last");
    }
  }

  Future<void> startListening() async {
    final available = await speech.initialize();
    if (!available) {
      debugPrint("Speech not available");
      return;
    }
    setState(() => listening = true);

    speech.listen(
      onResult: (result) {
        final spoken = result.recognizedWords.toLowerCase();
        if (spoken.contains("to")) {
          final parts = spoken.split("to");
          if (parts.length == 2) {
            final from = parts[0].trim();
            final to = parts[1].trim();
            final move = {"from": from, "to": to};
            final applied = game.move(move);
            if (applied != null) {
              boardController.loadFen(game.fen);
              setState(() {});
              tts.speak("You played $from to $to");
            } else {
              tts.speak("Invalid move");
            }
          }
        }
      },
    );
  }

  void stopListening() {
    speech.stop();
    setState(() => listening = false);
  }

  @override
  Widget build(BuildContext context) {
    final moves = game.history.map((m) => m.toString()).toList();

    return Scaffold(
      appBar: AppBar(title: Text("Mode: ${widget.mode}")),
      body: Column(
        children: [
          SizedBox(
            height: 360,
            child: ChessBoard(
              controller: boardController,
              boardColor: BoardColor.brown,
              boardOrientation: PlayerColor.white,
              onMove: onMove,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton(
                  onPressed: () {
                    game.undo();
                    boardController.loadFen(game.fen);
                    setState(() {});
                  },
                  child: const Text("Undo")),
              ElevatedButton(
                  onPressed: () {
                    game.reset();
                    boardController.loadFen(game.fen);
                    setState(() {});
                  },
                  child: const Text("Restart")),
              IconButton(
                icon: Icon(
                  listening ? Icons.mic : Icons.mic_none,
                  color: listening ? Colors.red : Colors.black,
                ),
                onPressed: listening ? stopListening : startListening,
              )
            ],
          ),
          Expanded(
            child: ListView.builder(
              itemCount: moves.length,
              itemBuilder: (_, i) => ListTile(
                title: Text(moves[i]),
                onTap: () => tts.speak(moves[i]),
              ),
            ),
          )
        ],
      ),
    );
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