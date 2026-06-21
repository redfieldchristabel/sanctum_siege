// ─── Sanctum Siege — Relay Server ────────────────────────────
// Listens on ws://localhost:8080.
// - Game clients connect and receive forwarded events.
// - CLI/Dev clients connect and inject events with source="dev".

import { WebSocketServer, WebSocket } from "ws";
import type { GameEvent, CliCommand, ServerMessage, EventSource } from "./types.js";

const PORT = 8080;

/** Set of game (subscriber) connections. */
const gameClients = new Set<WebSocket>();

const wss = new WebSocketServer({ port: PORT });

wss.on("connection", (ws, req) => {
  const url = req.url ?? "/";
  const isDev = url === "/dev";            // ws://localhost:8080/dev  — CLI
  const isGame = url === "/game" || url === "/";  // ws://localhost:8080/game or / — game

  send(ws, { type: "welcome", payload: isDev ? "dev-cli" : "game" });

  if (isGame) {
    gameClients.add(ws);
    console.log(`[relay] game client connected  (${gameClients.size} total)`);
  }

  if (isDev) {
    console.log(`[relay] dev CLI connected`);
  }

  ws.on("message", (raw) => {
    let msg: CliCommand;
    try {
      msg = JSON.parse(raw.toString());
    } catch {
      send(ws, { type: "error", payload: "invalid JSON" });
      return;
    }

    // Only dev clients can inject events
    if (!isDev) {
      send(ws, { type: "error", payload: "only dev clients can inject events" });
      return;
    }

    const gameEvent: GameEvent = {
      event: msg.event as GameEvent["event"],
      data: msg.data as GameEvent["data"],
      source: "dev",
    } as GameEvent;

    broadcast(gameEvent);
    send(ws, { type: "ack", payload: `${gameEvent.event} forwarded` });
    console.log(`[relay] dev → ${gameEvent.event}`, JSON.stringify(msg.data));
  });

  ws.on("close", () => {
    gameClients.delete(ws);
    if (isGame) console.log(`[relay] game client disconnected (${gameClients.size} left)`);
    if (isDev) console.log(`[relay] dev CLI disconnected`);
  });

  ws.on("error", () => gameClients.delete(ws));
});

/** Broadcast an event to all connected game clients. */
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

console.log(`\n  ⚔️  Sanctum Siege — Relay Server`);
console.log(`  ───────────────────────────────`);
console.log(`  ws://localhost:${PORT}        → game clients`);
console.log(`  ws://localhost:${PORT}/dev    → CLI / dev tools`);
console.log();
