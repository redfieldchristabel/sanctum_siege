// ─── Sanctum Siege — Dev CLI ─────────────────────────────────
// Interactive tool that connects to the relay and injects events.
//
// Usage:
//   npx tsx cli.ts                    — interactive mode
//   echo "wave hard" | npx tsx cli.ts --pipe   — pipe mode
//
// TikTok simulation:
//   join <name>   → viewer enters stream (appears in party, sets active user)
//   like <count>  → active user sends likes (adds points to their lobby score)
//   gift <n> [c]  → active user sends a gift

import * as readline from "node:readline";
import { stdin as input, stdout as output, exit } from "node:process";
import * as fs from "node:fs";
import * as path from "node:path";

const RELAY_URL = process.env.RELAY_URL ?? "ws://localhost:8080/dev";
const PRESETS_DIR = path.resolve(import.meta.dirname!, "presets");

// ─── Active user tracking ─────────────────────────
let _activeUser: { userId: string; username: string } | null = null;

// ─── Help text ───────────────────────────────────────────────

const HELP = `
  ⚔️  Sanctum Siege — Dev CLI (TikTok Simulator)

  TikTok Events:
    join <name>      Viewer enters stream (sets active user, appears in party)
    like [count]     Active user sends likes (adds lobby points)
    gift <name> [c]  Active user sends a gift (adds lobby points)
    comment <text>   Chat comment from active user
    leave            Active user leaves

  Game Admin:
    start / go       Start game (idle → 3s countdown → fight)
    wave [type]      Spawn devil wave (normal/hard/boss)
    angel <count>    Spawn angels
    config <k> <v>   Change game config at runtime
    march            Trigger start-match transition

  Other:
    lobby            Fill lobby with mock party for testing
    lobby_clear      Reset all lobby slots
    presets          List available presets
    run <name>       Run a preset
    help             Show this
    exit / quit      Disconnect

  Shortcuts:
    j <name>    = join
    l <id>      = leave
    g <n> [c]   = gift
    w [type]    = wave

`.trim();

// ─── Command builders ────────────────────────────────────────

type CommandFn = (match: RegExpMatchArray) => { event: string; data: Record<string, unknown> };

interface CommandEntry {
  pattern: RegExp;
  build: CommandFn;
}

function send(a: { event: string; data: Record<string, unknown> }): void {
  sendEvent(a.event, a.data);
}

const commands: CommandEntry[] = [
  // ── TikTok event: join ──────────────────────────
  {
    pattern: /^(?:join|j)\s+(.+)$/i,
    build: ([, name]) => {
      const userId = `dev_${Date.now()}`;
      const username = name.trim();
      _activeUser = { userId, username };
      return { event: "join", data: { userId, username, isGifter: false } };
    },
  },
  // ── TikTok event: like ──────────────────────────
  {
    pattern: /^(?:like|likes?)\s*(\d+)?$/i,
    build: ([, count]) => {
      const c = count ? parseInt(count) : 1;
      const u = _activeUser ?? { userId: "dev", username: "Dev" };
      return { event: "like", data: { userId: u.userId, username: u.username, count: c } };
    },
  },
  // ── TikTok event: gift ──────────────────────────
  {
    pattern: /^(?:gift|g)\s+(\S+)\s*(\d+)?$/i,
    build: ([, giftName, count]) => {
      const c = count ? parseInt(count) : 1;
      const u = _activeUser ?? { userId: "dev", username: "Dev" };
      return {
        event: "gift",
        data: {
          userId: u.userId,
          username: u.username,
          giftName: giftName.trim(),
          count: c,
          // Include calculated points so the receiver doesn't need gift name→points logic
          lobbyPoints: calcGiftPoints(giftName, c),
        },
      };
    },
  },
  // ── TikTok event: comment ───────────────────────
  {
    pattern: /^(?:comment|chat|c)\s+(.+)$/i,
    build: ([, text]) => {
      const u = _activeUser ?? { userId: "dev_chat", username: "Dev" };
      return { event: "comment", data: { userId: u.userId, username: u.username, text: text.trim() } };
    },
  },
  // ── TikTok event: leave ─────────────────────────
  {
    pattern: /^(?:leave|l)\s*(\S*)$/i,
    build: ([, id]) => {
      const userId = id || _activeUser?.userId || "unknown";
      _activeUser = null;
      return { event: "leave", data: { userId } };
    },
  },
  // ── Game admin ──────────────────────────────────
  {
    pattern: /^(?:game_start|start|begin|go)$/i,
    build: () => ({ event: "game_start", data: {} }),
  },
  {
    pattern: /^(?:wave|w)\s*(normal|hard|boss)?$/i,
    build: ([, difficulty]) => ({
      event: "spawn_wave",
      data: { difficulty: difficulty ?? "normal" },
    }),
  },
  {
    pattern: /^(?:angel|a)\s+(\d+)$/i,
    build: ([, count]) => ({
      event: "spawn_angel",
      data: { count: parseInt(count) },
    }),
  },
  {
    pattern: /^march$/i,
    build: () => ({ event: "start_match", data: {} }),
  },
  {
    pattern: /^(?:config|set)\s+(\S+)\s+(.+)$/i,
    build: ([, key, value]) => {
      let parsed: unknown = value.trim();
      if (parsed === "true") parsed = true;
      else if (parsed === "false") parsed = false;
      else if (/^\d+$/.test(parsed as string)) parsed = parseInt(parsed as string);
      else if (/^[\d.]+$/.test(parsed as string)) parsed = parseFloat(parsed as string);
      return { event: "dev_config", data: { key: key.trim(), value: parsed } };
    },
  },
  // ── Lobby admin ─────────────────────────────────
  {
    pattern: /^lobby$/i,
    build: () => ({ event: "lobby_update", data: {} }),
  },
  {
    pattern: /^lobby_clear$/i,
    build: () => ({ event: "lobby_clear", data: {} }),
  },
];

