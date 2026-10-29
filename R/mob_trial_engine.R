# MOB is authoritative. These compatibility fields are read-only views for the
# unchanged retained decision helpers; no second working-information model exists.
mob_sync_views <- function(state) {
  state$alpha <- state$mob$alpha
  state$beta <- state$mob$beta
  state$direct_dlt <- state$mob$cumulative_direct_DLT
  state$direct_nondlt <- state$mob$cumulative_direct_nonDLT
  state
}

mob_new_trial <- function(config = package_a_config(), trace_detail = TRUE) {
  state <- new_trial_state(config, trace_detail)
  state$specification_version <- "TWICEBEE-MOB-dev v0.1"
  state$mob <- mob_new_state(config$initial_alpha, config$initial_beta)
  state$pending <- data.frame(patient_id = integer(), cycle = integer(),
                              outcome = integer(), time = numeric())
  state$batch_log <- list()
  state$transition_log <- list()
  mob_sync_views(state)
}

# Called only after the complete pending batch has been incorporated.
mob_enter_stage2 <- function(state, time, reason) {
  if (state$stage == 2L) return(state)
  handoff <- mob_stage2_handoff(state$mob)
  entry <- list(time = time, reason = reason, batch_count = length(state$batch_log))
  if (state$trace_detail) {
    entry$final_stage1 <- state$mob
    entry$stage2_entry <- handoff$working_state
  }
  state$mob <- handoff$working_state
  state$stage <- handoff$stage
  state$stage2_entry_time <- time
  state$transition_log[[length(state$transition_log) + 1L]] <- entry
  state
}

# Every public decision boundary goes through this routine. Pending records
# have been registered from actual scheduled observations, never from shapes.
mob_prepare_decision <- function(state, time) {
  due <- which(state$pending$time <= time)
  batch <- state$pending[due, , drop = FALSE]
  if (length(due)) state$pending <- state$pending[-due, , drop = FALSE]
  dy <- dm <- matrix(0L, state$config$J, state$config$C)
  for (k in seq_len(nrow(batch))) {
    i <- batch$patient_id[k]; c <- batch$cycle[k]; y <- batch$outcome[k]
    patient <- state$patients[[i]]
    # A repeated record would silently double-count scientific information.
    if (patient$outcome_available[c]) stop("Outcome already incorporated")
    dose <- patient$doses[c]
    patient$outcomes[c] <- y
    patient$outcome_available[c] <- TRUE
    patient$outcome_times[c] <- batch$time[k]
    if (y == 1L) dy[dose, c] <- dy[dose, c] + 1L else dm[dose, c] <- dm[dose, c] + 1L
    if (y == 1L && dose == 1L) {
      patient$guided_status <- "statistical_discontinued"
      patient$discontinuation_reason <- "DL1_DLT"
    } else if (c == state$config$C) {
      patient$guided_status <- "completed_max_cycle"
    }
    state$patients[[i]] <- patient
  }
  before <- state$mob
  updated <- mob_update_state(before, dy, dm)
  state$mob <- updated$state
  state <- mob_sync_views(state)
  state$last_increment <- list(delta_y = dy, delta_m = dm,
    Delta_Hplus = updated$update$Delta_Hplus, Delta_Hminus = updated$update$Delta_Hminus)
  if (nrow(batch)) {
    entry <- c(list(time = time, stage = state$stage, outcomes = batch), state$last_increment)
    if (state$trace_detail) { entry$before <- before; entry$after <- state$mob }
    state$batch_log[[length(state$batch_log) + 1L]] <- entry
  }
  if (state$stage == 1L && any(batch$outcome == 1L)) {
    state <- mob_enter_stage2(state, time, "first_observed_DLT")
  }
  if (state$stage == 2L) state <- refresh_stage2_safety(state, time)
  state
}

