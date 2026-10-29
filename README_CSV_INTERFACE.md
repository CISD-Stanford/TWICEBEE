# TWICEBEE CSV interface v0.1

Component version **0.1**, included in repository release **1.0.0**.
Distributed under the [MIT License](LICENSE).

This interface records observed, evaluable binary DLT outcomes and delegates
recommendations to the **primary revised TWICEBEE** engine. The seven files in
`R/` are shared unchanged with the research engines. **The CSV interface
supports primary TWICEBEE, not TWICEBEE-MOB.** Its loader does not load MOB,
a comparator, a simulation runner, or an RNG.

Use de-identified subject codes only. Clinical eligibility and permission to
administer treatment come from the clinical protocol and clinical team.
A statistical preview is not administration or clinical authorization. This
interface has targeted operational checks, not clinical or regulatory validation.
It does not convert the toxicity-based MTDC into an RP2D schedule.

## Initialize and use

Use standard R (verified with R 4.4.1), on a local macOS/POSIX filesystem that
supports symbolic links and atomic rename. There are no additional R packages.
From the `TWICEBEE/` repository root:

```sh
Rscript --vanilla interface/twicebee_cli.R init /path/to/new-trial
Rscript --vanilla interface/twicebee_cli.R process /path/to/new-trial
Rscript --vanilla interface/twicebee_cli.R status /path/to/new-trial
```

An absolute path to `interface/twicebee_cli.R` works from any working directory.
Keep the extracted source-directory path and R temporary-directory path free of
spaces on R 4.4.1; its script-path handling does not support space-containing
source paths. Trial-directory paths may contain spaces when quoted.
`init` requires a new or empty trial directory.
`process` accepts the entire new event batch or changes none of the accepted
outputs. `status` verifies and displays the last committed history; it does
not process newly appended rows.

Initialization calls the unchanged `twicebee_config()` with its defaults:
four doses, eight cycles, target 0.30, starting dose 1, Stage-1 limit 6,
maximum enrollment 12, starting-dose cohort size 3, prior means
0.10/0.20/0.30/0.40 in every cycle with ESS 4, under/over penalties 1,
delta0 0.05, r1 0.50, r2/r_OD 0.95, minimum enrollment 6.
The retained configuration also contains enrollment interval 11 and cycle
duration 10; this manual interface uses entered event times and does not
schedule treatment using those simulation timing fields.
`trial_config.rds` saves the exact configuration. Parameter editing or
mid-trial changes are not supported. Defaults require protocol-specific
scientific review before any clinical use; this interface does not determine
their suitability for a protocol.

## Enter events

`init` creates `trial_events.csv`. The header-only template is also in
`templates/trial_events.csv`. Append rows; leave inapplicable fields blank.
Do not change column names or place comments in the CSV. Use UTF-8 text and
normal CSV quoting for commas in reasons.

| Field | Meaning |
|---|---|
| event_id | Unique strictly increasing positive integer, without leading zeros |
| available_at_utc | Exact UTC format `2026-10-12T18:00:00Z` |
| event_type | One of the ten event types below |
| subject_code | Unique fictional/de-identified identity for a new patient |
| patient_id | Engine-assigned positive integer, shown after confirmation |
| cycle | Confirmed cycle whose evaluable outcome is being entered |
| outcome | `1` DLT or `0` non-DLT; evaluable results only |
| recommendation_id | Issued ID such as `R000001`; never invent an ID |
| dose | Actual dose **level index** confirmed, not a physical dose amount |
| clinically_eligible | Explicit uppercase `TRUE` where required |
| reason | Clinical hold/discontinuation or authorized closure explanation |

All rows require event_id, available_at_utc, and event_type.
Other required fields are:

| Event | Required additional fields | Effect |
|---|---|---|
| REQUEST_NEW | subject_code, clinically_eligible | Preview C1; no enrollment or administration |
| REQUEST_NEXT | patient_id, clinically_eligible | Preview next cycle after the immediately preceding evaluable outcome |
| CONFIRM_DOSE | recommendation_id, dose, clinically_eligible | Recompute; commit only an agreeing, valid dose |
| OUTCOME | patient_id, cycle, outcome | Incorporate an evaluable result once; never assign automatically |
| HOLD | patient_id, reason | Block recommendations and confirmations |
| RELEASE_HOLD | patient_id, clinically_eligible | Explicitly clear a hold; no automatic dose |
| DISCONTINUE | patient_id, reason | Record external clinical discontinuation; retain assigned cycles |
| CANCEL_PREVIEW | recommendation_id | Cancel an unadministered pending preview |
| CLOSE_ENROLLMENT | reason | Record an authorized administrative closure; continue existing follow-up |
| FINALIZE | None | Require closed enrollment, resolved assigned outcomes, and no active patient/pending preview |

