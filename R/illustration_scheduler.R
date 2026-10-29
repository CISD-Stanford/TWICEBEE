# Required current functions extracted unchanged; see docs/SOURCE_MAPPING.md.

append_outcome_event <- function(events, assignment, config) {
  rbind(events, data.frame(
    time = assignment$time + config$cycle_duration,
    patient_id = assignment$patient_id,
    cycle = assignment$cycle,
    dose = assignment$dose
  ))
}


run_scheduled_trial <- function(config, outcome_function, trace_detail = FALSE,
                                trial_id = NA_integer_, profile = NA_character_) {
  state <- new_trial_state(config, trace_detail, trial_id, profile)
  events <- data.frame(time = numeric(), patient_id = integer(),
                       cycle = integer(), dose = integer())
  next_enrollment_id <- 1L
  current_time <- 0

  repeat {
    next_enrollment_time <- if (state$enrollment_open &&
                                next_enrollment_id <= config$max_enrollment) {
      config$enrollment_interval * (next_enrollment_id - 1L)
    } else {
      Inf
    }
    next_outcome_time <- if (nrow(events)) min(events$time) else Inf
    if (!is.finite(next_enrollment_time) && !is.finite(next_outcome_time)) break

    if (next_outcome_time <= next_enrollment_time) {
      row <- which.min(events$time)
      event <- events[row, , drop = FALSE]
      events <- events[-row, , drop = FALSE]
      current_time <- event$time
      outcome <- as.integer(outcome_function(
        event$patient_id, event$cycle, event$dose
      ))
      state <- incorporate_outcome(
        state, event$patient_id, event$cycle, outcome, current_time
      )
      assignment <- assign_next_cycle(state, event$patient_id, current_time)
      state <- assignment$state
      if (assignment$assigned) {
        assignment$time <- current_time
        events <- append_outcome_event(events, assignment, config)
      }
    } else {
      current_time <- next_enrollment_time
      enrollment <- enroll_patient(state, current_time)
      state <- enrollment$state
      if (enrollment$assigned) {
        enrollment$time <- current_time
        events <- append_outcome_event(events, enrollment, config)
        next_enrollment_id <- next_enrollment_id + 1L
      } else if (!state$enrollment_open) {
        next_enrollment_id <- config$max_enrollment + 1L
      }
    }
  }
  finalize_trial_state(state, current_time)
}


run_stochastic_trial <- function(probability_surface, seed, config,
                                 trial_id, profile) {
  set.seed(seed)
  outcome_function <- function(patient_id, cycle, dose) {
    rbinom(1L, 1L, probability_surface[dose, cycle])
  }
  run_scheduled_trial(config, outcome_function, FALSE, trial_id, profile)
}

