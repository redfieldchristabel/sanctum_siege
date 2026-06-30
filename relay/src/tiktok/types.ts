import { WebcastEvent } from 'tiktok-live-connector';

export interface TikTokUserObj {
  id: string;
  displayId: string;
  nickname?: string;
}

export interface TikTokGiftNestedObj {
  name?: string;
  diamondCount?: number;
  type?: number;
}

export interface TikTokMemberEvent {
  user?: TikTokUserObj;
  uniqueId?: string;
  userId?: string;
}

export interface TikTokChatEvent {
  user?: TikTokUserObj;
  uniqueId?: string;
  userId?: string;
  comment?: string;
  commentText?: string;
}

export interface TikTokLikeEvent {
  user?: TikTokUserObj;
  uniqueId?: string;
  userId?: string;
  likeCount?: number;
  count?: number;
  isFollower?: boolean;
}

export interface TikTokGiftEvent {
  user?: TikTokUserObj;
  uniqueId?: string;
  userId?: string;
  giftName?: string;
  gift?: TikTokGiftNestedObj;
  repeatCount?: number;
  count?: number;
  diamondCount?: number;
  giftType?: number;
  repeatEnd?: number;
  isFollower?: boolean;
}

export type TikTokEventEmitter = {
  on(event: WebcastEvent.MEMBER, fn: (data: TikTokMemberEvent) => void): void;
  on(event: WebcastEvent.CHAT, fn: (data: TikTokChatEvent) => void): void;
  on(event: WebcastEvent.LIKE, fn: (data: TikTokLikeEvent) => void): void;
  on(event: WebcastEvent.GIFT, fn: (data: TikTokGiftEvent) => void): void;
  on(event: 'error', fn: (err: Error) => void): void;
  on(event: 'disconnected', fn: (reason: string) => void): void;
};
