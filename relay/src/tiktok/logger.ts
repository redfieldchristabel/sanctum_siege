import type { GameEvent } from '../../types.js';

export function logConversion(eventType: string, rawFieldsSummary: object, finalPayload: GameEvent): void {
  console.log(`\n🔔 [TYPED TIKTOK EVENT] ─── ${eventType} ───`);
  console.log(`   🔹 Extracted Raw Keys :`, JSON.stringify(rawFieldsSummary));
  console.log(`   🔹 Type-Safe Payload  :`, JSON.stringify(finalPayload));
  console.log(`─────────────────────────────────────────────────────────────────\n`);
}
