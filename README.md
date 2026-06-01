# Scribe

Record your screen with narration (or hand it a recording you already have), and
Scribe turns it into a structured, illustrated user manual: it transcribes the
voice-over, pulls screenshots aligned to what's being said, and has an LLM write
the steps. Export to Markdown, HTML, or PDF.

**Scribe is local-first.** It runs on *your* machine with *your* own API keys (or
a fully local model), and everything — the database, your recordings, and the
generated manuals — stays in a single folder you control. There are no accounts,
no billing, and nothing phones home.

- 🔑 **Your keys, your machine.** Use your own Anthropic or OpenAI key, or point
  Scribe at a local llama model (Ollama / llama.cpp / LM Studio) so nothing leaves
  the box.
- 📁 **One folder = all your data.** SQLite database + recordings + generated
  manual files all live under one data dir. Mount it into Docker and back it up
  by copying a folder.
- 🖥️ **Web or CLI.** Record in the browser, upload an existing video, or process a
  file straight from the command line.
- 📄 **Results as files.** Every finished manual is written out as
  `manual.json` / `.md` / `.html` / `.pdf` next to the recording — not locked
  inside a database.

---

## Quick start (Docker)

The fastest way to run Scribe. You need Docker and one of: an Anthropic API key,
or a local model server (see [scenarios](#docker-usage--all-scenarios)).

```bash
# 1. Create your config from the template (gitignored):
curl -O https://raw.githubusercontent.com/esse/scribe/main/.env.example
mv .env.example .env

# 2. Edit .env and set at least:
#      SECRET_KEY_BASE=...   # one-time secret so signed URLs survive restarts;
#                            #   generate with:  openssl rand -hex 32
#      ANTHROPIC_API_KEY=sk-ant-...    # your own key (or use a local model)

# 3. Run it — data persists in ./data on the host (mounted at /data):
docker run -p 3000:80 -v "$PWD/data:/data" --env-file=.env essepl/scribe:latest
# → http://localhost:3000
```

All configuration is passed with `--env-file=.env`; only the keys you actually
set override the image's local-first defaults. Stop with `Ctrl-C`; your
recordings and manuals persist in `./data` and survive restarts and upgrades.

> **Build from source instead of pulling?** `docker build -t essepl/scribe:latest .`
> then use the same `docker run` command. (Substitute your own tag if you prefer,
> e.g. `-t scribe` + `docker run … scribe`.)

> The pipeline runs **offline by default** (a deterministic stub transcriber and
> a fake LLM), so even with *no* keys you can click through the whole flow with
> zero spend — you just won't get a real transcript or AI-written steps.

---

## How it works

```
Browser (recorder)            Rails                         Jobs (Solid Queue)
─────────────────             ─────                         ──────────────────
getDisplayMedia + mic   ─tus─▶ /files (resumable upload)
MediaRecorder(5s chunks)       POST /recordings/:id/complete
  — or —                                                        │
upload an existing file ─────▶ POST /recordings/upload          │
  — or —                                                        ▼
CLI: scribe:ingest[path] ────────────────────────▶  TranscribeJob ─▶ STT provider
                                                    ExtractFramesJob ─▶ ffmpeg scene detect
                                                    GenerateManualJob ─▶ LLM (vision + tools)
Review/Edit UI  ◀── manual JSON                     ExportJob ─▶ Exporters::Registry
                                                    ResultFiles ─▶ data/.../results/*.{json,md,html,pdf}
```

The pipeline is a linear **state machine** on `recordings.status`:

```
recording → uploaded → editing → transcribing → extracting_frames → generating_manual → complete
                                          └─────────────── failed (records failed_stage) ◀┘
```

Each stage is an idempotent, retryable job that advances the status and enqueues
the next on success; on failure it records `failed_stage`/`error_message` and
logs it. A failed recording can be re-run from its stage via
`POST /recordings/:id/retry`.

### Where the LLM is and isn't used

Speech-to-text is **not** done by the LLM — there's no STT in the Anthropic API
or in llama models, so transcription always goes through a dedicated provider
behind `Transcription::Base`. The LLM is used to segment the transcript into
steps, choose the best frame per step (vision), and write the title/summary/step
prose — emitted through a forced tool schema (`emit_manual`) for structured
output. Both the Anthropic client and the local-llama client return the same
response shape, so the pipeline doesn't care which one ran.

---

## Tech stack

| Concern          | Choice                                                                  |
|------------------|-------------------------------------------------------------------------|
| Backend          | Ruby on Rails 8 (Hotwire/Turbo + Stimulus)                              |
| Database         | **SQLite** — a file in the data dir (no external DB service)            |
| Background jobs  | **Solid Queue** (SQLite-backed; runs inside Puma in the container)      |
| Storage          | Local disk under the data dir (served via short-lived signed URLs)      |
| Resumable upload | tus (`tus-server` at `/files`, `tus-js-client` in the browser)          |
| Media            | system `ffmpeg`/`ffprobe`                                               |
| Transcription    | provider-abstracted: **local Whisper** (bundled in the image) / Deepgram / OpenAI / `stub` |
| LLM              | **Anthropic** / **OpenAI** (your key) **or local llama** (OpenAI-compatible) + offline fake |
| PDF              | HTML exporter rendered with **WeasyPrint** (CLI, no browser)            |
| Accounts/billing | none — single implicit local user                                       |

---

## Docker usage — all scenarios

All scenarios use the same image (`essepl/scribe:latest`) and the same mounted
`./data` folder. They differ only in **environment variables** — put them in
`.env` and pass it with `--env-file=.env`. `SECRET_KEY_BASE` is always required.

The run command is identical every time; only the contents of `.env` change:

```bash
docker run -p 3000:80 -v "$PWD/data:/data" --env-file=.env essepl/scribe:latest
```

### 1. Anthropic (your key) + local Whisper — recommended

Best quality. The manual is written by Claude using your own API key; audio is
transcribed **locally** with Whisper so it never leaves the machine. This is the
default — just provide your key:

```ini
# .env
SECRET_KEY_BASE=<openssl rand -hex 32>
ANTHROPIC_API_KEY=sk-ant-...
```

```bash
docker run -p 3000:80 -v "$PWD/data:/data" --env-file=.env essepl/scribe:latest
```

The image bundles `faster-whisper` and pre-downloads the `base` model at build
time, so local transcription works out of the box and fully offline. To bake in
a different size (better accuracy), build from source with a build arg:

```bash
docker build --build-arg WHISPER_MODEL=small -t essepl/scribe:latest .
```

or override at runtime via `WHISPER_MODEL` (downloaded on first use if not
pre-baked).

### 2. Fully local — a llama model + Whisper (nothing leaves the machine)

Run a model server on the host (e.g. [Ollama](https://ollama.com)) with a
**vision-capable** model, then point Scribe at it. No Anthropic key needed.

```bash
# On the host:
ollama serve
ollama pull llama3.2-vision
```

```ini
# .env
SECRET_KEY_BASE=<openssl rand -hex 32>
LLM_PROVIDER=local
LLM_BASE_URL=http://host.docker.internal:11434/v1   # reach the host from the container
LLM_MODEL=llama3.2-vision
TRANSCRIPTION_PROVIDER=whisper
```

```bash
docker run -p 3000:80 -v "$PWD/data:/data" --env-file=.env \
  --add-host=host.docker.internal:host-gateway essepl/scribe:latest
```

`--add-host=host.docker.internal:host-gateway` lets the container reach a server
running on the host. It's needed on **Linux**; Docker Desktop on macOS/Windows
resolves `host.docker.internal` automatically (the flag is harmless there). Any
OpenAI-compatible server works — llama.cpp (`http://host.docker.internal:8080/v1`),
LM Studio (`:1234/v1`), etc.

### 3. OpenAI (your key)

Use OpenAI's hosted models (GPT-4o, etc.) for the manual, with local Whisper for
transcription. Pick a **vision-capable** chat model.

```ini
# .env
SECRET_KEY_BASE=<openssl rand -hex 32>
LLM_PROVIDER=openai
OPENAI_LLM_API_KEY=sk-...
OPENAI_LLM_MODEL=gpt-4o
```

The LLM and OpenAI-transcription keys are **independent**: `OPENAI_LLM_API_KEY`
(+ `OPENAI_BASE_URL`) is for the LLM, `OPENAI_API_KEY` is for STT. They can be
different keys or endpoints. If you only set `OPENAI_API_KEY`, the LLM reuses it,
so one key still covers both.

### 4. Hosted transcription (Deepgram or OpenAI)

If you don't want to run Whisper, use a hosted STT provider with your own key.
Combine with either LLM option above.

```ini
# .env (Deepgram)
SECRET_KEY_BASE=<openssl rand -hex 32>
ANTHROPIC_API_KEY=sk-ant-...
TRANSCRIPTION_PROVIDER=deepgram
DEEPGRAM_API_KEY=...
```

```ini
# .env (OpenAI Whisper API)
TRANSCRIPTION_PROVIDER=openai
OPENAI_API_KEY=...
OPENAI_TRANSCRIBE_MODEL=whisper-1
```

### 5. Offline demo (no keys at all)

Leave `ANTHROPIC_API_KEY` unset and use the stub transcriber. The pipeline runs
end-to-end with deterministic placeholders — handy for trying the UI.

```ini
# .env
SECRET_KEY_BASE=<openssl rand -hex 32>
LLM_PROVIDER=fake
TRANSCRIPTION_PROVIDER=stub
```

### 6. CLI — process an existing recording without the browser

Turn a video you already have into a manual without starting the web server. Drop
the file under `./data` (so the container can see it at `/data`), then run the
rake task in a **one-shot container** (`--rm` removes it when done):

```bash
cp ~/Desktop/demo.mp4 ./data/demo.mp4
docker run --rm -v "$PWD/data:/data" --env-file=.env \
  essepl/scribe:latest bin/rails "scribe:ingest[/data/demo.mp4]"
```

It runs the whole pipeline inline — no background worker needed — and prints
where the result files landed, e.g. `/data/storage/recordings/3/results/` (on the
host that's `./data/storage/recordings/3/results/`). List recordings with:

```bash
docker run --rm -v "$PWD/data:/data" --env-file=.env \
  essepl/scribe:latest bin/rails scribe:list
```

### Behind HTTPS

The container serves plain HTTP by default (for `localhost`). If you put it
behind an HTTPS reverse proxy, set `FORCE_SSL=true` to enable HSTS + secure
cookies.

### Common Docker commands

```bash
# Run in the background with a name you can refer to:
docker run -d --name scribe -p 3000:80 -v "$PWD/data:/data" --env-file=.env essepl/scribe:latest
docker logs -f scribe            # follow logs
docker ps                        # status
docker stop scribe && docker rm scribe   # stop (your ./data is kept)

# Update to a newer image (data in ./data is preserved):
docker pull essepl/scribe:latest
docker stop scribe && docker rm scribe
docker run -d --name scribe -p 3000:80 -v "$PWD/data:/data" --env-file=.env essepl/scribe:latest

# Process an existing video / list recordings (one-shot, no running server):
docker run --rm -v "$PWD/data:/data" --env-file=.env essepl/scribe:latest bin/rails "scribe:ingest[/data/clip.mp4]"
docker run --rm -v "$PWD/data:/data" --env-file=.env essepl/scribe:latest bin/rails scribe:list

# Open a Rails console (in the running container, or one-shot with `docker run --rm -it … `):
docker exec -it scribe bin/rails console

# Start over: delete all local data (irreversible):
docker stop scribe && docker rm scribe && rm -rf ./data
```

> The image is larger than a typical Rails image because it bundles ffmpeg,
> WeasyPrint, and a pre-downloaded local Whisper model — but it runs fully
> offline-capable, and startup is fast. The database is created and migrated
> automatically on every boot, so the first run just works.

---

## Output & the data folder

Everything Scribe produces is written as plain files under `SCRIBE_DATA_DIR`
(`/data` inside the container — i.e. your mounted `./data` on the host). Nothing
is locked inside the database; mount or copy this one folder to move, back up, or
inspect all your data.

```
data/
├── db/                          # SQLite datastore (one file per database)
│   ├── scribe.sqlite3           #   primary: recordings, transcripts, manuals
│   ├── scribe_queue.sqlite3     #   Solid Queue (background jobs)
│   └── scribe_cache.sqlite3, scribe_cable.sqlite3
├── tus/                         # in-flight resumable uploads (transient)
└── storage/
    └── recordings/<id>/         # one folder per recording, keyed by its DB id
        ├── source.<ext>         # the original recorded/uploaded video (.webm/.mp4/.mov/…)
        ├── frames/              # every frame ffmpeg extracted (scene-change candidates)
        │   └── <timestamp_ms>.png
        └── results/             # ← the finished manual — this is what you publish
            ├── manual.json      #   structured manual: title, summary, ordered steps
            ├── manual.md        #   Markdown, references ./images/step-NN.png
            ├── manual.html      #   self-contained HTML (images inlined)
            ├── manual.pdf       #   rendered PDF (WeasyPrint; skipped if unavailable)
            ├── images/          #   the one screenshot chosen per step
            │   └── step-NN.png
            └── transcript.json  #   full transcript + per-segment timings
```

**`results/` is the deliverable.** It's self-contained: `manual.md` uses relative
`./images/...` links and `manual.html`/`manual.pdf` embed their images, so you can
copy `results/` anywhere and it stays intact. The CLI prints this path on success
(e.g. `/data/storage/recordings/3/results/`, which is
`./data/storage/recordings/3/results/` on the host), and the web UI serves the
same files.

The two image locations differ on purpose: `frames/` holds the **full** set of
extracted frames (handy if you re-run or want a different shot), while
`results/images/` holds only the per-step screenshots the LLM picked for the
manual. Result files are written automatically when a manual completes — set
`WRITE_RESULT_FILES=false` to keep results in the database only.

---

## Local development (without Docker)

System deps: Ruby (see `.ruby-version`), `ffmpeg`, and `weasyprint` (PDF export).
SQLite is bundled with the `sqlite3` gem — no database server to install.

```bash
bundle install
cp .env.example .env          # optional: add your keys

bin/rails db:prepare          # create + migrate the SQLite DBs under ./data
bin/dev                       # web server + Solid Queue worker (Ctrl-C stops both)
```

Open http://localhost:3000. `.env` is loaded automatically in development (via
`dotenv-rails`); it is **not** loaded in test, so the suite stays offline.

Install the system tools — macOS: `brew install ffmpeg weasyprint`;
Ubuntu: `sudo apt-get install -y ffmpeg weasyprint`. For local transcription,
`pip install faster-whisper` and point `WHISPER_BIN` at the bundled wrapper:
`WHISPER_BIN=script/faster-whisper` (it emits the JSON the pipeline expects). The
Docker image does this for you.

### Using an existing recording

- **Web:** on the record page there's an *"Or use a recording you already have"*
  form — pick a `.webm`/`.mp4`/`.mov`/`.mkv` and it runs the same pipeline.
- **CLI:** `bin/rails "scribe:ingest[/path/to/video.mp4]"` (runs inline and
  prints the result folder). Append `,async` to enqueue instead:
  `bin/rails "scribe:ingest[/path/to/video.mp4,async]"`.

### Running checks

```bash
bin/rails test                # full suite (offline; ffmpeg needed for the e2e pipeline test)
bin/rubocop                   # style (rails-omakase)
bin/brakeman -i config/brakeman.ignore   # security scan
```

CI (`.github/workflows/ci.yml`) runs all three with ffmpeg + WeasyPrint
installed.

---

## Configuration reference

All config comes from ENV (see `.env.example`). Highlights:

| Variable | Default | Purpose |
|----------|---------|---------|
| `SCRIBE_DATA_DIR` | `./data` (`/data` in Docker) | Where the DB, recordings and manuals live |
| `SECRET_KEY_BASE` | — (required in production/Docker) | Signs download URLs; generate with `openssl rand -hex 32` |
| `LLM_PROVIDER` | `anthropic` if key set, else `fake` | `anthropic` \| `openai` \| `local` \| `fake` |
| `ANTHROPIC_API_KEY` | — | Your Anthropic key (provider `anthropic`) |
| `ANTHROPIC_MANUAL_MODEL` | `claude-sonnet-4-6` | Anthropic model for manual generation |
| `OPENAI_LLM_API_KEY` | falls back to `OPENAI_API_KEY` | OpenAI key for the LLM (provider `openai`), independent of the STT key |
| `OPENAI_LLM_MODEL` | `gpt-4o` | OpenAI chat model (provider `openai`; vision-capable) |
| `OPENAI_BASE_URL` | `https://api.openai.com/v1` | OpenAI LLM endpoint — override for Azure/proxies |
| `LLM_BASE_URL` | `http://localhost:11434/v1` | OpenAI-compatible endpoint (provider `local`) |
| `LLM_MODEL` | `llama3.2-vision` | Local model id (vision-capable) |
| `LLM_API_KEY` | — | Optional bearer token for the local server |
| `TRANSCRIPTION_PROVIDER` | `whisper` (`stub` in tests) | `whisper` \| `deepgram` \| `openai` \| `stub` |
| `WHISPER_BIN` | `faster-whisper` (`/rails/script/faster-whisper` in Docker) | Local STT CLI emitting JSON segments |
| `WHISPER_MODEL` | `base` | faster-whisper model size (`tiny`/`base`/`small`/`medium`/`large-v3`) |
| `WHISPER_MODEL_DIR` | — (`/opt/whisper-models` in Docker) | Where Whisper models are cached |
| `DEEPGRAM_API_KEY` | — | Deepgram STT key |
| `OPENAI_API_KEY` | — | OpenAI STT key (and the fallback LLM key) |
| `WRITE_RESULT_FILES` | `true` | Write manual.json/md/html/pdf to disk |
| `RAW_VIDEO_RETENTION_DAYS` | `0` (keep forever) | Auto-purge raw videos older than N days |
| `WEASYPRINT_CMD` | `weasyprint` | PDF renderer command |
| `FORCE_SSL` | `false` | HSTS + secure cookies (set behind HTTPS proxy) |

---

## Key modules

- `app/services/llm.rb` — provider selection (`anthropic` / `openai` / `local` /
  `fake`). `llm/local_client.rb` is the OpenAI-compatible client (translates
  to/from the Anthropic message shape); `llm/openai_client.rb` points it at OpenAI.
- `app/services/anthropic/` — `Client` (HTTP) and `FakeClient` (offline).
- `app/services/transcription/` — `Base.build` selects the provider; `Whisper`
  (local CLI, default), `Deepgram`/`Openai` (hosted), and the offline `Stub`.
- `app/services/recording_ingest.rb` — ingest an existing video (web upload or
  CLI) and start the pipeline.
- `app/services/result_files.rb` — write a finished manual out as plain files
  under the data dir.
- `app/services/media/` — `Probe` (ffprobe), `AudioExtractor`, `FrameExtractor`,
  `Editor` (trim).
- `app/services/manual_generation/` — `ToolSchema` (forced output) + `Generator`
  (prompt build, chunking, vision images).
- `app/services/storage.rb` — disk storage facade with signed (HMAC) URLs.
- `app/services/exporters/` — `Registry` + `Markdown`/`Html`/`Pdf`. **Adding a
  format = one subclass + `Registry.register`.**
- `app/jobs/` — `TranscribeJob → ExtractFramesJob → GenerateManualJob`, plus
  `ExportJob` and `PurgeExpiredRecordingsJob`. Shared retry/failure handling in
  `PipelineStage`.
- `lib/tasks/scribe.rake` — the `scribe:ingest` / `scribe:list` CLI.

---

## What changed in the local-first pivot

Removed, because they don't belong in a tool you run for yourself:

- **Stripe & the credit ledger** — processing is free; there's no metering, no
  packs, no checkout, no webhooks.
- **Accounts & login** — a single implicit local user owns everything.
- **Sentry** — no error reporting leaves the machine.
- **Postgres & MinIO/S3** — replaced by a single SQLite file and on-disk storage
  under the mounted data dir.

Added:

- **OpenAI** (`LLM_PROVIDER=openai`) and **local llama** (`LLM_PROVIDER=local`)
  options alongside Anthropic — full choice of model.
- **Existing-recording ingest** via web upload and the `scribe:ingest` CLI.
- **Result files** written to the data folder for every completed manual.

---

## Security & privacy

- Single-user, local-first: no accounts to manage, no third-party backend.
- All downloads go through short-lived **signed URLs** (HMAC); the storage folder
  isn't served directly.
- Your API keys stay server-side and never reach the browser. With
  `LLM_PROVIDER=local` + local Whisper, no audio, frames, or text leave the
  machine at all.
- `getDisplayMedia` requires HTTPS + a user gesture (enforced by the browser).