mob_enroll_patient <- function(state, time, external_candidates = seq_len(state$config$J)) {
  state <- mob_prepare_decision(state, time)
  if (!state$enrollment_open) return(list(state = state, assigned = FALSE))
  id <- length(state$patients) + 1L
  if (id > state$config$max_enrollment) {
    state <- close_enrollment(state, time, "maximum_enrollment")
    return(list(state = state, assigned = FALSE))
  }
  cohort <- ((id - 1L) %/% state$config$cohort_size) + 1L
  if (state$stage == 1L) {
    dose <- state$config$starting_dose
    decision <- list(dose = dose, candidates = dose, cohort_anchor = dose)
    type <- "accelerated_titration_new"
  } else {
    decision <- decide_new_patient(state, id, external_candidates)
    dose <- decision$dose
    type <- "stage2_new_patient"
  }
  if (is.na(dose)) {
    state <- close_enrollment(state, time, "empty_cycle1_admissible_set")
    return(list(state = state, assigned = FALSE))
  }
  patient <- make_patient(id, cohort, time, state$config$C)
  patient$doses[1L] <- dose
  patient$assignment_times[1L] <- time
  state$patients[[id]] <- patient
  state <- append_decision_log(state, list(time = time, patient_id = id, cycle = 1L,
    stage = state$stage, decision_type = type, assigned_dose = dose,
    decision = decision, batch_count = length(state$batch_log)))
  if (state$stage == 1L && id >= state$config$n0) {
    state <- mob_enter_stage2(state, time, "stage1_enrollment_limit")
    state <- refresh_stage2_safety(state, time)
  }
  if (id >= state$config$max_enrollment) state <- close_enrollment(state, time, "maximum_enrollment")
  list(state = state, assigned = TRUE, patient_id = id, cycle = 1L, dose = dose)
}

mob_assign_next_cycle <- function(state, patient_id, time, clinically_eligible = TRUE,
                                  external_candidates = seq_len(state$config$J)) {
  state <- mob_prepare_decision(state, time)
  patient <- state$patients[[patient_id]]
  cycle <- max(which(patient$outcome_available)) + 1L
  if (cycle > state$config$C || patient$guided_status != "active") {
    return(list(state = state, assigned = FALSE))
  }
  if (!clinically_eligible) {
    state$patients[[patient_id]]$guided_status <- "external_discontinued"
    state$patients[[patient_id]]$discontinuation_reason <- "clinical_ineligibility"
    return(list(state = state, assigned = FALSE))
  }
  if (state$stage == 1L) {
    decision <- assign_stage1(state, patient_id, cycle, time)
    type <- "accelerated_titration"
  } else {
    decision <- decide_ongoing_patient(state, patient_id, cycle, external_candidates)
    type <- if (decision$post_dlt) "post_DLT" else "ordinary_stage2"
  }
  if (is.na(decision$dose)) {
    state$patients[[patient_id]]$guided_status <- "statistical_discontinued"
    state$patients[[patient_id]]$discontinuation_reason <- if (decision$post_dlt &&
      patient$doses[cycle - 1L] == 1L) "DL1_DLT" else "empty_patient_specific_candidate_set"
    return(list(state = state, assigned = FALSE, decision = decision))
  }
  state$patients[[patient_id]]$doses[cycle] <- decision$dose
  state$patients[[patient_id]]$assignment_times[cycle] <- time
  state <- append_decision_log(state, list(time = time, patient_id = patient_id, cycle = cycle,
    stage = state$stage, decision_type = type, assigned_dose = decision$dose,
    decision = decision, batch_count = length(state$batch_log)))
  list(state = state, assigned = TRUE, patient_id = patient_id, cycle = cycle,
       dose = decision$dose, decision = decision)
}

mob_finalize <- function(state, time) {
  state <- mob_prepare_decision(state, time)
  if (nrow(state$pending)) stop("Terminal processing requires resolved follow-up")
  state <- finalize_trial_state(state, time)
  attach_decision7(state)
}
