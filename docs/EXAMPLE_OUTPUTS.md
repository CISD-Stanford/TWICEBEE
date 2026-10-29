# Illustrative inputs and expected outputs

## Primary TWICEBEE illustration

Run `Rscript --vanilla examples/twicebee_illustration.R` from the repository root. The unchanged example uses its fixed three-dose, eight-cycle probability surface, seed 314159 and Mersenne-Twister/Inversion/Rejection RNG settings. It is a single simulated illustration, not a simulation campaign.

Expected: six enrolled patients, 43 evaluable patient-cycles and 12 DLT-positive patient-cycles. All eight terminal statuses are `RECOMMENDED`. Terminal doses and the supported contiguous sequence are `1,2,2,2,2,3,3,3`.

Small reference CSVs are included and are overwritten by the example at `examples/output/twicebee/summary.csv`, `terminal.csv` and `supported_sequence.csv`.

## MOB working update

Run `Rscript --vanilla examples/mob_working_update.R` from the repository root. The existing deterministic three-dose, one-cycle fixture has prior alpha `(0.2,0.3,0.4)` and beta `(0.8,0.7,0.6)`. One direct DLT at dose 1 gives direct alpha `(1.2,0.3,0.4)`, borrowed DLT increment `(0,0.9,0.8)` and closed alpha `(1.2,1.2,1.2)`. Beta remains unchanged, with zero borrowed non-DLT increments. Output: `examples/output/mob/working_update.csv`.

This fixture is a working-state illustration; it is not claimed to reproduce a manuscript appendix or an entire trial.

## Fictional CSV workflow

`examples/fictional_events.csv` supplies explicit fictional events for F001 and F002. Run `Rscript --vanilla examples/run_manual_example.R /path/to/new-fictional-trial`. The script calls the unchanged CLI through fresh R processes and checks resume/idempotence.

Expected: three evaluable patient-cycles, one DLT and two non-DLTs. F001's C2 administration is DL2. Final conditional terminal recommendations are C1 DL1 and C2 DL3; C3–C8 have `INSUFFICIENT_DIRECT_INFORMATION`. The supported contiguous prefix is `[1,3]`. Terminal C2 DL3 is distinct from the administered C2 DL2 and is not an RP2D recommendation.

Nine derived output files are created in the new trial directory: `trial_state.rds`, `trial_config.rds`, `recommendations.csv`, `patient_status.csv`, `decision_history.csv`, `accepted_events.csv`, `event_processing_status.csv`, `terminal_cycle_specific.csv` and `terminal_sequence.csv`. The full trial directory also contains input, symbolic links and hidden generation/lock machinery. Preserve hidden contents and links when backing it up; isolated CSV/RDS snapshots are not a resumable backup.
