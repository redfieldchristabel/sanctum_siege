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

// ─── Help text ───────────────────────────────────────────────

const HELP = `
  ⚔️  Sanctum Siege — Dev CLI

  Commands:
    start / go          Start game (idle → 3s countdown → fight)
    join <name>          Simulate a viewer joining
    leave <userId>       Viewer leaves
    like [count]         Send likes (default: 1)
    gift <name> [count]  Simulate a gift
    comment <text>       Chat comment from viewer
    wave [type]          Spawn devil wave (normal/hard/boss)
    angel <count>        Spawn angels
    config <key> <val>   Change game config at runtime
    run <name>           Run a preset script (presets/<name>.txt)
    presets              List available presets
    help                 Show this
    exit / quit          Disconnect

  Shortcuts:
    j <name>        = join
    l <id>          = leave
    g <n> [c]       = gift
    w [type]        = wave

`.trim();

// ─── Command → event mapping ─────────────────────────────────

interface CommandEntry {
  pattern: RegExp;
  build: (match: RegExpMatchArray) => { event: string; data: Record<string, unknown> };
}

const commands: CommandEntry[] = [
  {
    pattern: /^(?:game_start|start|begin|go)$/i,
    build: () => ({ event: "game_start", data: {} }),
  },
  {
    pattern: /^(?:join|j)\s+(.+)$/i,
    build: ([, name]) => ({
      event: "join",
      data: { userId: `dev_${Date.now()}`, username: name.trim() },
    }),
  },
  {
    pattern: /^(?:leave|l)\s+(\S+)$/i,
    build: ([, id]) => ({ event: "leave", data: { userId: id } }),
  },
  {
    pattern: /^(?:like|likes?)\s*(\d+)?$/i,
    build: ([, count]) => ({
      event: "like",
      data: { userId: "dev", count: count ? parseInt(count) : 1 },
    }),
  },
  {
    pattern: /^(?:gift|g)\s+(\S+)\s*(\d+)?$/i,
    build: ([, name, count]) => ({
      event: "gift",
      data: {
        userId: "dev",
        username: "Dev",
        giftName: name.trim(),
        count: count ? parseInt(count) : 1,
      },
    }),
  },
  {
    pattern: /^(?:comment|chat|c)\s+(.+)$/i,
    build: ([, text]) => ({
      event: "comment",
      data: { userId: "dev_chat", username: "TestUser", text: text.trim() },
    }),
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
];

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

/** Execute a single CLI command line (same parsing as interactive mode). */
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
      const { event, data } = cmd.build(m);
      sendEvent(event, data);
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
    const ok = executeLine(line);
    if (!ok) console.log(`  ? Skipped: "${line}"`);
    await new Promise((r) => setTimeout(r, 300)); // delay between commands
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

    // Built-in commands (not sent over WebSocket)
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
        const { event, data } = cmd.build(m);
        sendEvent(event, data);
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

  // If first arg is a preset name, run it immediately
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
    // Not a known command — treat as preset name
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
