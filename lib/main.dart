import 'dart:convert';
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
              Text(
                playerName.isEmpty ? "Guest" : playerName,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
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
      // keep websocket logic for future; for local testing you can ignore
      channel = IOWebSocketChannel.connect("ws://localhost:8080");

      channel!.stream.listen((data) {
        try {
          final decoded = jsonDecode(data);
          if (decoded["type"] == "ai_move" || decoded["type"] == "assistant_move") {
            final move = decoded["move"];
            if (move != null) {
              // move is expected in long algebraic form acceptable by chess package
              game.move(move);
              boardController.loadFen(game.fen);
              tts.speak("AI played: $move");
              setState(() {});
            }
          }
        } catch (e) {
          debugPrint("Error parsing AI response: $e");
        }
      });
    }
  }

  void sendMove(String move) {
    if (channel != null) {
      final fen = game.fen; // getter
      if (widget.mode == "ai") {
        channel!.sink.add('{"type":"ai_move","fen":"$fen","level":"beginner"}');
      } else if (widget.mode == "assistant") {
        channel!.sink.add('{"type":"assistant_move","fen":"$fen"}');
      }
    }
  }

  // Undo last move
  void undoMove() {
    try {
      final res = game.undo();
      // res could be null if no moves
      boardController.loadFen(game.fen);
      setState(() {});
      if (res != null) tts.speak("Undid move");
    } catch (e) {
      debugPrint("Undo error: $e");
    }
  }

  // Restart the game
  void restartGame() {
    game.reset();
    boardController.loadFen(game.fen);
    setState(() {});
    tts.speak("Game restarted");
  }

  void onMove() {
    // update local game from board controller FEN, then refresh UI & history
    try {
      final fen = boardController.getFen();
      game.load(fen);
      final last = game.history.isNotEmpty ? game.history.last.toString() : "";
      setState(() {}); // refresh UI (history list etc)
      if (last.isNotEmpty) {
        tts.speak("Move played: $last");
        if (widget.mode == "ai" || widget.mode == "assistant") {
          sendMove(last);
        }
      }
    } catch (e) {
      debugPrint("onMove error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    // build a layout: board on top, controls and move list below
    final moves = game.history.map((m) => m.toString()).toList();
    return Scaffold(
      appBar: AppBar(title: Text("Mode: ${widget.mode}")),
      body: Column(
        children: [
          // Chess board (fixed height for better layout on mobile)
          SizedBox(
            height: 360,
            child: ChessBoard(
              controller: boardController,
              boardColor: BoardColor.brown,
              boardOrientation: PlayerColor.white,
              onMove: onMove,
            ),
          ),

          // Controls: Undo / Restart
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: undoMove,
                  icon: const Icon(Icons.undo),
                  label: const Text("Undo"),
                ),
                ElevatedButton.icon(
                  onPressed: restartGame,
                  icon: const Icon(Icons.replay),
                  label: const Text("Restart"),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    // quick speak current FEN or moves
                    final last = game.history.isNotEmpty ? game.history.last.toString() : "No moves yet";
                    tts.speak(last);
                  },
                  icon: const Icon(Icons.volume_up),
                  label: const Text("Speak Last"),
                ),
              ],
            ),
          ),

          const Divider(),

          // Move history list
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text("Move History", style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Expanded(
                    child: moves.isEmpty
                        ? const Center(child: Text("No moves yet"))
                        : ListView.separated(
                            itemCount: moves.length,
                            separatorBuilder: (_, __) => const Divider(),
                            itemBuilder: (context, index) {
                              final moveText = moves[index];
                              return ListTile(
                                dense: true,
                                leading: Text("${index + 1}."),
                                title: Text(moveText),
                                onTap: () {
                                  // tap a move to speak it
                                  tts.speak(moveText);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
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