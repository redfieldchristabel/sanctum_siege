// ─── Sanctum Siege — Shared Event Types ────────────────────────

/** Every event the game can receive from the relay. */
export type GameEvent =
  | { event: "join";      data: JoinData;      source: EventSource }
  | { event: "leave";     data: LeaveData;     source: EventSource }
  | { event: "like";      data: LikeData;      source: EventSource }
  | { event: "gift";      data: GiftData;      source: EventSource }
  | { event: "comment";   data: CommentData;   source: EventSource }
  | { event: "spawn_wave"; data: SpawnWaveData; source: EventSource }
  | { event: "spawn_angel"; data: SpawnAngelData; source: EventSource }
  | { event: "dev_config"; data: DevConfigData;  source: "dev" };

export type EventSource = "tiktok" | "dev";

export interface JoinData {
  userId: string;
  username: string;
}

export interface LeaveData {
  userId: string;
}

export interface LikeData {
  userId: string;
  count: number;
}

export interface GiftData {
  userId: string;
  username: string;
  giftName: string;
  count: number;
}

export interface CommentData {
  userId: string;
  username: string;
  text: string;
}

export interface SpawnWaveData {
  difficulty?: "normal" | "hard" | "boss";
}

export interface SpawnAngelData {
  count: number;
}

export interface DevConfigData {
  key: string;
  value: unknown;
}

/** Message the CLI sends over the wire (source is implied). */
export type CliCommand = { event: GameEvent["event"]; data: Record<string, unknown> };

/** Server → client message (game or CLI). */
export interface ServerMessage {
  type: "welcome" | "error" | "ack";
  payload?: string;
}
