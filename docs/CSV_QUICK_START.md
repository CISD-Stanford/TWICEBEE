# TWICEBEE CSV Interface v0.1 — Quick Start
macOS fictional workflow | Primary revised TWICEBEE only; not TWICEBEE-MOB | Research use
This is a standalone R-source interface, not an installable R package. Prior local verification used macOS 26.6 (Apple arm64) with R 4.4.1; it uses standard R only. Clinical eligibility and authorization to administer a dose remain outside the software.
## 1. Extract and initialize a test trial
Extract `TWICEBEE-v1.0.0.zip` into a source path containing no spaces. Keep the R temporary-directory path free of spaces as well. Open Terminal and change directory to its `TWICEBEE/` root. Quoted trial-directory paths may contain spaces. Use a local Mac directory, not iCloud/Dropbox or a network drive.

```sh
TRIAL="$HOME/twicebee_csv_trial_test"
```


```sh
Rscript --vanilla interface/twicebee_cli.R init "$TRIAL"
```


```sh
Rscript --vanilla interface/twicebee_cli.R status "$TRIAL"
```

The test directory must be new or empty. Initialization creates trial_events.csv (input) and the saved state/output files. In RStudio or a plain-text editor, open the CSV and append only the new rows shown below; keep its existing header exactly as provided.
## 2. Enter fictional patients and confirm cycle 1
For every stage: append the indicated row(s) to trial_events.csv, save, then run process. Inspect the printed status or recommendations.csv before confirming a dose. In this fictional test, clinically_eligible=TRUE represents an externally authorized decision.
A. Request first patient F001 (one row)

```csv
1,2026-10-12T18:00:00Z,REQUEST_NEW,F001,,,,,,TRUE,
```


```sh
Rscript --vanilla interface/twicebee_cli.R process "$TRIAL"
```

Expected: recommendation R000001, cycle 1, dose level 1, status PENDING. No dose has yet been recorded as administered.
B. Confirm F001 C1 DL1 after fictional administration

```csv
2,2026-10-12T18:01:00Z,CONFIRM_DOSE,,,,,R000001,1,TRUE,
```

Run process again. Expected: R000001 becomes CONFIRMED; F001 receives patient_id 1.
C. Preview F002, then confirm it (process after EACH row)

```csv
3,2026-10-12T18:02:00Z,REQUEST_NEW,F002,,,,,,TRUE,
```


```csv
4,2026-10-12T18:03:00Z,CONFIRM_DOSE,,,,,R000002,1,TRUE,
```

Expected: F002 is assigned patient_id 2, with confirmed C1 DL1. Row 4 is entered only after processing and reviewing the row-3 preview.
To inspect recommendations without editing output files, run:

```sh
cat "$TRIAL/recommendations.csv"
```


## 3. Incorporate outcomes and obtain the next decision
Append the following THREE rows together, then run process once. These events share one information-availability time; the interface incorporates both outcomes before the next-cycle request, even though REQUEST_NEXT appears first in CSV order.

```csv
5,2026-10-13T18:00:00Z,REQUEST_NEXT,,1,,,,,TRUE,
```


```csv
6,2026-10-13T18:00:00Z,OUTCOME,,2,1,1,,,,
```


```csv
7,2026-10-13T18:00:00Z,OUTCOME,,1,1,0,,,,
```


```sh
Rscript --vanilla interface/twicebee_cli.R process "$TRIAL"
```


```sh
cat "$TRIAL/recommendations.csv"
```

Expected: F001 (patient 1) receives C2 recommendation R000003 at DL2, status PENDING. F002 (patient 2) has C1 DLT=1 at DL1 and is statistically discontinued. F001 has C1 DLT=0. The recommendation alone is not administration.
Confirm the recommended C2 dose after fictional administration

```csv
8,2026-10-13T18:01:00Z,CONFIRM_DOSE,,,,,R000003,2,TRUE,
```


```sh
Rscript --vanilla interface/twicebee_cli.R process "$TRIAL"
```


```sh
Rscript --vanilla interface/twicebee_cli.R status "$TRIAL"
```

Expected: F001 C2 DL2 is CONFIRMED. The trial is ongoing, so the final MTDC files remain header-only. New evaluable outcomes can be entered later using additional OUTCOME events.
## 4. Review outputs and resume later
| File in test trial directory | What to check |
|---|---|
| recommendations.csv | Recommendation ID, cycle, dose, PENDING vs CONFIRMED |
| patient_status.csv | Patient status, pending outcomes, eligibility to request |
| decision_history.csv | Chronological recommendations, confirmations, and outcomes |
| terminal_cycle_specific.csv / terminal_sequence.csv | Final cycle-specific results / contiguous MTDC prefix; populated only after FINALIZE |

Close Terminal/R normally. Later reopen Terminal, return to the same extracted source folder, re-enter TRIAL="$HOME/twicebee_csv_trial_test", and use status or process. With no new events, process does not duplicate outcomes.
## 5. Complete fictional example

```sh
Rscript --vanilla examples/run_manual_example.R "$HOME/twicebee_csv_full_example"
```

This tested script uses two fictional patients and completes follow-up/FINALIZE. Expected: three evaluable patient-cycles (one DLT); conditional terminal C1=DL1 and C2=DL3; C3–C8 have INSUFFICIENT_DIRECT_INFORMATION; the supported contiguous prefix is [1, 3]. The terminal C2 DL3 is not the same as F001's administered C2 DL2.
## Safeguards and troubleshooting
Use dose LEVEL indices, not physical doses. UTC timestamps must be YYYY-MM-DDTHH:MM:SSZ; events at the same timestamp must be submitted together. Do not change previously accepted CSV rows or edit generated CSV/RDS files, symlinks, or hidden .commits files. Back up the entire trial directory, including hidden contents. Correct only unaccepted events after an error. Existing v0.1 cannot amend accepted outcomes, adjudicate unavailable outcomes, or customize the default design. For errors, record the command, full message, R version and sessionInfo(). Software results are research-only and do not establish an RP2D or authorize treatment.

See [the CSV reference](../README_CSV_INTERFACE.md) for the exact eleven-column schema, all ten event types, recovery and platform limitations. Distributed under the [MIT License](../LICENSE).
