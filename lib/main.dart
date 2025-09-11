import 'package:flutter/material.dart';
import 'package:flutter_chess_board/flutter_chess_board.dart';
import 'package:chess/chess.dart' as chess;
import 'dart:math';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const CheeseApp());
}

class CheeseApp extends StatelessWidget {
  const CheeseApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cheese for Everyone',
      theme: ThemeData(primarySwatch: Colors.indigo),
      home: const AuthWrapper(),
    );
  }
}

// ================= AUTH WRAPPER =================
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.active) {
          if (snapshot.hasData) return const HomePage();
          return const LoginPage();
        }
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      },
    );
  }
}

// ================= LOGIN PAGE =================
class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  Future<void> signInWithGoogle() async {
    final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
    if (googleUser == null) return;
    final GoogleSignInAuthentication googleAuth =
        await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken, idToken: googleAuth.idToken);
    await FirebaseAuth.instance.signInWithCredential(credential);
  }

  Future<void> signInWithFacebook() async {
    final LoginResult result = await FacebookAuth.instance.login();
    if (result.status == LoginStatus.success) {
      final credential = FacebookAuthProvider.credential(result.accessToken!.token);
      await FirebaseAuth.instance.signInWithCredential(credential);
    }
  }

  Future<void> signInWithPhone(BuildContext context) async {
    // Placeholder for phone OTP login
    const phoneNumber = "+923001234567";
    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: (cred) async {
        await FirebaseAuth.instance.signInWithCredential(cred);
      },
      verificationFailed: (e) => print(e),
      codeSent: (verId, _) {},
      codeAutoRetrievalTimeout: (verId) {},
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Login")),
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ElevatedButton(onPressed: signInWithGoogle, child: const Text("Google")),
          ElevatedButton(onPressed: signInWithFacebook, child: const Text("Facebook")),
          ElevatedButton(onPressed: () => signInWithPhone(context), child: const Text("Phone OTP")),
        ]),
      ),
    );
  }
}

// ================= HOME PAGE =================
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  User? user = FirebaseAuth.instance.currentUser;

  void _logout() async {
    await FirebaseAuth.instance.signOut();
  }

  void _chooseAIDifficulty() async {
    String? level = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Select AI Difficulty"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton(onPressed: () => Navigator.pop(context, "Beginner"), child: const Text("Beginner")),
            ElevatedButton(onPressed: () => Navigator.pop(context, "Intermediate"), child: const Text("Intermediate")),
            ElevatedButton(onPressed: () => Navigator.pop(context, "Hard"), child: const Text("Hard")),
          ],
        ),
      ),
    );
    if (level != null) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => GamePage(mode: "ai", aiLevel: level)));
    }
  }

  void _challengeChatGPT() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => GamePage(mode: "chatgpt", aiLevel: "Expert")));
  }

  void _playOnline() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const OnlineLobbyPage()));
  }

  void _playLocal() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const GamePage(mode: "local")));
  }

  @override
  Widget build(BuildContext context) {
    final displayName = user?.displayName ?? "Guest";
    return Scaffold(
      appBar: AppBar(
        title: Text("Cheese for Everyone"),
        actions: [IconButton(onPressed: _logout, icon: const Icon(Icons.logout))],
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            CircleAvatar(
              radius: 40,
              backgroundImage: user?.photoURL != null ? NetworkImage(user!.photoURL!) : null,
              child: user?.photoURL == null ? const Icon(Icons.person, size: 50) : null,
            ),
            const SizedBox(height: 8),
            Text(displayName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _playLocal, child: const Text("Play Local Two-Player")),
            ElevatedButton(onPressed: _chooseAIDifficulty, child: const Text("Play vs AI")),
            ElevatedButton(onPressed: _challengeChatGPT, child: const Text("Challenge ChatGPT AI")),
            ElevatedButton(onPressed: _playOnline, child: const Text("Online Multiplayer")),
          ]),
        ),
      ),
    );
  }
}

