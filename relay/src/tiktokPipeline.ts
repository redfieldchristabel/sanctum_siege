import { TikTokLiveConnection, WebcastEvent } from 'tiktok-live-connector';
import type { GameEvent } from '../types.js';
import type { TikTokEventEmitter } from './tiktok/types.js';
import { mapMemberEvent, mapChatEvent, mapLikeEvent, mapGiftEvent } from './tiktok/mappers.js';
import { logConversion } from './tiktok/logger.js';

export function initTikTokPipeline(
  broadcast: (event: GameEvent) => void,
  tiktokUsername?: string,
  onClosed?: () => void
): void {
  const username: string = tiktokUsername ?? process.env.TIKTOK_USERNAME ?? "christabelredfiel";

  console.log(`[tiktok] Initializing type-safe modular connector for: @${username}`);

  const liveConnection = new TikTokLiveConnection(username, {
    processInitialData: true,
    fetchRoomInfoOnConnect: true,
    enableExtendedGiftInfo: false
  });

  const conn = liveConnection as unknown as TikTokEventEmitter;

  liveConnection.connect()
    .then((state: { roomId: string }) => {
      console.log(`[tiktok] Successfully attached to room ID: ${state.roomId}`);
    })
    .catch((err: Error) => {
      console.error('[tiktok] Connection initialization failed:', err.message || err);
      if (onClosed) onClosed();
    });

  // ─── Stream Viewer Join Events ───
  conn.on(WebcastEvent.MEMBER, (data) => {
    const mapped = mapMemberEvent(data);
    logConversion("MEMBER / JOIN", { userId: data.user?.id, username: data.user?.displayId }, mapped);
    broadcast(mapped);
  });

  // ─── Stream Viewer Chat Comments ───
  conn.on(WebcastEvent.CHAT, (data) => {
    const mapped = mapChatEvent(data);
    const chatUser = data.uniqueId || data.user?.displayId || "UnknownUser";
    logConversion("CHAT / COMMENT", { msgText: data.comment || data.commentText, userHandle: chatUser }, mapped);
    broadcast(mapped);
  });

  // ─── Stream Taps / Likes ───
  conn.on(WebcastEvent.LIKE, (data) => {
    const mapped = mapLikeEvent(data);
    const likeUser = data.user?.displayId || data.uniqueId || "UnknownUser";
    logConversion("LIKE / TAP", { incomingLikes: data.likeCount || data.count, userHandle: likeUser }, mapped);
    broadcast(mapped);
  });

  // ─── Stream Gift Purchases ───
  conn.on(WebcastEvent.GIFT, (data) => {
    const giftType = data.giftType || data.gift?.type || 0;
    const repeatEnd = data.repeatEnd ?? 1;

    const isComboFinished = giftType === 1 && repeatEnd === 1;
    const isInstantGift = giftType !== 1;

    if (isComboFinished || isInstantGift) {
      const mapped = mapGiftEvent(data);
      const logLabel = isComboFinished ? "GIFT (COMBO STREAK FINISHED)" : "GIFT (SINGLE)";

      logConversion(logLabel, { giftName: data.giftName || data.gift?.name, totalCount: data.repeatCount || data.count }, mapped);
      broadcast(mapped);
    } else {
      const username = data.user?.displayId || data.uniqueId || "UnknownUser";
      const giftName = data.giftName || data.gift?.name || "Gift";
      const count = data.repeatCount || data.count || 1;
      console.log(`   ⚡ [Tiktok Gift Combo Increment] @${username} is combo-ing ${giftName} (${count}x)...`);
    }
  });

  conn.on('error', (err: Error) => {
    console.error('[tiktok] Live Pipeline Exception encountered:', err);
  });

  conn.on('disconnected', (reason: string) => {
    console.warn(`[tiktok] Live pipeline dropped connection. Reason: ${reason}`);
    if (onClosed) onClosed();
  });
}