A subject code cannot identify two people or an already enrolled patient.
After cancellation, the same still-unenrolled subject can request a fresh
preview with the same code. An enrolled patient uses patient_id thereafter.
Patient IDs are allocated only at confirmed administration; simultaneous
new-subject previews do not reserve numeric patient IDs.

For example, append a REQUEST_NEW for F001 with eligibility TRUE, run
`process`, and inspect `recommendations.csv`. After reviewing clinical
eligibility and the actual administration, append CONFIRM_DOSE referencing
that recommendation and dose, with renewed eligibility TRUE. Process it and
read the allocated patient_id. Later append OUTCOME for that patient's
confirmed cycle. Process outcomes before requesting further decisions.
Eligibility must be explicitly renewed for every request, release, and
confirmation; a previous TRUE is not reused.

Confirmations are recalculated on the current engine state. A changed model
may still support the issued dose; it can be confirmed if it remains valid.
A changed dose or inconsistent confirmation rejects the batch: correct the
unaccepted input, cancel the preview, request a new one, and review it.
There is no arbitrary override or import path for off-algorithm treatment.
If recomputation returns no dose, its mandatory statistical discontinuation
or closure is saved with `INVALIDATED_NO_DOSE`, and no administered dose is
created. A request returning no dose is saved with `NO_DOSE_AVAILABLE`.
The status command and CSVs show these consequences and reasons.

Holds do not erase treatments and do not prevent outstanding outcomes from
being entered. Release a hold explicitly before a new recommendation or
confirmation. Clinical discontinuation cannot be reversed in v0.1; it
cancels pending previews and prevents all further assignments. Outcomes from
already administered cycles still enter the unchanged recursive updater.
Unresolved outcomes cannot be silently counted as non-DLT or removed for
finalization.

## Time and processing order

Times represent **information availability/action processing**, not biological
toxicity onset. They convert to numeric seconds since 1970-01-01 00:00:00 UTC,
independent of the computer's time zone. An outcome time must be strictly
later than its confirmed assignment time. Other events can share a time
when submitted in the same batch.

Keep event rows in nondecreasing time order with increasing IDs. At a common
time all OUTCOME rows are processed first, in ascending patient_id then
cycle order, using the original one-observation recursive update each time.
All other events then follow event_id order, including concurrent new and
ongoing patient requests. For example, an OUTCOME with a higher ID enters
before a lower-ID REQUEST_NEXT at the same time. The processing-status
output makes this order visible.

Submit **all** events at a timestamp together. After a successful process
call, every newly appended timestamp must be strictly later than the last
committed time. Backdating or appending more rows at a committed timestamp
is rejected. Conflicting simultaneous clinical instructions, such as HOLD
and RELEASE_HOLD, or DISCONTINUE and confirmation for the same patient, are
rejected. A release followed by a request is ordered prospectively by ID.

## Saved outputs and restart

- `trial_state.rds`: `readRDS(...)$record$state` is the engine state;
  the record also saves accepted rows, clinical metadata, issued decisions,
  initialized configuration, and last processing time.
- `trial_config.rds`: exact initialized configuration.
- `recommendations.csv`: preview ID, subject/patient, time, cycle, recommended
  dose, status, confirmation and no-dose explanation. PENDING means
  unadministered and must be rechecked at confirmation. CONFIRMED is the
  actual assignment; the separate confirmed_dose field is blank otherwise.
- `patient_status.csv`: last administered/evaluable cycle and outcome,
  outstanding assigned cycles, holds, external stops, original statistical
  status/reason, pending preview, and whether a further request is possible.
- `decision_history.csv`: processing order, recommendations, confirmations,
  administrative events/outcomes, original decision stage, statuses, doses,
  source IDs, and reasons.
- `accepted_events.csv` and `event_processing_status.csv`: authoritative
  accepted event rows and their actual processing order/status.
