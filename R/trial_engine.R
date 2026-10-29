# State transitions for the minimum revised TWICEBEE conduct engine.

empty_log <- function(columns) {
  as.data.frame(setNames(replicate(length(columns), logical(0), simplify = FALSE), columns),
                stringsAsFactors = FALSE)
}

new_trial_state <- function(config, trace_detail = FALSE,
                            trial_id = NA_integer_, profile = NA_character_) {
  list(
    specification_version = "v0.4 (2026-09-21)",
    config = config,
    trial_id = trial_id,
    profile = profile,
    stage = 1L,
    stage2_entry_time = NA_real_,
    alpha = config$initial_alpha,
    beta = config$initial_beta,
    calibrated = FALSE,
    patients = list(),
    direct_dlt = matrix(0L, config$J, config$C),
    direct_nondlt = matrix(0L, config$J, config$C),
    excluded = matrix(FALSE, config$J, config$C),
    overdose_probability = matrix(NA_real_, config$J, config$C),
    enrollment_open = TRUE,
    enrollment_closure_time = NA_real_,
    enrollment_closure_reasons = character(),
    stopping_evaluations = list(),
    exclusion_events = list(),
    decision_log = list(),
    update_log = list(),
    trace_detail = trace_detail,
    trial_complete = FALSE,
    completion_time = NA_real_
  )
}

close_enrollment <- function(state, time, reasons) {
  if (!state$enrollment_open) {
    # Preserve categories that arise at the same decision time, but do not
    # retroactively relabel an enrollment closure during later follow-up.
    if (isTRUE(all.equal(state$enrollment_closure_time, time))) {
      state$enrollment_closure_reasons <- unique(c(
        state$enrollment_closure_reasons, reasons
      ))
    }
    return(state)
  }
  state$enrollment_open <- FALSE
  state$enrollment_closure_time <- time
  state$enrollment_closure_reasons <- unique(reasons)
  state
}

refresh_stage2_safety <- function(state, time) {
  refreshed <- refresh_overdose_exclusions(
    state$alpha, state$beta, state$excluded, state$config
  )
  if (nrow(refreshed$new_cells)) {
    state$exclusion_events[[length(state$exclusion_events) + 1L]] <- list(
      time = time,
      triggering_anchors = refreshed$triggering_anchors,
      new_cells = refreshed$new_cells
    )
  }
  state$excluded <- refreshed$excluded
  state$overdose_probability <- refreshed$overdose_probability
  if (!length(population_admissible_doses(state$excluded, 1L))) {
    state <- close_enrollment(state, time, "empty_cycle1_admissible_set")
  }
  stopping <- evaluate_retained_stopping(
    state$alpha, state$beta, length(state$patients), state$config
  )
  stopping$time <- time
  state$stopping_evaluations[[length(state$stopping_evaluations) + 1L]] <- stopping
  if (stopping$stop) {
    reasons <- character()
    if (stopping$rule_all_toxic) reasons <- c(reasons, "retained_all_doses_toxic_r1")
    if (stopping$rule_mtd_plus) reasons <- c(reasons, "retained_mtd_plus_r2")
    state <- close_enrollment(state, time, reasons)
  }
  state
}

transition_to_stage2 <- function(state, time, reason) {
  if (state$stage == 2L) return(state)
  calibrated <- calibrate_working_state(state$alpha, state$beta)
  pre_alpha <- state$alpha
  pre_beta <- state$beta
  state$alpha <- calibrated$alpha
  state$beta <- calibrated$beta
  state$calibrated <- TRUE
  state$stage <- 2L
  state$stage2_entry_time <- time
  entry <- list(
    type = "stage2_entry", time = time, reason = reason,
    average_ess = calibrated$average_ess,
    final_ess_range = range(state$alpha + state$beta)
  )
  if (state$trace_detail) {
    entry$pre_alpha <- pre_alpha
    entry$pre_beta <- pre_beta
    entry$post_alpha <- state$alpha
    entry$post_beta <- state$beta
  }
  state$update_log[[length(state$update_log) + 1L]] <- entry
  refresh_stage2_safety(state, time)
}

make_patient <- function(id, cohort_id, enrolled_time, C) {
  list(
    id = id,
    cohort_id = cohort_id,
    enrolled_time = enrolled_time,
    doses = rep(NA_integer_, C),
    outcomes = rep(NA_integer_, C),
    outcome_available = rep(FALSE, C),
    assignment_times = rep(NA_real_, C),
    outcome_times = rep(NA_real_, C),
    guided_status = "active",
    discontinuation_reason = NA_character_
  )
}

append_decision_log <- function(state, entry) {
  state$decision_log[[length(state$decision_log) + 1L]] <- entry
  state
}

