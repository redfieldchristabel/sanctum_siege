// ─── Sanctum Siege — Dev CLI ─────────────────────────────────
// Interactive tool that connects to the relay and injects events.
//
// Usage:
//   npx tsx cli.ts                    — interactive mode
//   echo "wave hard" | npx tsx cli.ts --pipe   — pipe mode

import * as readline from "node:readline";
import { stdin as input, stdout as output, exit } from "node:process";
import * as fs from "node:fs";
import * as path from "node:path";

const RELAY_URL = process.env.RELAY_URL ?? "ws://localhost:8080/dev";
const PRESETS_DIR = path.resolve(import.meta.dirname!, "presets");

// ─── Active user tracking & context ─────────────────────────
let _activeUser: { userId: string; username: string } | null = null;

// Registry map of username -> userId to retain consistency across sessions
const _userMap = new Map<string, string>([
  ["sarah", "dev_sarah"],
  ["alex", "dev_alex"],
  ["bob", "dev_bob"],
  ["alice", "dev_alice"],
]);

// ─── Help text ───────────────────────────────────────────────

const HELP = `
  ⚔️  Sanctum Siege — Dev CLI (TikTok Simulator)

  TikTok Context & Events:
    be <name>        Become/switch to this user context locally (no join event)
    join <name>      Viewer enters stream (sets active user, appears in party)
    like [count]     Active user sends likes (adds lobby points)
    gift <name> [c]  Active user sends a gift (adds lobby points)
    comment <text>   Chat comment from active user
    revive <user>    Send revive request (active user's soldier walks to ghost)
    cover <user>     Send cover request (active user's soldier guards target)
    leave            Active user leaves

  Game Admin:
    start / go       Start game (idle → 3s countdown → fight)
    kill <name>      Instantly kill an angel soldier (for revive testing)
    wave [type]      Spawn devil wave (normal/hard/boss)
    angel <count>    Spawn angels
    spawn <name>     Spawn a named angel (username matters for revive)
    melee <name>     Spawn a named melee-class soldier (tank, close-range)
    config <k> <v>   Change game config at runtime
    march            Trigger start-match transition
    next / reset     Return to lobby for next match (after game over)

  Other:
    lobby            Fill lobby with mock party for testing
    lobby_clear      Reset all lobby slots
    presets          List available presets
    run <name>       Run a preset
    help             Show this
    exit / quit      Disconnect

  Shortcuts:
    be <name>   = become
    j <name>    = join
    l           = leave
    g <n> [c]   = gift
    w [type]    = wave
    c <text>    = comment
    r <user>    = revive
    cov <user>  = cover
`.trim();

// ─── Command builders ────────────────────────────────────────

type CommandFn = (
  match: RegExpMatchArray,
  activeUser: { userId: string; username: string }
) => { event: string; data: Record<string, unknown> } | null;

interface CommandEntry {
  pattern: RegExp;
  requiresUser?: boolean; // Contextual Guard Check Flag
  build: CommandFn;
}

function send(a: { event: string; data: Record<string, unknown> }): void {
  sendEvent(a.event, a.data);
}

