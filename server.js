const WebSocket = require('ws');
const { spawn } = require('child_process');

const wss = new WebSocket.Server({ port: 8080 });

wss.on('connection', ws => {
  ws.on('message', msg => {
    try {
      const data = JSON.parse(msg);

      if (data.type === 'ai_move') {
        // Stockfish integration
        const stockfish = spawn('stockfish');
        stockfish.stdin.write(`position fen ${data.fen}\n`);
        stockfish.stdin.write(`go depth 10\n`);
        stockfish.stdout.on('data', d => {
          const line = d.toString();
          if (line.includes('bestmove')) {
            ws.send(JSON.stringify({ type: 'ai_move', bestmove: line.split(' ')[1] }));
            stockfish.kill();
          }
        });
      }

      if (data.type === 'assistant_move') {
        // Assistant simulation (placeholder)
        ws.send(JSON.stringify({
          type: 'assistant_move',
          bestmove: 'e2e4',
          explanation: 'I played pawn to e4 to control the center.'
        }));
      }
    } catch (e) {
      console.error(e);
    }
  });
});

console.log('Server running on ws://localhost:8080');