assign_stage1 <- function(state, patient_id, cycle, time) {
  dose <- if (cycle == 1L) {
    state$config$starting_dose
  } else {
    min(state$config$J, state$patients[[patient_id]]$doses[cycle - 1L] + 1L)
  }
  list(
    dose = dose,
    log = list(
      time = time, patient_id = patient_id, cycle = cycle, stage = 1L,
      assigned_dose = dose, decision_type = "accelerated_titration",
      current_anchor = if (cycle == 1L) state$config$starting_dose else
        state$patients[[patient_id]]$doses[cycle - 1L],
      current_candidates = dose, previous_anchor_doses = integer(),
      previous_candidates = list(), previous_component = NA_integer_,
      fallback = NA, post_dlt = FALSE,
      exclusions_in_force = which(state$excluded[, cycle])
    )
  )
}

enroll_patient <- function(state, time) {
  if (!state$enrollment_open) return(list(state = state, assigned = FALSE))
  id <- length(state$patients) + 1L
  if (id > state$config$max_enrollment) {
    state <- close_enrollment(state, time, "maximum_enrollment")
    return(list(state = state, assigned = FALSE))
  }
  cohort_id <- ((id - 1L) %/% state$config$cohort_size) + 1L

  if (state$stage == 1L) {
    decision <- list(dose = state$config$starting_dose)
    log_entry <- list(
      time = time, patient_id = id, cycle = 1L, stage = 1L,
      assigned_dose = decision$dose, decision_type = "accelerated_titration_new",
      current_anchor = state$config$starting_dose,
      current_candidates = decision$dose, previous_anchor_doses = integer(),
      previous_candidates = list(), previous_component = NA_integer_,
      fallback = NA, post_dlt = FALSE,
      exclusions_in_force = which(state$excluded[, 1L])
    )
  } else {
    decision <- decide_new_patient(state, id)
    if (is.na(decision$dose)) {
      state <- close_enrollment(state, time, "empty_cycle1_admissible_set")
      return(list(state = state, assigned = FALSE))
    }
    log_entry <- list(
      time = time, patient_id = id, cycle = 1L, stage = 2L,
      assigned_dose = decision$dose, decision_type = "stage2_new_patient",
      current_anchor = decision$cohort_anchor,
      current_candidates = decision$candidates,
      previous_anchor_doses = integer(), previous_candidates = list(),
      previous_component = NA_integer_, fallback = NA, post_dlt = FALSE,
      cohort_completion = decision$cohort_completion,
      safety_override = decision$safety_override,
      exclusions_in_force = which(state$excluded[, 1L])
    )
  }

  patient <- make_patient(id, cohort_id, time, state$config$C)
  patient$doses[1L] <- decision$dose
  patient$assignment_times[1L] <- time
  state$patients[[id]] <- patient
  state <- append_decision_log(state, log_entry)

  if (state$stage == 1L && length(state$patients) >= state$config$n0) {
    state <- transition_to_stage2(state, time, "stage1_enrollment_limit")
  }
  if (length(state$patients) >= state$config$max_enrollment) {
    state <- close_enrollment(state, time, "maximum_enrollment")
  }
  list(state = state, assigned = TRUE, patient_id = id, cycle = 1L,
       dose = decision$dose)
}

assign_next_cycle <- function(state, patient_id, time) {
  patient <- state$patients[[patient_id]]
  completed_cycle <- max(which(patient$outcome_available), na.rm = TRUE)
  cycle <- completed_cycle + 1L
  if (cycle > state$config$C || patient$guided_status != "active") {
    return(list(state = state, assigned = FALSE))
  }

  if (state$stage == 1L) {
    assignment <- assign_stage1(state, patient_id, cycle, time)
    decision <- assignment
  } else {
    decision <- decide_ongoing_patient(state, patient_id, cycle)
    if (is.na(decision$dose)) {
      state$patients[[patient_id]]$guided_status <- "statistical_discontinued"
      state$patients[[patient_id]]$discontinuation_reason <- if (decision$post_dlt &&
        state$patients[[patient_id]]$doses[cycle - 1L] == 1L) {
        "DL1_DLT"
      } else {
        "empty_patient_specific_candidate_set"
      }
      return(list(state = state, assigned = FALSE))
    }
    assignment <- list(
      dose = decision$dose,
      log = list(
        time = time, patient_id = patient_id, cycle = cycle, stage = 2L,
        assigned_dose = decision$dose,
        decision_type = if (decision$post_dlt) "post_DLT" else "ordinary_stage2",
        current_anchor = patient$doses[cycle - 1L],
        current_candidates = decision$current_candidates,
        previous_anchor_doses = decision$previous_anchor_doses,
        previous_candidates = decision$previous_candidates,
        previous_component = decision$previous_component,
        qualifying_previous_ids = decision$qualifying_ids,
        fallback = decision$fallback, post_dlt = decision$post_dlt,
        exclusions_in_force = which(state$excluded[, cycle])
      )
    )
  }

  state$patients[[patient_id]]$doses[cycle] <- assignment$dose
  state$patients[[patient_id]]$assignment_times[cycle] <- time
  state <- append_decision_log(state, assignment$log)
  list(state = state, assigned = TRUE, patient_id = patient_id,
       cycle = cycle, dose = assignment$dose)
}