const commands: CommandEntry[] = [
  // ── Local command: become/be ───────────────────
  {
    pattern: /^be(?:come)?\s+(.+)$/i,
    build: ([, name]) => {
      const username = name.trim();
      const userId = _userMap.get(username.toLowerCase()) ?? `dev_${username.toLowerCase()}`;
      _userMap.set(username.toLowerCase(), userId);
      _activeUser = { userId, username };
      console.log(`  👤 Switched context! You are now acting as: ${username}`);
      return null; // Handled internally, nothing sent to relay server
    },
  },
  // ── TikTok event: join ──────────────────────────
  {
    pattern: /^(?:join|j)\s+(.+)$/i,
    build: ([, name]) => {
      const username = name.trim();
      const userId = _userMap.get(username.toLowerCase()) ?? `dev_${Date.now()}`;
      _userMap.set(username.toLowerCase(), userId);
      _activeUser = { userId, username };
      return { event: "join", data: { userId, username, isGifter: false } };
    },
  },
  // ── TikTok event: like ──────────────────────────
  {
    pattern: /^(?:like|likes?)\s*(\d+)?$/i,
    requiresUser: true,
    build: ([, count], u) => {
      const c = count ? parseInt(count) : 1;
      console.log(`  [${u.username}] sends ${c} likes`);
      return { event: "like", data: { userId: u.userId, username: u.username, count: c, isFollower: true } };
    },
  },
  // ── TikTok event: gift ──────────────────────────
  {
    pattern: /^(?:gift|g)\s+(\S+)\s*(\d+)?$/i,
    requiresUser: true,
    build: ([, giftName, count], u) => {
      const c = count ? parseInt(count) : 1;
      console.log(`  [${u.username}] sends a gift: ${giftName} x${c}`);
      return {
        event: "gift",
        data: {
          userId: u.userId,
          username: u.username,
          giftName: giftName.trim(),
          count: c,
          lobbyPoints: calcGiftPoints(giftName, c),
          isFollower: true,
        },
      };
    },
  },
  // ── TikTok event: comment ───────────────────────
  {
    pattern: /^(?:comment|chat|c)\s+(.+)$/i,
    requiresUser: true,
    build: ([, text], u) => {
      console.log(`  [${u.username}] comments: "${text.trim()}"`);
      return { event: "comment", data: { userId: u.userId, username: u.username, text: text.trim() } };
    },
  },
  // ── Revive command ──────────────────────────
  {
    pattern: /^(?:revive|r)\s+@?(\S+)$/i,
    requiresUser: true,
    build: ([, name], u) => {
      const target = name.trim();
      console.log(`  [${u.username}] issues revive command for @${target}`);
      return { event: "comment", data: { userId: u.userId, username: u.username, text: `revive @${target}` } };
    },
  },
  // ── Cover command ───────────────────────────
  {
    pattern: /^(?:cover|cov)\s+@?(\S+)$/i,
    requiresUser: true,
    build: ([, name], u) => {
      const target = name.trim();
      console.log(`  [${u.username}] issues cover command for @${target}`);
      return { event: "comment", data: { userId: u.userId, username: u.username, text: `cover @${target}` } };
    },
  },
  // ── TikTok event: leave ─────────────────────────
  {
    pattern: /^(?:leave|l)\s*(\S*)$/i,
    requiresUser: true,
    build: ([, id], u) => {
      const userId = id || u.userId;
      console.log(`  [${u.username}] leaves the stream room`);
      if (!id) _activeUser = null;
      return { event: "leave", data: { userId } };
    },
  },
  // ── Game admin ──────────────────────────────────
  {
    pattern: /^(?:kill|k)\s+(\S+)$/i,
    build: ([, name]) => {
      const username = name.trim();
      _userMap.set(username.toLowerCase(), _userMap.get(username.toLowerCase()) ?? `dev_${username.toLowerCase()}`);
      return { event: "kill", data: { username } };
    },
  },
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
    pattern: /^(?:spawn|sp)\s+(\S+)$/i,
    build: ([, name]) => {
      const username = name.trim();
      _userMap.set(username.toLowerCase(), _userMap.get(username.toLowerCase()) ?? `dev_${username.toLowerCase()}`);
      return { event: "spawn_angel", data: { name: username } };
    },
  },
  {
    pattern: /^(?:melee|m)\s+(\S+)$/i,
    build: ([, name]) => {
      const username = name.trim();
      _userMap.set(username.toLowerCase(), _userMap.get(username.toLowerCase()) ?? `dev_${username.toLowerCase()}`);
      return { event: "spawn_angel", data: { name: username, class: "melee" } };
    },
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
  {
    pattern: /^lobby$/i,
    build: () => ({ event: "lobby_update", data: {} }),
  },
  {
    pattern: /^lobby_clear$/i,
    build: () => ({ event: "lobby_clear", data: {} }),
  },
  // ── Game lifecycle ──
  {
    pattern: /^(?:next|next_match|reset)$/i,
    build: () => ({ event: "next_match", data: {} }),
  },
];

/** Convert gift name to lobby points. */
function calcGiftPoints(name: string, count: number): number {
  const lower = name.toLowerCase();
  if (lower.includes("capsule") || lower.includes("lion")) return 500 * count;
  if (lower.includes("donut") || lower.includes("diamond")) return 50 * count;
  if (lower.includes("rose") || lower.includes("flower")) return 10 * count;
  return 0;
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
      // 🛡️ Context Guard Evaluation
      if (cmd.requiresUser && !_activeUser) {
        console.log("  ✗ Guard Error: You must specify a user first using 'be <name>' or 'join <name>' before using this command.");
        return true;
      }

      const mockFallback = { userId: "dev", username: "Dev" };
      const result = cmd.build(m, _activeUser ?? mockFallback);

      if (result) {
        send(result);
      }
      return true;
    }
  }
  return false;
}

