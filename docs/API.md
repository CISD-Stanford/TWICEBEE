# Research state and conduct API

Load using the README commands. These calls operate on explicit research states; they do not import an arbitrary observed-history table or implement a clinical workflow. Rows of all working/count matrices are doses, columns are cycles. Binary outcomes are 1 for DLT and 0 for non-DLT. Times use a common caller-defined scale; the illustration retains interval 11 and cycle duration 10.

## Configuration

`twicebee$twicebee_config(max_enrollment = 12L)` delegates without modification to the retained `package_a_config`. It returns `J`, `C`, `theta0`, `starting_dose`, `n0`, `max_enrollment`, `cohort_size`, `prior_means`, `prior_ess`, `initial_alpha`, `initial_beta`, `under_penalty`, `over_penalty`, `delta0`, `r1`, `r2`, `r_OD`, `minimum_enrollment`, `enrollment_interval`, and `cycle_duration`. Matrix dimensions and scientific inputs must be internally consistent. Changing those inputs requires scientific review outside these examples.

## Revised TWICEBEE

| Call through `twicebee$` | Inputs and result |
|---|---|
| `new_trial_state(config, trace_detail = FALSE, trial_id = NA_integer_, profile = NA_character_)` | Returns initialized trial state; no outcomes generated. |
| `enroll_patient(state, time)` | Returns assignment list including `state`, `assigned`, and, when assigned, patient/cycle/dose. No external clinical eligibility argument is supplied by this retained function. |
| `incorporate_outcome(state, patient_id, cycle, outcome, time)` | Incorporates the observed outcome of an already assigned cycle; returns state with updated patient, counts, working shapes, transition and safety fields. |
| `assign_next_cycle(state, patient_id, time)` | Returns next assignment or statistical discontinuation; the caller retains the returned `state`. |
| `close_enrollment(state, time, reasons)` | Records closure; existing enrolled patients still require appropriate follow-up. |
| `finalize_trial_state(state, time)` | Assembles dose/outcome histories, availability flags and patient information; determines completion from patient states. |
| `attach_decision7(state)` | Requires ended enrollment, completed trial and resolved assigned outcomes. Adds final recommendation object without altering conduct. |

The state contains `config`, `alpha`, `beta`, `direct_dlt`, `direct_nondlt`, permanent `excluded` cells, patients, enrollment flags/reasons, decision/update/safety logs and completion fields. Each patient stores assigned doses, outcomes, availability, times and guided status. Finalization adds `dose_history`, `outcome_history`, `outcome_availability`, `patient_information`, final working means/ESS and admissibility.

Stage-1 and Stage-2 conduct, current/previous patient components, destination-cycle fallback, post-DLT restrictions, upward no-skipping, stopping and overdose protection remain in the copied functions. Clinical eligibility must be assessed before executing a statistical continuation; the base engine does not itself evaluate recovery, delay or clinical acceptability. Arbitrary direct edits of state fields are not a documented history-import procedure.

## TWICEBEE-MOB

| Call through `mob$` | Inputs and result |
|---|---|
| `mob_new_state(a0, b0)` | Original shape grids -> persistent prior/shape/direct/borrowed ledger state. |
| `mob_update_state(state, delta_y, delta_m)` | Complete new actual DLT/non-DLT batch -> `state` and `update`, including `tilde_alpha`, `tilde_beta`, `alpha`, `beta`, `Delta_Hplus`, `Delta_Hminus`. |
| `mob_new_trial(config, trace_detail = TRUE)` | Integrated trial state, authoritative `state$mob`, compatibility views and pending queue. |
| `mob_register_observation(state, assignment, schedule, time)` | Registers one specified later evaluable outcome for the assigned patient-cycle. Returns trial state; no outcome is generated. |
| `mob_prepare_decision(state, time)` | Incorporates every pending record due by `time` as one direct batch, then transition/safety. |
| `mob_enroll_patient(state, time, external_candidates = seq_len(state$config$J))` | Assignment list; complete due batch is consumed first. |
| `mob_assign_next_cycle(state, patient_id, time, clinically_eligible = TRUE, external_candidates = seq_len(state$config$J))` | Assignment or discontinuation; supplied eligibility is a protocol input. |
| `mob_finalize(state, time)` | Consumes due data, requires no pending follow-up, finalizes and attaches unchanged terminal procedure. |
| `mob_run_schedule(config, enrollment_times, outcome_schedule, clinical_schedule = NULL, trace_detail = TRUE)` | Explicit deterministic scheduler returning a finalized trial state. |

`outcome_schedule` has `patient_id`, `cycle`, `outcome`, `time`. Each actually assigned cycle must have exactly one matching record with availability time later than assignment. Unreached records are not observations and do not enter the working state. At a common time all due outcomes enter before any ongoing/enrollment decision. `clinical_schedule`, when supplied, has `patient_id`, `cycle`, `eligible` for ongoing destination-cycle decisions. The scheduler defaults to eligibility TRUE where no record is supplied; absence is not an assessment of clinical eligibility. Enrollment eligibility must be handled by the caller's supplied enrollment schedule.

The isolated persistent state has original `a0`, `b0`, current `alpha`, `beta`, `cumulative_direct_DLT`, `cumulative_direct_nonDLT`, `cumulative_borrowed_DLT`, and `cumulative_borrowed_nonDLT`. Only new actual observations enter direct ledgers; empty batches preserve the exact state. Working shapes carry forward into Stage 2 without ESS calibration. Imported helpers are isolated from the revised calibrated updater.

## Terminal object and retained identities

Both integrated methods return `state$decision7`: `cycle_specific` (cycle/status/dose/direct_n/admissible_n/selected_cell_direct_n), `sequence` (cycle/dose/in_recommended_sequence), `recommended_sequence` and `first_unsupported_cycle`. Status precedence is `NO_ADMISSIBLE_DOSE`, then `INSUFFICIENT_DIRECT_INFORMATION`, then `RECOMMENDED`. Direct eligibility is cycle-level, not a requirement for direct data at the selected cell.

Implementation-history strings in returned state are retained unchanged. They do not supersede the repository and component versions listed in COMPONENT_VERSIONS.md or imply a new statistical variant.

`illustration_scheduler.R` contains the unchanged scheduler/outcome generator required for the fixed example. Core observed-state functions do not require that generator, seed records, production outputs or external source files. The example is a simulated illustration; the isolated MOB example is a deterministic count update.