incorporate_outcome <- function(state, patient_id, cycle, outcome, time) {
  patient <- state$patients[[patient_id]]
  dose <- patient$doses[cycle]
  patient$outcomes[cycle] <- as.integer(outcome)
  patient$outcome_available[cycle] <- TRUE
  patient$outcome_times[cycle] <- time
  state$patients[[patient_id]] <- patient
  if (outcome == 1L) {
    state$direct_dlt[dose, cycle] <- state$direct_dlt[dose, cycle] + 1L
  } else {
    state$direct_nondlt[dose, cycle] <- state$direct_nondlt[dose, cycle] + 1L
  }

  pre_alpha <- state$alpha
  pre_beta <- state$beta
  if (state$stage == 1L) {
    updated <- apply_working_increment(state$alpha, state$beta, dose, cycle, outcome)
    state$alpha <- updated$alpha
    state$beta <- updated$beta
    update_entry <- list(
      type = "stage1_observation", time = time, patient_id = patient_id,
      cycle = cycle, dose = dose, outcome = outcome,
      calibrated = FALSE, average_ess = mean(state$alpha + state$beta)
    )
  } else {
    updated <- recursive_working_update(state$alpha, state$beta, dose, cycle, outcome)
    state$alpha <- updated$alpha
    state$beta <- updated$beta
    update_entry <- list(
      type = "stage2_recursive_observation", time = time, patient_id = patient_id,
      cycle = cycle, dose = dose, outcome = outcome,
      calibrated = TRUE, average_ess = updated$average_ess,
      final_ess_range = range(state$alpha + state$beta)
    )
  }
  if (state$trace_detail) {
    update_entry$pre_alpha <- pre_alpha
    update_entry$pre_beta <- pre_beta
    update_entry$post_alpha <- state$alpha
    update_entry$post_beta <- state$beta
    if (state$stage == 2L) {
      update_entry$intermediate_alpha <- updated$intermediate_alpha
      update_entry$intermediate_beta <- updated$intermediate_beta
    }
  }
  state$update_log[[length(state$update_log) + 1L]] <- update_entry

  if (state$stage == 1L && outcome == 1L) {
    state <- transition_to_stage2(state, time, "first_observed_DLT")
  } else if (state$stage == 2L) {
    state <- refresh_stage2_safety(state, time)
  }

  if (outcome == 1L && dose == 1L) {
    state$patients[[patient_id]]$guided_status <- "statistical_discontinued"
    state$patients[[patient_id]]$discontinuation_reason <- "DL1_DLT"
  } else if (cycle == state$config$C) {
    state$patients[[patient_id]]$guided_status <- "completed_max_cycle"
  }
  state
}

finalize_trial_state <- function(state, time) {
  n <- length(state$patients)
  dose_history <- matrix(NA_integer_, n, state$config$C)
  outcome_history <- matrix(NA_integer_, n, state$config$C)
  outcome_available <- matrix(FALSE, n, state$config$C)
  patient_information <- data.frame(
    patient_id = seq_len(n), cohort_id = integer(n), enrolled_time = numeric(n),
    guided_status = character(n), discontinuation_reason = character(n),
    stringsAsFactors = FALSE
  )
  for (i in seq_len(n)) {
    dose_history[i, ] <- state$patients[[i]]$doses
    outcome_history[i, ] <- state$patients[[i]]$outcomes
    outcome_available[i, ] <- state$patients[[i]]$outcome_available
    patient_information$cohort_id[i] <- state$patients[[i]]$cohort_id
    patient_information$enrolled_time[i] <- state$patients[[i]]$enrolled_time
    patient_information$guided_status[i] <- state$patients[[i]]$guided_status
    patient_information$discontinuation_reason[i] <- ifelse(
      is.na(state$patients[[i]]$discontinuation_reason), "",
      state$patients[[i]]$discontinuation_reason
    )
  }
  state$dose_history <- dose_history
  state$outcome_history <- outcome_history
  state$outcome_availability <- outcome_available
  state$patient_information <- patient_information
  state$final_working_means <- state$alpha / (state$alpha + state$beta)
  state$final_ess <- state$alpha + state$beta
  state$final_population_admissibility <- lapply(
    seq_len(state$config$C),
    function(cycle) population_admissible_doses(state$excluded, cycle)
  )
  state$trial_complete <- all(vapply(
    state$patients,
    function(patient) patient$guided_status != "active",
    logical(1)
  ))
  state$completion_time <- time
  state
}
