const { Queue, Worker } = require('bullmq');
const Redis = require('ioredis');
const Sentry = require('@sentry/node');
const { pool, redis } = require('./db');
const { billTick, TICK_SECONDS } = require('./billing');
const { finishCall } = require('./callctl');

// Ring timeouts and per-15s billing live in Redis (BullMQ), not in process memory, so a restart/deploy
// no longer drops calls and several API containers can run side by side.
const RING_TIMEOUT_MS = 20000;
const connection = () => new Redis(process.env.REDIS_URL, { maxRetriesPerRequest: null });

const queue = new Queue('calls', {
  connection: connection(),
  defaultJobOptions: { removeOnComplete: true, removeOnFail: 200, attempts: 3, backoff: { type: 'exponential', delay: 1000 } },
});

const ringTimeout = (callId) => queue.add('ring-timeout', { callId }, { delay: RING_TIMEOUT_MS, jobId: `ring-${callId}` });
const scheduleTick = (callId, tick, delay = TICK_SECONDS * 1000) =>
  queue.add('bill-tick', { callId, tick }, { delay, jobId: `tick-${callId}-${tick}` });

// Every job is safe to run twice (status-guarded updates + ledger idempotency keys)
async function handle(job) {
  const { callId, tick } = job.data;

  if (job.name === 'ring-timeout') {
    await finishCall(callId, 'missed', ['ringing']); // does nothing if the partner already answered
    return;
  }

  if (job.name === 'bill-tick') {
    const call = (await pool.query(`SELECT * FROM calls WHERE id=$1 AND status='active'`, [callId])).rows[0];
    if (!call) return; // call already over: the chain stops here
    if (tick >= 4 && !(await redis.exists(`call:hb:${callId}`))) return void (await finishCall(callId, 'ended')); // both phones gone
    if (!(await billTick(call, tick))) return void (await finishCall(callId, 'ended')); // wallet empty
    await scheduleTick(callId, tick + 1);
    return;
  }

  if (job.name === 'sweep') { // safety net, once a minute: heal anything a lost job could leave behind
    const stuck = await pool.query(`SELECT id FROM calls WHERE status='ringing' AND created_at < now() - interval '60 seconds'`);
    for (const r of stuck.rows) await finishCall(r.id, 'missed', ['ringing']);
    const active = await pool.query(
      `SELECT id, billed_seconds, EXTRACT(EPOCH FROM now() - started_at) AS elapsed FROM calls WHERE status='active' AND started_at < now() - interval '2 minutes'`);
    for (const r of active.rows) {
      if (!(await redis.exists(`call:hb:${r.id}`))) { await finishCall(r.id, 'ended'); continue; }
      if (Number(r.elapsed) - r.billed_seconds > 60) { // billing chain broke: restart it where it stopped
        const next = Math.floor(r.billed_seconds / TICK_SECONDS) + 1;
        await scheduleTick(r.id, next, 0);
      }
    }
  }
}

function startWorker() {
  const worker = new Worker('calls', handle, { connection: connection(), concurrency: 10 });
  worker.on('failed', (job, err) => {
    console.error('[queue] job failed:', job?.name, err.message);
    Sentry.captureException(err);
  });
  queue.add('sweep', {}, { repeat: { every: 60000 } }).catch((e) => console.error('[queue] sweep schedule failed', e));
  return worker;
}

module.exports = { queue, startWorker, ringTimeout, scheduleTick };