- `terminal_cycle_specific.csv` and `terminal_sequence.csv`: header-only
  before finalization; afterward, unchanged Decision-7 cycle-specific
  statuses and the contiguous recommended prefix. Later conditional
  estimates stay in the first table; they do not extend the executable
  sequence beyond an unsupported cycle.

Administrative hold/discontinuation fields are distinct from
`statistical_discontinued`, `DL1_DLT`, overdose exclusions and safety
closure reasons. The adapter marks an otherwise active externally stopped
patient `external_clinical_discontinued` in the conduct status to represent
external eligibility for the original finalizer. It preserves pre-existing
statistical/max-cycle statuses and every dose, outcome and working shape.
Later core outcome processing can update its statistical status, while the
separate clinical-discontinuation record persists.

Close R normally. On return, use the same distribution and trial directory,
then `status` or `process`. Each command verifies source identities and
saved output integrity and deterministically replays accepted events to
reproduce every issued decision and the scientific state. Repeated
`process` with no new rows writes nothing. No observation is ever added
again to persisted counts.

Previously accepted field values, rows, and their order are immutable.
CSV quoting/line-ending formatting can change if parsed field values remain
exactly identical; whitespace within values is significant. Correct only
unaccepted rows after an error. v0.1 has no accepted-history correction or
trial migration facility; seek review from the software maintainers and study team.

## Saving protection and errors

All derived outputs are read-only views through relative symbolic links.
They resolve through `.current` to one complete generation in `.commits/`.
Writing is staged and `.current` is replaced atomically after success.
Older generations remain available. Do not edit derived CSVs/RDS files,
replace output links, or delete hidden files. Back up the **whole trial
directory, including hidden directories and symbolic links**, using a tool
that preserves links. A state RDS alone is not a complete backup.

Commands use `.writer-lock/` to exclude another writer/status reader.
Do not edit the input while processing; a final re-read also detects edits.
For a normal rejection, no accepted output changes. The input remains as
submitted, so fix/remove only its unaccepted suffix and run process again.
CLI errors go to stderr and return exit status 1.

After an interrupted process, first confirm no R process is using that
trial. Back up the entire directory. Inspect `.current` and run status
after removing a leftover `.writer-lock/` only when no writer remains.
If a generation exists beyond the pointer, preserve it outside
`.commits/` for investigation before retrying; the CLI refuses to
overwrite it. Never advance `.current` manually to an unverified generation.
A leftover `.current-next` is not authoritative. For a replaced output
link, restore its relative target `.current/<output-filename>` after
checking the underlying generation. For an altered committed file, restore
the intact whole generation from backup and seek review.

Report the action, error message, R version, event IDs/types/times involved
(without direct identifiers), and whether the accepted prefix/state were
restored. This is accidental-error protection, not a tamper-proof audit
system or a guarantee against hardware/power-loss/filesystem faults.

## Reproducible fictional example and checks

```sh
Rscript --vanilla examples/run_manual_example.R /path/to/new-example-trial
```

The example uses explicitly constructed fictional outcomes, never simulated
DLT draws. It previews and confirms F001 C1 at DL1 and F002 C1 at DL1.
At the common next availability time, F001's non-DLT and F002's DL1 DLT
are incorporated before F001's C2 preview. C2 is recommended and confirmed
at DL2; its constructed non-DLT is later entered. The example exercises
hold/release, fictional external discontinuation, authorized closure, and
finalization. Each command starts a fresh R session; it inspects CSVs and
verifies idempotent reopening.

Saved CSV-trial outputs are not included in the source distribution.
Run the example to create the complete trial directory with its outputs and
hidden commit history.

The included tests A–G cover operational failures, small constructed
histories, and direct agreement with the unchanged engine/Decision-7:

```sh
Rscript --vanilla tests/run_targeted_tests.R /path/to/new-check-results
```

Detailed preparation logs and internal audit records are not distributed.
The documented CLI and fictional example need no test files.
Windows, network/cloud-synchronized filesystems, real clinical deployment,
unavailable/lost evaluable outcomes, accepted-history amendments,
parameter customization and regulatory validation are outside this v0.1
verification. Default configuration and exact replay require the same
saved distribution; upgrades need a reviewed migration procedure.

For a guided fictional workflow, see [Quick Start](docs/CSV_QUICK_START.md).
The software remains research-only; operational verification does not establish
clinical or regulatory validation.