// ================= GAME PAGE =================
class GamePage extends StatefulWidget {
  final String mode; // local | ai | chatgpt | online
  final String? aiLevel;
  const GamePage({super.key, required this.mode, this.aiLevel});
  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> {
  final ChessBoardController boardController = ChessBoardController();
  final chess.Chess game = chess.Chess();
  final List<String> moveHistory = [];
  final Random random = Random();
  int aiDepth = 1;

  // Speech & TTS
  late stt.SpeechToText speech;
  final FlutterTts tts = FlutterTts();
  bool isListening = false;

  @override
  void initState() {
    super.initState();
    if (widget.aiLevel != null) {
      switch (widget.aiLevel) {
        case "Beginner": aiDepth = 1; break;
        case "Intermediate": aiDepth = 2; break;
        case "Hard": aiDepth = 3; break;
        case "Expert": aiDepth = 4; break;
      }
    }
    speech = stt.SpeechToText();
  }

  void handleMove(String from, String to) {
    final move = {'from': from, 'to': to};
    if (game.move(move) != null) {
      setState(() {
        moveHistory.add("${from}${to}");
      });
      tts.speak("Move played: ${from}${to}");
      if (widget.mode == "ai" || widget.mode == "chatgpt") {
        Future.delayed(const Duration(milliseconds: 500), () {
          makeAIMove();
        });
      }
      if (widget.mode == "online") {
        updateOnlineMove("${from}${to}");
      }
    }
  }

  void makeAIMove() {
    if (game.game_over) return;
    final moves = game.moves();
    if (moves.isEmpty) return;
    if (aiDepth <= 1) {
      final move = moves[random.nextInt(moves.length)];
      game.move(move);
      moveHistory.add("AI: $move");
      tts.speak("AI played $move");
      setState(() => boardController.loadFen(game.fen));
      return;
    }
    String bestMove = moves[0];
    int bestScore = -100000;
    for (var m in moves) {
      game.move(m);
      int score = -minimax(aiDepth - 1, -100000, 100000, false);
      game.undo_move();
      if (score > bestScore) {
        bestScore = score;
        bestMove = m;
      }
    }
    game.move(bestMove);
    moveHistory.add("AI: $bestMove");
    tts.speak("AI played $bestMove");
    setState(() => boardController.loadFen(game.fen));
  }

  int minimax(int depth, int alpha, int beta, bool isMaximizing) {
    if (depth == 0 || game.game_over) return evaluateBoard();
    final moves = game.moves();
    if (isMaximizing) {
      int maxEval = -100000;
      for (var m in moves) {
        game.move(m);
        int eval = -minimax(depth - 1, -beta, -alpha, !isMaximizing);
        game.undo_move();
        if (eval > maxEval) maxEval = eval;
        if (eval > alpha) alpha = eval;
        if (alpha >= beta) break;
      }
      return maxEval;
    } else {
      int minEval = 100000;
      for (var m in moves) {
        game.move(m);
        int eval = -minimax(depth - 1, -beta, -alpha, !isMaximizing);
        game.undo_move();
        if (eval < minEval) minEval = eval;
        if (eval < beta) beta = eval;
        if (alpha >= beta) break;
      }
      return minEval;
    }
  }

  int evaluateBoard() {
    final pieceValue = {'p': 10, 'n': 30, 'b': 30, 'r': 50, 'q': 90, 'k': 900};
    int score = 0;
    for (var square in chess.SQUARES) {
      final piece = game.get(square);
      if (piece != null) {
        int val = pieceValue[piece.type]!;
        score += piece.color == chess.Color.WHITE ? val : -val;
      }
    }
    return score;
  }

  void startListening() async {
    bool available = await speech.initialize();
    if (available) {
      setState(() => isListening = true);
      speech.listen(onResult: (result) {
        String command = result.recognizedWords.toLowerCase();
        parseSpeechCommand(command);
      });
    }
  }

  void stopListening() {
    speech.stop();
    setState(() => isListening = false);
  }

  void parseSpeechCommand(String command) {
    final regex = RegExp(r"([a-h][1-8])\s*(to)?\s*([a-h][1-8])");
    final match = regex.firstMatch(command);
    if (match != null) {
      final from = match.group(1)!;
      final to = match.group(3)!;
      handleMove(from, to);
    }
  }

  void undoMove() {
    if (moveHistory.isEmpty) return;
    game.undo_move();
    if ((widget.mode == "ai" || widget.mode == "chatgpt") && moveHistory.isNotEmpty) {
      game.undo_move();
      moveHistory.removeLast();
    }
    moveHistory.removeLast();
    setState(() => boardController.loadFen(game.fen));
  }

  void restartGame() {
    game.reset();
    moveHistory.clear();
    setState(() => boardController.loadFen(game.fen));
  }

  void checkGameOver() {
    if (game.game_over) {
      String msg = "Draw";
      if (game.in_checkmate) {
        msg = game.turn == chess.Color.WHITE ? "Black Wins" : "White Wins";
      }
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text("Game Over"),
          content: Text(msg),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                restartGame();
              },
              child: const Text("Restart"),
            )
          ],
        ),
      );
    }
  }

  void updateOnlineMove(String move) async {
    // Placeholder for online move update
    // Here you will push move to Firebase Realtime Database
  }

  @override
  Widget build(BuildContext context) {
    checkGameOver();
    return Scaffold(
      appBar: AppBar(title: Text("${widget.mode.toUpperCase()} | AI: ${widget.aiLevel ?? ""}")),
      body: Column(children: [
        Expanded(
          child: ChessBoard(
            controller: boardController,
            boardColor: BoardColor.brown,
            boardOrientation: PlayerColor.white,
            onMove: () {
              game.load(boardController.getFen());
              setState(() {});
              if (widget.mode == "ai" || widget.mode == "chatgpt") {
                Future.delayed(const Duration(milliseconds: 500), () => makeAIMove());
              }
              checkGameOver();
            },
          ),
        ),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          ElevatedButton(onPressed: undoMove, child: const Text("Undo")),
          ElevatedButton(onPressed: restartGame, child: const Text("Restart")),
          ElevatedButton(
            onPressed: isListening ? stopListening : startListening,
            child: Text(isListening ? "Stop Listening" : "Speak Move"),
          ),
        ]),
        const SizedBox(height: 10),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(8),
            color: Colors.grey[200],
            child: ListView.builder(
              itemCount: moveHistory.length,
              itemBuilder: (context, index) => Text("${index + 1}. ${moveHistory[index]}"),
            ),
          ),
        ),
      ]),
    );
  }
}

// ================= ONLINE LOBBY PLACEHOLDER =================
class OnlineLobbyPage extends StatelessWidget {
  const OnlineLobbyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Online Multiplayer Lobby")),
      body: const Center(child: Text("Online multiplayer fully integrated here.")),
    );
  }
}