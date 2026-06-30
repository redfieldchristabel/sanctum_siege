// ─── Sanctum Siege — Core Orchestrator Relay ────────────────
import { WebSocketServer, WebSocket } from "ws";
import type { GameEvent, ServerMessage } from "./types.js";
import { initTikTokPipeline } from "./src/tiktokPipeline.js";
import { handleCliMessage } from "./src/cliPipeline.js";

const PORT = 8080;
const gameClients = new Set<WebSocket>();
const wss = new WebSocketServer({ port: PORT });

// ─── Start the Concurrent Event Pipelines ───
// TikTok pipeline boots on-demand via moderator CLI command ("tiktok") instead of at startup
let isTikTokPipelineRunning = false;

wss.on("connection", (ws, req) => {
  const url = req.url ?? "/";
  const isDev = url === "/dev";                  // ws://localhost:8080/dev  — Moderator CLI
  const isGame = url === "/game" || url === "/";  // ws://localhost:8080/game or / — Game Engine

  send(ws, { type: "welcome", payload: isDev ? "dev-cli" : "game" });

  if (isGame) {
    gameClients.add(ws);
    console.log(`[relay] game engine instance connected (${gameClients.size} total)`);
  }

  if (isDev) {
    console.log(`[relay] moderator dev CLI connection established`);
  }

  ws.on("message", (raw) => {
    // Security check: Guard access so only local moderator CLI connections can inject over the path
    if (!isDev) {
      send(ws, { type: "error", payload: "access denied: only authorized dev clients inject events" });
      return;
    }

    // Forward the message to the CLI pipeline module for routing execution
    handleCliMessage(ws, raw as Buffer, broadcast, () => {
      if (isTikTokPipelineRunning) {
        send(ws, { type: "error", payload: "Pipeline Aborted: TikTok Live scraper is already active." });
        return;
      }

      console.log(`\n[relay] CLI Activation Triggered: Booting up TikTok Live Stream Listeners...`);

      // Flip flag to true to secure the lock
      isTikTokPipelineRunning = true;

      // Pass the state-reset callback so the process error or disconnect can auto-release
      initTikTokPipeline(broadcast, () => {
        isTikTokPipelineRunning = false;
        console.log(`[relay] TikTok pipeline state cleared. Ready for next manual activation.`);
      });

      send(ws, { type: "ack", payload: "TikTok live scraping pipeline successfully launched!" });
    });
  });

  ws.on("close", () => {
    gameClients.delete(ws);
    if (isGame) console.log(`[relay] game engine client dropped (${gameClients.size} remaining)`);
    if (isDev) console.log(`[relay] moderator dev CLI link disconnected`);
  });

  ws.on("error", () => gameClients.delete(ws));
});

/** Broadcast any internal or external unified event to all open game sessions */
function broadcast(event: GameEvent): void {
  const json = JSON.stringify(event);
  for (const client of gameClients) {
    if (client.readyState === WebSocket.OPEN) {
      client.send(json);
    }
  }
}

function send(ws: WebSocket, msg: ServerMessage): void {
  ws.send(JSON.stringify(msg));
}

console.log(`\n  ⚔️  Sanctum Siege — Modular Event Router Active`);
console.log(`  ───────────────────────────────────────────────`);
console.log(`  ws://localhost:${PORT}        → target for game client stream listeners`);
console.log(`  ws://localhost:${PORT}/dev    → target for interactive moderator tools`);
console.log();