/** Convert gift name to lobby points. */
function calcGiftPoints(name: string, count: number): number {
  const lower = name.toLowerCase();
  if (lower.includes("capsule") || lower.includes("lion")) return 500 * count;
  if (lower.includes("donut") || lower.includes("diamond")) return 50 * count;
  if (lower.includes("rose") || lower.includes("flower")) return 10 * count;
  return 0; // unrecognized gifts don't add lobby points
}

// ─── WebSocket connection ────────────────────────────────────

let ws: WebSocket | null = null;
let connected = false;

function connect(): Promise<void> {
  return new Promise((resolve, reject) => {
    ws = new WebSocket(RELAY_URL);

    ws.onopen = () => {
      connected = true;
      console.log(`  ✓ Connected to ${RELAY_URL}\n`);
      resolve();
    };

    ws.onmessage = (msg) => {
      try {
        const json = JSON.parse(msg.data as string);
        if (json.type === "ack") {
          console.log(`  → ${json.payload}`);
        }
      } catch { /* ignore non-JSON messages */ }
    };

    ws.onerror = () => {
      connected = false;
      reject(new Error("Could not connect. Is the relay running?"));
    };

    ws.onclose = () => {
      connected = false;
    };
  });
}

function sendEvent(event: string, data: Record<string, unknown>): void {
  if (!ws || ws.readyState !== WebSocket.OPEN) {
    console.log("  ✗ Not connected to relay");
    return;
  }
  ws.send(JSON.stringify({ event, data }));
}

/** Execute a single CLI command line. Supports multi-action commands. */
function executeLine(line: string): boolean {
  const trimmed = line.trim();
  if (!trimmed || /^(exit|quit|q)$/i.test(trimmed)) return true;
  if (/^help$/i.test(trimmed)) { console.log(`\n${HELP}\n`); return true; }
  if (/^(?:presets?|list)$/i.test(trimmed)) { listPresets(); return true; }
  if (/^run\s+(\S+)$/i.test(trimmed)) {
    const m = trimmed.match(/^run\s+(\S+)$/i)!;
    runPreset(m[1]!);
    return true;
  }

  for (const cmd of commands) {
    const m = trimmed.match(cmd.pattern);
    if (m) {
      send(cmd.build(m));
      return true;
    }
  }
  return false;
}

// ─── Presets ─────────────────────────────────────────────────

