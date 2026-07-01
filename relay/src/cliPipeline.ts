import { WebSocket } from "ws";
import type { GameEvent, CliCommand } from "../types.js";

/**
 * Validates and handles execution for inbound commands arriving from the Moderator CLI.
 */
export function handleCliMessage(
  ws: WebSocket,
  rawMessage: Buffer | string,
  broadcast: (event: GameEvent) => void,
  onStartTikTok: (username?: string) => void
): void {
  let msg: CliCommand;

  try {
    msg = JSON.parse(rawMessage.toString());
  } catch {
    ws.send(JSON.stringify({ type: "error", payload: "invalid JSON payload structure" }));
    return;
  }

  // Intercept: tiktok event triggers on-demand pipeline init instead of broadcasting
  if ((msg as { event: string }).event === "tiktok") {
    const username = (msg.data as Record<string, string> | undefined)?.username;
    onStartTikTok(username);
    return;
  }

  // Build the game event structure with explicit source designation
  const gameEvent: GameEvent = {
    event: msg.event as GameEvent["event"],
    data: msg.data as GameEvent["data"],
    source: "dev"
  } as GameEvent;

  // Broadcast the moderator interaction to the connected game clients
  broadcast(gameEvent);

  // Acknowledge the command back to the CLI tool
  ws.send(JSON.stringify({ type: "ack", payload: `${gameEvent.event} forwarded to game` }));
  console.log(`[relay] dev override → ${gameEvent.event}`, JSON.stringify(msg.data));
}
