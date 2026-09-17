# Playbook: Turning a course module into a tested, shareable branch

This is the exact process used to take Module 13 (Storage for AI Applications)
from "a set of notebooks with placeholder instructions" to "actually
provisioned and tested against real GCP infrastructure, ready to hand to
someone else." Follow the same steps for each of `branch 1` (Module 14),
`branch 2` (Module 15), and `branch 3` (Module 16) in this repo.

GCP project used for Module 13 (reuse unless told otherwise):
`gcp-fde-project` (project number `1039893753206`).

## 0. Read before touching anything

- Read every doc in `docs/` for the module, in order. Understand what each
  topic teaches and what the "hands-on" project actually builds.
- Read every notebook/script fully (not just skim) — know what each cell is
  supposed to do before running it.
- Check `.env.example` and `requirements.txt` for what config and packages
  the module expects.
- Check for `.bat` files — these are Windows-only provisioning/cleanup
  scripts. They won't run on macOS/Linux, but they document the exact
  `gcloud` commands the module needs. Read them for that, not to execute
  them directly.

## 1. GCP + local environment setup

```bash
gcloud config set project <PROJECT_ID>
gcloud auth application-default login
gcloud auth application-default set-quota-project <PROJECT_ID>
gcloud billing projects describe <PROJECT_ID> --format="value(billingEnabled)"
```

Enable whatever APIs the module's `.bat` files or docs reference
(`gcloud services enable ...`). Don't assume — check what's already enabled
first with `gcloud services list --enabled --project=<PROJECT_ID>`.

Create a Python virtualenv inside the module folder and install
`requirements.txt` into it — never touch global Python:

```bash
cd <module-folder>
python3 -m venv .venv
./.venv/bin/pip install -r requirements.txt
```

(`python -m venv` auto-creates a `.venv/.gitignore` with `*` in it, so the
venv is never at risk of being committed even before you add a repo-level
`.gitignore`.)

## 2. Create `.env` with real values

Copy `.env.example` to `.env`. Fill in every key with real values for the
actual GCP project — real resource names, real region/zone, and a freshly
generated password for anything that needs one:

```bash
openssl rand -base64 18 | tr -d '=+/' | cut -c1-20
```

**Check for a repo-level `.gitignore` before creating `.env`.** If there
isn't one, add it *first* — a public repo with a real Cloud SQL password
committed to git history is a real, hard-to-undo mistake. Module 13's repo
had no `.gitignore` at all until this was caught. Minimum needed:

```
.env
.env.*
!.env.example
__pycache__/
*.pyc
.ipynb_checkpoints/
.venv/
.DS_Store
```

## 3. Handle the `.bat` files — move, don't delete-and-forget

Move the original `.bat` files into a `bat-files/` subfolder inside the
module (`git mv`, not delete) — they're kept for reference (what the
original Windows-only commands looked like), but are no longer part of the
active setup flow:

```bash
mkdir bat-files
git mv 00_setup_vars.bat 0Xa_provision_*.bat 99_cleanup.bat bat-files/
```

(Module 13 initially deleted them outright and had to restore them from
git history later at the user's request — moving them into a folder up
front avoids that extra round-trip.)

## 4. Write `commands.md` as you go — not after

Create `commands.md` at the module root. Structure: one `##` section per
topic, in teaching order, plus a "0. One-time project setup" section at the
top and a "Final cleanup" section at the bottom.

**Two hard rules, learned from getting this wrong on Module 13:**

- **Write the real command you're about to run into `commands.md` *before or
  immediately after* running it — not from memory afterward.** It's much
  easier to keep this accurate in real time than to reconstruct it later.
- **Show literal, real values in every command — no `$VAR` placeholders,
  no `<PROJECT_ID>` angle brackets, no shell-variable sourcing shown in the
  final doc.** Exception: never write a *live* secret (a password for a
  resource that still exists) directly into the command as typed in the
  terminal — source it from `.env` into a shell variable while actually
  running it, so it never sits in shell history in plain text. Once that
  resource is torn down, it's fine (and was explicitly asked for on Module
  13) to go back and write the real literal value into `commands.md`, since
  the value is no longer live anywhere and the doc becomes a true record of
  exactly what ran.

