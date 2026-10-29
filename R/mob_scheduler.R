# A deterministic availability schedule specifies patient_id, cycle, outcome,
# time. Only actually assigned patient-cycles enter the pending observation queue.
mob_register_observation <- function(state, assignment, schedule, time) {
  if (!assignment$assigned) return(state)
  record <- schedule[schedule$patient_id == assignment$patient_id &
                       schedule$cycle == assignment$cycle, , drop = FALSE]
  if (nrow(record) != 1L || record$time <= time) {
    stop("Each assigned cycle needs one explicitly scheduled later evaluable outcome")
  }
  state$pending <- rbind(state$pending, record[, c("patient_id", "cycle", "outcome", "time")])
  state
}

mob_run_schedule <- function(config, enrollment_times, outcome_schedule,
                             clinical_schedule = NULL, trace_detail = TRUE) {
  state <- mob_new_trial(config, trace_detail)
  next_enrollment <- 1L
  time <- 0
  repeat {
    et <- if (state$enrollment_open && next_enrollment <= length(enrollment_times))
      enrollment_times[next_enrollment] else Inf
    ot <- if (nrow(state$pending)) min(state$pending$time) else Inf
    time_next <- min(et, ot)
    if (!is.finite(time_next)) break
    time <- time_next
    # Collect ALL due outcomes before any patient's next-cycle decision,
    # enrollment decision, transition, safety refresh or stopping evaluation.
    ready <- sort(unique(state$pending$patient_id[state$pending$time <= time]))
    state <- mob_prepare_decision(state, time)
    for (id in ready) {
      cycle <- max(which(state$patients[[id]]$outcome_available)) + 1L
      eligible <- TRUE
      if (!is.null(clinical_schedule)) {
        row <- clinical_schedule$patient_id == id & clinical_schedule$cycle == cycle
        if (any(row)) eligible <- clinical_schedule$eligible[which(row)[1L]]
      }
      assignment <- mob_assign_next_cycle(state, id, time, eligible)
      state <- mob_register_observation(assignment$state, assignment, outcome_schedule, time)
    }
    while (state$enrollment_open && next_enrollment <= length(enrollment_times) &&
           enrollment_times[next_enrollment] <= time) {
      assignment <- mob_enroll_patient(state, time)
      state <- mob_register_observation(assignment$state, assignment, outcome_schedule, time)
      next_enrollment <- next_enrollment + 1L
    }
  }
  mob_finalize(state, time)
}