function listPresets(): void {
  try {
    const files = fs.readdirSync(PRESETS_DIR).filter((f) => f.endsWith(".txt"));
    if (files.length === 0) {
      console.log("  No presets found in", PRESETS_DIR);
      return;
    }
    console.log("\n  Available presets:");
    for (const f of files) {
      const name = f.replace(/\.txt$/, "");
      const first = fs.readFileSync(path.join(PRESETS_DIR, f), "utf-8").split("\n")[0]?.replace(/^#\s*/, "") ?? "";
      console.log(`    ${name.padEnd(20)} ${first}`);
    }
    console.log();
  } catch {
    console.log("  Presets directory not found at", PRESETS_DIR);
  }
}

async function runPreset(name: string): Promise<void> {
  const filePath = path.join(PRESETS_DIR, `${name}.txt`);
  let content: string;
  try {
    content = fs.readFileSync(filePath, "utf-8");
  } catch {
    console.log(`  ✗ Preset "${name}" not found. Try "presets" to list.`);
    return;
  }

  console.log(`  ▶ Running preset "${name}"...`);
  const lines = content.split("\n").map((l) => l.trim()).filter((l) => l && !l.startsWith("#"));

  for (const line of lines) {
    // Support sleep <seconds> — pauses execution for a given duration
    const sleepMatch = line.match(/^sleep\s+(\d+(?:\.\d+)?)\s*(?:s(?:ec(?:onds?)?)?)?$/i);
    if (sleepMatch) {
      const ms = Math.round(parseFloat(sleepMatch[1]!) * 1000);
      console.log(`  💤 Sleeping ${sleepMatch[1]}s...`);
      await new Promise((r) => setTimeout(r, ms));
      continue;
    }

    const ok = executeLine(line);
    if (!ok) console.log(`  ? Skipped: "${line}"`);
    await new Promise((r) => setTimeout(r, 300));
  }
  console.log(`  ✓ Preset "${name}" done\n`);
}

// ─── Interactive mode ────────────────────────────────────────

async function interactive(): Promise<void> {
  console.log(HELP);

  const rl = readline.createInterface({ input, output, prompt: "> " });
  rl.prompt();

  for await (const line of rl) {
    const trimmed = line.trim();
    if (!trimmed) { rl.prompt(); continue; }

    // Built-in commands
    if (/^(exit|quit|q)$/i.test(trimmed)) {
      console.log("bye");
      ws?.close();
      rl.close();
      exit(0);
    }
    if (/^help$/i.test(trimmed)) {
      console.log(`\n${HELP}\n`);
      rl.prompt();
      continue;
    }
    if (/^(?:presets?|list)$/i.test(trimmed)) {
      listPresets();
      rl.prompt();
      continue;
    }
    if (/^run\s+(\S+)$/i.test(trimmed)) {
      const m = trimmed.match(/^run\s+(\S+)$/i)!;
      await runPreset(m[1]!);
      rl.prompt();
      continue;
    }

    // WebSocket commands
    let matched = false;
    for (const cmd of commands) {
      const m = trimmed.match(cmd.pattern);
      if (m) {
        send(cmd.build(m));
        matched = true;
        break;
      }
    }

    if (!matched) {
      console.log(`  ? Unknown: "${trimmed}"  (type "help")`);
    }
    rl.prompt();
  }
}

// ─── Pipe mode ───────────────────────────────────────────────

async function pipeMode(): Promise<void> {
  const rl = readline.createInterface({ input });
  const lines: string[] = [];
  for await (const line of rl) {
    const t = line.trim();
    if (t && !t.startsWith("#")) lines.push(t);
  }

  for (const line of lines) {
    executeLine(line);
    await new Promise((r) => setTimeout(r, 200));
  }

  await new Promise((r) => setTimeout(r, 300));
  ws?.close();
  exit(0);
}

// ─── Main ────────────────────────────────────────────────────

async function main() {
  const args = process.argv.slice(2);
  const isPipe = args.includes("--pipe");
  const presetName = args.find((a) => !a.startsWith("--"));

  try {
    await connect();
  } catch {
    console.log(`
  ✗ Could not connect to relay at ${RELAY_URL}
    Make sure the relay is running:
      cd relay && npx tsx index.ts
`);
    exit(1);
  }

  if (presetName && commands.every((c) => !c.pattern.test(`run ${presetName}`))) {
    await runPreset(presetName);
    ws?.close();
    exit(0);
  }

  if (isPipe) {
    await pipeMode();
  } else {
    await interactive();
  }
}

main().catch((err) => {
  console.error("Fatal:", err);
  exit(1);
});
