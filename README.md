# Scribe

Record your screen with narration, and Scribe turns it into a structured,
illustrated user manual: it transcribes the voice-over, pulls screenshots
aligned to what's being said, and has Claude write the steps. Export to
Markdown, HTML, or PDF. Processing is paid for with prepaid credits via Stripe.

This repository implements the SPEC in milestone order (see
[Status](#status--milestones)). It's a Rails 8 monolith with Hotwire/Stimulus,
PostgreSQL, and background jobs.

---

## How it works

```
Browser (recorder)            Rails                         Jobs (Solid Queue)
─────────────────             ─────                         ──────────────────
getDisplayMedia + mic   ─tus─▶ /files (resumable upload)
MediaRecorder(5s chunks)       POST /recordings/:id/complete ─▶ reserve credits
                                                                │
                                                    TranscribeJob ─▶ STT provider
                                                    ExtractFramesJob ─▶ ffmpeg scene detect
                                                    GenerateManualJob ─▶ Claude (vision + tools)
Review/Edit UI  ◀── manual JSON                     ExportJob ─▶ Exporters::Registry
Buy credits     ── Checkout ─▶ Stripe ── webhook ─▶ credit ledger
```

The pipeline is a linear **state machine** on `recordings.status`:

```
recording → uploaded → transcribing → extracting_frames → generating_manual → complete
                                  └─────────────── failed (records failed_stage) ◀┘
```

Each stage is an idempotent, retryable job that advances the status and enqueues
the next on success; on failure it records `failed_stage`/`error_message`, voids
the credit hold, and reports to Sentry.

### Where Claude is and isn't used

The Anthropic API has **no speech-to-text**. Transcription goes through a
dedicated STT provider behind `Transcription::Base`. Claude is used to segment
the transcript into steps, choose the best frame per step (vision), and write
the title/summary/step prose — emitted through a forced tool schema
(`emit_manual`) for structured output.

---

## Tech stack

| Concern        | Choice                                                              |
|----------------|---------------------------------------------------------------------|
| Backend        | Ruby on Rails 8 (Hotwire/Turbo + Stimulus)                          |
| Database       | PostgreSQL                                                          |
| Background jobs| **Solid Queue** (Postgres-backed — see decision note below)         |
| Object storage | S3-compatible behind `Storage`; disk adapter for dev/test           |
| Resumable upload | tus (`tus-server` mounted at `/files`, `tus-js-client` in browser) |
| Media          | system `ffmpeg`/`ffprobe`                                           |
| Transcription  | provider-abstracted: Deepgram / OpenAI (hosted) / faster-whisper / `stub` |
| AI             | Anthropic Messages API (plain HTTP client) + offline fake           |
| PDF            | HTML exporter rendered with **WeasyPrint** (CLI, no browser)        |
| Auth           | Rails 8 built-in authentication (session-based, per-user)           |
| Billing        | Stripe Checkout (one-time) + append-only credit ledger             |
| Observability  | Sentry (server + jobs), wired from milestone 0                      |

---

## Getting started (local dev)

System deps: Ruby (see `.ruby-version`), `ffmpeg`, and `weasyprint` (PDF export).
Postgres and object storage (MinIO) come from `docker compose`.

```bash
docker compose up -d          # Postgres + MinIO (+ auto-creates the bucket)
bundle install
cp .env.example .env          # fill in keys (see "full flow" below)

bin/rails db:prepare          # create + migrate (primary + queue DBs)
bin/rails db:seed             # seed credit packs (idempotent)

bin/dev                       # command-up: web server + Solid Queue worker
```

`bin/dev` is the single command-up for the dev environment — it runs Puma and
the Solid Queue worker together (via overmind/foreman if installed, otherwise
directly) and tears both down on Ctrl-C. Development uses a dedicated
`scribe_development_queue` database for jobs, matching production. `.env` is
loaded automatically in development (via `dotenv-rails`); it is **not** loaded in
test, so the suite stays offline.

Install the system tools (macOS): `brew install ffmpeg weasyprint`.
Ubuntu: `sudo apt-get install -y ffmpeg weasyprint`.

### Testing the whole flow locally (real transcription + manual)

The pipeline runs **offline by default** (stub STT + fake Claude), so you can
demo end-to-end with zero keys or spend. To exercise the real services:

1. `docker compose up -d` — Postgres + MinIO with the `scribe` bucket.
2. In `.env`, set `STORAGE_ADAPTER=s3` (MinIO creds are pre-filled) so uploads,
   frames and exports go through signed URLs.
3. Set `ANTHROPIC_API_KEY` for manual generation.
4. Choose a real transcription provider (required for actual transcripts):
   - `TRANSCRIPTION_PROVIDER=deepgram` + `DEEPGRAM_API_KEY`, or
   - `TRANSCRIPTION_PROVIDER=openai` + `OPENAI_API_KEY` (model via
     `OPENAI_TRANSCRIBE_MODEL`, default `whisper-1`), or
   - `TRANSCRIPTION_PROVIDER=whisper` + `WHISPER_BIN` pointing at a local
     faster-whisper / whisper-ctranslate2 CLI that emits JSON segments.
5. `bin/dev`, open http://localhost:3000, sign up, buy/seed credits, record.

MinIO console: http://localhost:9001 (`minioadmin` / `minioadmin`).

Then open http://localhost:3000, sign up, and record. With no
`ANTHROPIC_API_KEY` and `TRANSCRIPTION_PROVIDER=stub`, the full pipeline runs
**offline** using deterministic stubs — no external spend.

### Running checks

```bash
bin/rails test                # full suite
bin/rubocop                   # style (rails-omakase)
bin/brakeman -i config/brakeman.ignore   # security scan
```

CI (`.github/workflows/ci.yml`) runs all three with a Postgres service and
ffmpeg installed. A SessionStart hook (`bin/web-setup`) provisions the same for
Claude Code web sessions.

---

## Key modules

- `app/services/credits/` — the **ledger** (`Ledger.hold!/settle!/void!`),
  metering (`Meter`). Balance is always derived: `SUM(amount) WHERE state IN
  ('settled','pending')`. All credit mutations go through here.
- `app/services/transcription/` — `Base.build` selects the provider; `Stub` is
  the offline default; `Deepgram`, `Openai` (hosted, real STT) and `Whisper`
  (local CLI) are real implementations. Each separates the HTTP call (`#fetch`)
  from response mapping (`#parse`) so mapping is unit-tested offline.
- `app/services/media/` — `Probe` (ffprobe), `AudioExtractor`, `FrameExtractor`
  (scene detect + periodic fallback + on-demand seeks + thumbnails).
- `app/services/manual_generation/` — `ToolSchema` (forced output), `Generator`
  (prompt build, chunking, vision images).
- `app/services/anthropic/` — `Client` (HTTP) and `FakeClient` (offline).
- `app/services/exporters/` — `Registry` + `Markdown`/`Html`/`Pdf`. **Adding a
  format = one subclass + `Registry.register`.**
- `app/jobs/` — `TranscribeJob → ExtractFramesJob → GenerateManualJob`, plus
  `ExportJob` and `PurgeExpiredRecordingsJob` (retention). Shared retry/failure
  handling in `PipelineStage`: transient errors (network/timeout) auto-retry with
  backoff; permanent or exhausted failures record `failed_stage` and void the
  hold. A failed recording can be re-run from its stage via `POST
  /recordings/:id/retry`.
- `app/services/recording_purge.rb` — delete a recording's stored objects + rows
  (`destroy!`) and retention purge of the raw video while keeping the manual
  (`purge_raw_video!`).

---

## Decisions (SPEC §17)

Defaults were chosen where the SPEC left a fork; each is marked `TODO(decision:)`
in code so it's greppable. Confirm before hardening.

- **Background jobs:** the SPEC defaulted to GoodJob; this build uses **Solid
  Queue** instead — it's the Rails 8 built-in, equally Postgres-backed (no extra
  Redis to operate, which was the SPEC's stated reason for GoodJob), so the
  operational profile matches with one fewer dependency.
- **STT provider:** offline `stub` by default; Deepgram/whisper ready to swap via
  `TRANSCRIPTION_PROVIDER`. *(open)*
- **Auth:** Rails 8 built-in authentication. *(chosen)*
- **Pricing / `CREDITS_PER_MINUTE`:** flat **1 credit/minute**; seed packs
  Starter 60 / Pro 300 / Studio 1000 with placeholder prices + Stripe price ids.
  *(open)*
- **Export billing:** built-in exports cost **0 credits**; per-format cost is
  configurable (`Scribe.config.export_credit_costs`). *(default)*
- **Retention:** raw video kept **30 days** (`RAW_VIDEO_RETENTION_DAYS`), then
  auto-purged by `PurgeExpiredRecordingsJob` (daily, see `config/recurring.yml`);
  manuals persist. *(window open for confirmation)*
- **Metering model:** flat per-minute now; `settle!(actual_amount:)` already
  accepts token-based actuals without a schema change. *(default)*

---

## Status / milestones

| # | Milestone | State |
|---|-----------|-------|
| 1 | Scaffold (Rails, Postgres, jobs, storage, auth, Sentry, CI) | ✅ |
| 2 | Record + resumable upload (Stimulus recorder, tus) | ✅ backend + recorder; playback via signed URLs |
| 3 | Pipeline + transcription (state machine, audio extract, provider) | ✅ |
| 4 | Frames + manual (scene frames, Claude alignment, review/edit UI) | ✅ |
| 5 | Exports (registry + Markdown/HTML/PDF, signed download) | ✅ (PDF via WeasyPrint) |
| 6 | Credits + Stripe (ledger, packs, Checkout, webhook, 402 gating) | ✅ |
| 7 | Hardening (retries, failure UI, delete/retention, usage logging) | ✅ — automatic transient-error retries + per-stage manual retry, failure/retry + delete UI, `RecordingPurge` + daily retention job, token-usage logging |

### Tests (SPEC §15)

- `test/models/credit_transaction_test.rb` — ledger math, hold→settle/void, and
  no double-spend under concurrency.
- `test/services/exporters_test.rb` — golden Markdown/HTML, PDF render via
  WeasyPrint, registry behaviour.
- `test/services/storage_s3_test.rb` — S3/MinIO adapter (stubbed): put/get/
  delete, presigned-URL shape, SSE toggle.
- `test/services/transcription_test.rb` — provider selection + Deepgram/OpenAI
  response mapping (canned payloads) + missing-key guard.
- `test/integration/stripe_webhook_test.rb` — webhook idempotency (replay → one
  grant).
- `test/integration/pipeline_test.rb` — end-to-end with a real short ffmpeg
  fixture, stubbed STT + Claude; success and failure paths.
- `test/integration/recordings_flow_test.rb` — `/complete` credit reservation,
  402 gating, per-user authorization.

---

## Security & privacy (SPEC §14)

- All downloads via short-lived **signed URLs** (HMAC for the disk adapter,
  presigned for S3); no public buckets. S3 objects use SSE.
- Per-user authorization on every recording/manual/export/frame.
- Stripe webhook signature verification; Anthropic/STT/Stripe keys are
  server-side only and never reach the browser.
- `getDisplayMedia` requires HTTPS + a user gesture (enforced by the browser).