For each topic's section, capture:
- The exact `gcloud`/CLI commands used to provision it
- Any real bug or gotcha hit while running it (see §6 — write these up
  properly, they're often the most useful part of the doc)
- The exact cleanup command(s) for that topic's resources
- Any real timing anomaly (e.g., "this took 40 minutes instead of the
  documented 5-10 minutes, no errors, just slow") — future readers should
  know that's a "keep waiting" situation, not a "something's broken" one

## 5. Provision infrastructure for real, one topic at a time

Don't provision everything up front. Follow the module's own suggested
order, and for slow resources (Cloud SQL, Redis, anything with real
compute/memory reserved), kick off provisioning in the background and keep
working on other topics while it completes.

**When something is provisioning slowly:** check `gcloud <service>
operations describe <op-id>` or `... instances describe ... --format=
"value(state)"`. If the status is still actively `RUNNING`/`CREATING` with
no error, that's a "keep waiting" situation — Module 13's Cloud SQL took
~40 minutes and Redis took ~55 minutes against a documented 5-10 minute
estimate, both with zero errors the whole time, and both eventually
succeeded. Don't cancel a healthy-but-slow operation. Do proactively tell
the person you're working with when something is taking meaningfully
longer than documented, and check in before just continuing to wait
indefinitely.

## 6. Run every notebook/script for real, and actually verify the result

Execute notebooks headlessly so results get saved:

```bash
./.venv/bin/jupyter nbconvert --to notebook --execute --inplace <notebook>.ipynb --ExecutePreprocessor.timeout=120
```

After every run:
- **Read the actual saved outputs** — don't just check "did it error." A
  notebook can run clean and still be wrong (e.g., an LLM agent
  confidently returning a number).
- **Independently verify anything the notebook claims**, using a second,
  different method. Examples from Module 13: after the agent said "10,198
  stories," ran the identical SQL query myself outside the agent to
  confirm an exact match. After Redis reported a cache hit, checked the
  actual key and its TTL directly with `redis.Redis(...).keys(...)`. Don't
  trust output; check the underlying state.

**When something fails, read the actual error rather than assuming the
notebook code is broken.** Two real, non-obvious bugs turned up this way on
Module 13:
- `from setup import ...` failed because the file was `00_setup.py` (a
  leading digit makes a filename unimportable as a plain module name) — no
  plain `setup.py` existed. Fixed with a tiny shim file that loads
  `00_setup.py`'s contents under the importable name. This bug will likely
  recur in any module using the same `00_setup.py` naming convention —
  check for it early rather than rediscovering it per module.
- A BigQuery agent's schema prompt named a column `time_ts`; the real
  public table's column was actually `timestamp`. The LLM correctly used
  the wrong name it was given, and BigQuery's own error pointed at the
  actual schema — confirmed via `client.get_table(...)` before "fixing"
  anything.
- Signed URL generation failed because `gcloud auth application-default
  login` produces credentials with no private key to sign with. Fixed
  properly (not worked around) via IAM impersonation — created a dedicated
  service account, granted the user account `roles/iam.serviceAccountTokenCreator`
  on it, and passed `impersonated_credentials.Credentials(...)` into the
  signing call. This is the correct production pattern (no service account
  key files), and will very likely recur for any topic doing GCS signed
  URLs, Cloud Storage V4 signing, or anything else requiring a signature
  from user-level ADC credentials.

When a fix changes notebook code, re-run the *whole* notebook afterward and
confirm a clean pass — don't assume the fix worked from reading the diff.

## 7. Keep docs in sync as things change

Every time a `.bat` file is moved/removed or a workflow changes, grep the
whole module for stale references and fix them immediately, not at the end:

```bash
grep -rn "\.bat\b" docs/ README.md
```

Module 13 shipped originally with `code/<module-folder>/...`-style paths
inside its own docs (assuming a different repo layout than the one it
actually ended up living in). Check for and strip any path prefix that
doesn't match this repo's actual structure.

## 8. Before calling it "done" — a real pre-share audit

Don't just eyeball it. Run actual checks:

```bash
# Every notebook is valid JSON and every code cell parses
python3 -c "
import json, ast
nb = json.load(open('X.ipynb'))
for c in nb['cells']:
    if c['cell_type'] == 'code':
        ast.parse(''.join(c['source']))
"

# No leftover error-type outputs from earlier failed debugging runs
# (loop over cells, check for output_type == 'error')

# .env.example covers exactly what the setup script requires — no more, no less
grep -oE 'os\.environ\["[A-Z_]+"\]' 00_setup.py | sort -u
grep -oE '^[A-Z_]+=' .env.example | tr -d '=' | sort -u

# requirements.txt covers every import actually used (walk the AST of every
# notebook, collect top-level import names, compare against requirements.txt)

# No secrets or personal machine paths leaked into committed notebook outputs
grep -rln "/Users/<yourname>\|<your-email>" *.ipynb docs/ README.md
```

That last check caught a real issue on Module 13: a saved Firestore
deprecation warning had the full local filesystem path baked into a
notebook's committed output. Removed just that one stderr output entry,
kept the real stdout results.

## 9. Final cleanup — and keep `commands.md` honest about it

Tear down every billable resource (anything with no free tier — check the
module's own cost notes for which ones). Verify empty with `list` commands
afterward, don't just trust that `delete` succeeded silently. Update
`commands.md`'s final cleanup section to reflect what was *actually* torn
down, including anything deleted later than originally planned (Module 13's
free-tier resources — a bucket, a Firestore database, a signer service
account — were initially left running since they cost nothing, then deleted
anyway later at the user's request; `commands.md` was updated to reflect
that final state, not the original plan).

## Summary checklist, per module/branch

- [ ] Read all docs + all code first
- [ ] `.gitignore` exists and covers `.env` before `.env` is ever created
- [ ] `.env` created with real values, `.env.example` kept in sync
- [ ] Original `.bat` files moved into `bat-files/`, not deleted
- [ ] `commands.md` written incrementally, real literal values, real bugs documented
- [ ] Every notebook/script actually run against real GCP infra
- [ ] Every claimed result independently verified by a second method
- [ ] Real bugs found are actually fixed (not worked around) and re-verified
- [ ] Docs grep'd for stale references after every structural change
- [ ] Pre-share audit run (JSON/syntax validity, no error outputs, env var
      parity, requirements parity, no leaked personal paths)
- [ ] Billable resources torn down and verified empty
- [ ] `commands.md` cleanup section matches what was actually deleted