/** Tab auto-completion handler for readline */
function completer(line: string): [string[], string] {
  // If there are no spaces yet, we are completing the primary command name
  if (!line.includes(" ")) {
    // Filter out single-letter aliases so they don't cause artificial conflicts
    const commandCompletions = [
      "become", "be", "join", "like", "gift", "comment", "chat",
      "revive", "cover", "leave", "start", "go", "kill", "wave",
      "angel", "spawn", "melee", "config", "set", "march",
      "lobby", "lobby_clear", "presets", "run", "help", "exit", "quit",
      "next", "reset"
    ];

    const hits = commandCompletions.filter((c) => c.startsWith(line.toLowerCase()));

    // Commands that require arguments get an automatic trailing space when uniquely matched
    const commandsWithArgs = [
      "become", "be", "join", "like", "gift", "comment", "chat",
      "revive", "cover", "kill", "wave", "angel", "spawn", "melee",
      "config", "set", "run"
    ];

    // Scenario A: Exactly one unique match found -> auto-complete and append a trailing space
    if (hits.length === 1 && hits[0] != null) {
      const matchedCmd = hits[0];
      const finalCompletion = commandsWithArgs.includes(matchedCmd) ? `${matchedCmd} ` : matchedCmd;
      return [[finalCompletion], line];
    }

    // Scenario B: Multiple conflicting options found -> show options on double-tab
    return [hits.length ? hits : commandCompletions, line];
  }

  // Case 2: A space exists, meaning we are completing arguments!
  const firstSpaceIndex = line.indexOf(" ");
  const command = line.substring(0, firstSpaceIndex).toLowerCase().trim();
  const argPrefix = line.substring(firstSpaceIndex + 1);

  // Preset auto-complete for the 'run' command
  if (command === "run") {
    try {
      if (fs.existsSync(PRESETS_DIR)) {
        const files = fs.readdirSync(PRESETS_DIR)
          .filter((f) => f.endsWith(".txt"))
          .map((f) => f.replace(/\.txt$/, ""));

        const hits = files.filter((name) => name.toLowerCase().startsWith(argPrefix.toLowerCase()));
        const completions = hits.map((h) => `${line.substring(0, firstSpaceIndex)} ${h}`);
        return [completions, line];
      }
    } catch { /* Fail silently */ }
    return [[], line];
  }

  // Auto-complete active user names from context registry
  if (["kill", "k", "revive", "r", "spawn", "sp", "melee", "m", "be", "become", "cover", "cov"].includes(command)) {
    const usernames = Array.from(_userMap.keys());
    const hits = usernames.filter((name) => name.toLowerCase().startsWith(argPrefix.toLowerCase()));
    const completions = hits.map((h) => `${line.substring(0, firstSpaceIndex)} ${h}`);
    return [completions, line];
  }

  // Auto-complete devil wave difficulties
  if (["wave", "w"].includes(command)) {
    const difficulties = ["normal", "hard", "boss"];
    const hits = difficulties.filter((d) => d.startsWith(argPrefix.toLowerCase()));
    const completions = hits.map((h) => `${line.substring(0, firstSpaceIndex)} ${h}`);
    return [completions, line];
  }

  return [[], line];
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

  const rl = readline.createInterface({
    input,
    output,
    prompt: "> ",
    completer: completer
  });
  rl.prompt();

  for await (const line of rl) {
    const trimmed = line.trim();
    if (!trimmed) { rl.prompt(); continue; }

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

    let matched = false;
    for (const cmd of commands) {
      const m = trimmed.match(cmd.pattern);
      if (m) {
        if (cmd.requiresUser && !_activeUser) {
          console.log("  ✗ Guard Error: You must specify a user first using 'be <name>' or 'join <name>' before using this command.");
        } else {
          const mockFallback = { userId: "dev", username: "Dev" };
          const res = cmd.build(m, _activeUser ?? mockFallback);
          if (res) send(res);
        }
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
