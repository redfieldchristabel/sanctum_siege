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
  | { event: "dev_config"; data: DevConfigData;  source: "dev" }
  // ── Lobby events ──
  | { event: "lobby_join";    data: LobbyJoinData;       source: "dev" }
  | { event: "lobby_update"; data: Record<string, never>; source: "dev" }
  | { event: "lobby_clear";  data: Record<string, never>; source: "dev" }
  | { event: "lobby_points"; data: LobbyPointsData;      source: "dev" }
  | { event: "start_match";  data: Record<string, never>; source: "dev" }
  // Game lifecycle
  | { event: "next_match";  data: Record<string, never>; source: "dev" };

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
  isFollower?: boolean;
}

export interface GiftData {
  userId: string;
  username: string;
  giftName: string;
  count: number;
  coinCost?: number;
  isFollower?: boolean;
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

export interface LobbyJoinData {
  username: string;
  points: number;
  isGifter: boolean;
}

export interface LobbyPointsData {
  username: string;
  points: number;
}

/** Message the CLI sends over the wire (source is implied). */
export type CliCommand = { event: GameEvent["event"]; data: Record<string, unknown> };

/** Server → client message (game or CLI). */
export interface ServerMessage {
  type: "welcome" | "error" | "ack";
  payload?: string;
}
