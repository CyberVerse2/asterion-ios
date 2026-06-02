#!/usr/bin/env node
import { spawn } from "node:child_process";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

const rootDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const skypadiEnvPath = "/Users/thecyberverse/Code/skypadi/backend/.env";
const stateDir = path.join(rootDir, ".codex");
const statePath = path.join(stateDir, "iphone-build-refresh-state.json");
const buildScript = path.join(rootDir, "scripts", "build-install-launch-iphone.sh");

const recipient = "ejioforcelestine77@gmail.com";
const firstDueAt = new Date("2026-05-31T02:15:00+01:00");
const refreshIntervalMs = 6 * 24 * 60 * 60 * 1000;
const resendModulePath = "/Users/thecyberverse/Code/skypadi/backend/node_modules/resend/dist/index.mjs";
const forceDue = process.env.ASTERION_IPHONE_REFRESH_FORCE_DUE === "1";
const forceCycleId = process.env.ASTERION_IPHONE_REFRESH_FORCE_CYCLE_ID?.trim();
const replyPollWindowMs = Number(process.env.ASTERION_IPHONE_REFRESH_REPLY_POLL_MS ?? 12 * 60 * 1000);
const replyPollIntervalMs = Number(process.env.ASTERION_IPHONE_REFRESH_REPLY_POLL_INTERVAL_MS ?? 20 * 1000);

function parseEnv(contents) {
  const env = {};
  for (const rawLine of contents.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith("#")) continue;
    const separator = line.indexOf("=");
    if (separator === -1) continue;
    const key = line.slice(0, separator).trim();
    let value = line.slice(separator + 1).trim();
    if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
      value = value.slice(1, -1);
    }
    env[key] = value;
  }
  return env;
}

async function loadState() {
  try {
    return JSON.parse(await readFile(statePath, "utf8"));
  } catch (error) {
    if (error?.code === "ENOENT") return {};
    throw error;
  }
}

async function saveState(state) {
  await mkdir(stateDir, { recursive: true });
  await writeFile(statePath, `${JSON.stringify(state, null, 2)}\n`);
}

function nextDueAt(state) {
  if (!state.lastSuccessAt) return firstDueAt;
  return new Date(new Date(state.lastSuccessAt).getTime() + refreshIntervalMs);
}

function cycleIdFor(date) {
  return date.toISOString().slice(0, 10).replaceAll("-", "");
}

function htmlEscape(value) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

async function sendReadyEmail(resend, from, replyTo, cycleId) {
  const subject = `Asterion iPhone refresh due [${cycleId}]`;
  const text = [
    "Asterion's iPhone development build refresh is due.",
    "",
    "Please turn on/unlock the iPhone, keep it on the same Wi-Fi as the Mac, and reply to this email with ok when it is ready.",
    "I will check for your reply immediately for about 12 minutes, then retry on the next scheduled run if needed.",
    "",
    `Reply address: ${replyTo}`,
  ].join("\n");

  const { error } = await resend.emails.send({
    from,
    to: recipient,
    replyTo,
    subject,
    text,
    html: `<p>Asterion's iPhone development build refresh is due.</p><p>Please turn on/unlock the iPhone, keep it on the same Wi-Fi as the Mac, and reply to this email with <strong>ok</strong> when it is ready.</p><p>I will check for your reply immediately for about 12 minutes, then retry on the next scheduled run if needed.</p><p>Reply address: ${htmlEscape(replyTo)}</p>`,
  });

  if (error) {
    throw new Error(`Resend email send failed: ${error.message}`);
  }
}

async function findReply(resend, replyTo, since) {
  const { data, error } = await resend.emails.receiving.list({ limit: 50 });
  if (error) {
    throw new Error(`Resend inbound list failed: ${error.message}`);
  }

  const emails = Array.isArray(data?.data) ? data.data : Array.isArray(data) ? data : [];
  for (const candidate of emails) {
    const createdAt = new Date(candidate.created_at ?? candidate.createdAt ?? 0);
    const recipients = Array.isArray(candidate.to) ? candidate.to : [candidate.to].filter(Boolean);
    if (createdAt < since) continue;
    if (!recipients.some((to) => String(to).toLowerCase().includes(replyTo.toLowerCase()))) continue;
    if (!String(candidate.from ?? "").toLowerCase().includes(recipient.toLowerCase())) continue;

    const id = candidate.id;
    if (!id) return candidate;
    const full = await resend.emails.receiving.get(id);
    if (full.error) {
      throw new Error(`Resend inbound fetch failed: ${full.error.message}`);
    }
    return full.data ?? candidate;
  }

  return null;
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function waitForReply(resend, replyTo, since) {
  const deadline = Date.now() + replyPollWindowMs;
  while (Date.now() <= deadline) {
    const reply = await findReply(resend, replyTo, since);
    if (reply) return reply;
    await sleep(replyPollIntervalMs);
  }
  return null;
}

function run(command, args, cwd) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { cwd, stdio: "inherit" });
    child.on("error", reject);
    child.on("exit", (code) => {
      if (code === 0) resolve();
      else reject(new Error(`${command} ${args.join(" ")} exited with ${code}`));
    });
  });
}

const state = await loadState();
const now = new Date();
const dueAt = forceDue ? now : nextDueAt(state);

if (now < dueAt) {
  console.log(`No iPhone refresh due. Next due date: ${dueAt.toISOString()}`);
  process.exit(0);
}

const env = parseEnv(await readFile(skypadiEnvPath, "utf8"));
const resendApiKey = env.RESEND_API_KEY;
const inboundDomain = env.RESEND_INBOUND_DOMAIN;
if (!resendApiKey || !inboundDomain) {
  throw new Error(`RESEND_API_KEY and RESEND_INBOUND_DOMAIN are required in ${skypadiEnvPath}`);
}

const { Resend } = await import(resendModulePath);
const resend = new Resend(resendApiKey);
const cycleId = forceCycleId || cycleIdFor(dueAt);
const replyTo = `asterion-iphone-refresh-${cycleId}@${inboundDomain}`;
const from = `Asterion Build Refresh <asterion-iphone-refresh@${inboundDomain}>`;

let promptSentAt = new Date(state.promptSentAt ?? now);
let activeReplyTo = state.replyTo ?? replyTo;
if (state.promptCycleId !== cycleId) {
  await sendReadyEmail(resend, from, replyTo, cycleId);
  promptSentAt = now;
  activeReplyTo = replyTo;
  await saveState({
    ...state,
    promptCycleId: cycleId,
    promptSentAt: now.toISOString(),
    replyTo,
    forceTest: forceDue || undefined,
  });
  console.log(`Sent iPhone readiness email to ${recipient}. Polling for a reply to ${replyTo}.`);
}

const reply = await waitForReply(resend, activeReplyTo, promptSentAt);
if (!reply) {
  console.log(`No readiness reply found yet for ${activeReplyTo}.`);
  process.exit(0);
}

console.log(`Readiness reply found (${reply.id ?? "unknown id"}). Running iPhone build/install/launch.`);
await run(buildScript, [], rootDir);
await saveState({
  lastSuccessAt: new Date().toISOString(),
  lastReplyId: reply.id ?? null,
});
console.log("iPhone refresh completed successfully.");
