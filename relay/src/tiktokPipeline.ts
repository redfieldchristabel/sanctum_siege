import { TikTokLiveConnection } from 'tiktok-live-connector';
import type { GameEvent } from '../types.js';

// TikTokLiveConnection extends EventEmitter at runtime but the package types
// don't expose .on(). Use a minimal shim for type safety.
type TikTokEventEmitter = {
  on(event: 'chat', fn: (data: TikTokChatData) => void): void;
  on(event: 'like', fn: (data: TikTokLikeData) => void): void;
  on(event: 'gift', fn: (data: TikTokGiftData) => void): void;
  on(event: 'error', fn: (err: Error) => void): void;
  on(event: 'disconnected', fn: (reason: string) => void): void;
};

interface TikTokChatData {
  userId: string;
  uniqueId: string;
  comment: string;
}

interface TikTokLikeData {
  userId: string;
  uniqueId: string;
  likeCount: number;
  isFollower?: boolean;
}

interface TikTokGiftData {
  userId: string;
  uniqueId: string;
  giftName: string;
  repeatCount: number;
  diamondCount: number;
  giftType: number;
  repeatEnd: number;
  isFollower?: boolean;
}

/**
 * Initializes the connection to a live TikTok room and forwards events via the broadcast handler.
 * @param broadcast Callback function to route payload frames down to the game client
 */
export function initTikTokPipeline(broadcast: (event: GameEvent) => void): void {
  const tiktokUsername = process.env.TIKTOK_USERNAME || "christabelredfiel";

  console.log(`[tiktok] Initializing connector for account: @${tiktokUsername}`);

  const conn: TikTokEventEmitter = new TikTokLiveConnection(tiktokUsername, {
    processInitialData: true,
    fetchRoomInfoOnConnect: true,
    enableExtendedGiftInfo: false
  }) as unknown as TikTokEventEmitter;

  (conn as unknown as TikTokLiveConnection).connect()
    .then((state: { roomId: string }) => {
      console.log(`[tiktok] Successfully attached to room ID: ${state.roomId}`);
    })
    .catch((err: Error) => {
      console.error('[tiktok] Connection initialization failed:', err.message || err);
    });

  // ─── Stream Viewer Chat Comments ───
  conn.on('chat', (data: TikTokChatData) => {
    broadcast({
      event: "comment",
      data: {
        userId: data.userId,
        username: data.uniqueId,
        text: data.comment
      },
      source: "tiktok"
    });
  });

  // ─── Stream Taps / Likes ───
  conn.on('like', (data: TikTokLikeData) => {
    broadcast({
      event: "like",
      data: {
        userId: data.userId,
        username: data.uniqueId,
        count: data.likeCount,
        ...(data.isFollower !== undefined ? { isFollower: data.isFollower } : {}),
      },
      source: "tiktok"
    });
  });

  // ─── Stream Gift Purchases ───
  conn.on('gift', (data: TikTokGiftData) => {
    // giftType 1 + repeatEnd guarantees parsing only after a combo sequence completes
    if (data.giftType === 1 && data.repeatEnd === 1) {
      broadcast({
        event: "gift",
        data: {
          userId: data.userId,
          username: data.uniqueId,
          giftName: data.giftName || "", // Empty string fallback — safe without extended gift info
          count: data.repeatCount,
          coinCost: data.diamondCount || 1, // Raw diamonds; fallback 1 for free-tier safety
          ...(data.isFollower !== undefined ? { isFollower: data.isFollower } : {}),
        },
        source: "tiktok"
      });
    }
  });

  conn.on('error', (err: Error) => {
    console.error('[tiktok] Live Pipeline Exception encountered:', err);
  });

  conn.on('disconnected', (reason: string) => {
    console.warn(`[tiktok] Live pipeline dropped connection. Reason: ${reason}`);
  });
}
