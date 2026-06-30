import type { GameEvent, JoinData, CommentData, LikeData, GiftData } from '../../types.js';
import type { TikTokMemberEvent, TikTokChatEvent, TikTokLikeEvent, TikTokGiftEvent } from './types.js';

export function mapMemberEvent(data: TikTokMemberEvent): GameEvent {
  const username = data.user?.displayId || data.uniqueId || "UnknownUser";
  const userId = data.user?.id || data.userId || "UnknownID";

  const joinData: JoinData = { userId, username };
  return {
    event: "join",
    data: joinData,
    source: "tiktok"
  };
}

export function mapChatEvent(data: TikTokChatEvent): GameEvent {
  const username = data.uniqueId || data.user?.displayId || "UnknownUser";
  const userId = data.userId || data.user?.id || "UnknownID";
  const text = data.comment || data.commentText || "";

  const commentData: CommentData = { userId, username, text };
  return {
    event: "comment",
    data: commentData,
    source: "tiktok"
  };
}

export function mapLikeEvent(data: TikTokLikeEvent): GameEvent {
  const username = data.user?.displayId || data.uniqueId || "UnknownUser";
  const userId = data.user?.id || data.userId || "UnknownID";
  const count = Number(data.likeCount || data.count || 1);

  const likeData: LikeData = {
    userId,
    username,
    count,
    isFollower: data.isFollower ?? false
  };
  return {
    event: "like",
    data: likeData,
    source: "tiktok"
  };
}

export function mapGiftEvent(data: TikTokGiftEvent): GameEvent {
  const username = data.user?.displayId || data.uniqueId || "UnknownUser";
  const userId = data.user?.id || data.userId || "UnknownID";
  const giftName = data.giftName || data.gift?.name || "Gift";
  const count = Number(data.repeatCount || data.count || 1);
  const coinCost = Number(data.diamondCount || data.gift?.diamondCount || 1);

  const giftData: GiftData = {
    userId,
    username,
    giftName,
    count,
    coinCost,
    isFollower: data.isFollower ?? false
  };
  return {
    event: "gift",
    data: giftData,
    source: "tiktok"
  };
}
