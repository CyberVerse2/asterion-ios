import { parseArgs } from 'node:util';

import { loadConfig } from './config.js';
import { Database } from './db.js';
import { log } from './log.js';
import { ScrapeRunner, type RunOptions } from './runner.js';

const usage = `Usage: node dist/cli.js [options]

One pass of the novel scraper, then exit (the long-lived service is dist/server.js).

  --dry-run              Read-only: report what would be fetched; no database writes.
  --probe                With --dry-run, fetch the first planned chapter of each novel to check it.
  --novel <id|slug>      Limit to a novel by novels.id or novelfire slug (repeatable).
  --max-chapters <n>     Cap chapters fetched in this pass (all novels together).
  --max-per-novel <n>    Cap chapters fetched per novel (default MAX_CHAPTERS_PER_NOVEL).
  --json                 Print the full run summary as JSON at the end.
`;

function positive(value: string | undefined, name: string): number | undefined {
  if (value === undefined) return undefined;
  const number = Number(value);
  if (!Number.isInteger(number) || number < 1) throw new Error(`${name} must be a positive integer`);
  return number;
}

async function main(): Promise<void> {
  const { values } = parseArgs({
    options: {
      'dry-run': { type: 'boolean', default: false },
      probe: { type: 'boolean', default: false },
      novel: { type: 'string', multiple: true },
      'max-chapters': { type: 'string' },
      'max-per-novel': { type: 'string' },
      json: { type: 'boolean', default: false },
      help: { type: 'boolean', default: false }
    }
  });
  if (values.help) {
    console.log(usage);
    return;
  }

  const options: RunOptions = { trigger: 'cli', dryRun: values['dry-run'] ?? false, probe: values.probe ?? false };
  const ids: number[] = [];
  const slugs: string[] = [];
  for (const novel of values.novel ?? []) {
    if (/^\d+$/.test(novel)) ids.push(Number(novel));
    else slugs.push(novel.replace(/^https?:\/\/novelfire\.net\/book\//, '').replace(/\/.*$/, ''));
  }
  if (ids.length > 0) options.novelIds = ids;
  if (slugs.length > 0) options.slugs = slugs;
  const maxChapters = positive(values['max-chapters'], '--max-chapters');
  if (maxChapters !== undefined) options.maxChaptersPerRun = maxChapters;
  const perNovel = positive(values['max-per-novel'], '--max-per-novel');
  if (perNovel !== undefined) options.maxChaptersPerNovel = perNovel;

  const config = loadConfig();
  const db = new Database(config.databaseUrl);
  const runner = new ScrapeRunner(config, db);
  process.on('SIGINT', () => {
    log.warn('SIGINT: finishing in-flight chapters, then stopping');
    runner.abort();
  });

  try {
    const summary = await runner.start(options)!;
    if (values.json) console.log(JSON.stringify(summary, null, 2));
    process.exitCode = summary.status === 'failed' ? 1 : 0;
  } finally {
    await db.close();
  }
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
