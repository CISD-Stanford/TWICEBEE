# Candidate construction and Stage-2 sequential dose decisions.

collapse_int <- function(x) {
  if (!length(x)) "" else paste(sort(unique(as.integer(x))), collapse = ",")
}

qualifying_previous_destination <- function(state, patient_id, cycle) {
  if (!length(state$patients)) return(integer())
  eligible <- vapply(state$patients, function(patient) {
    patient$id < patient_id &&
      !is.na(patient$outcomes[cycle]) &&
      patient$outcome_available[cycle]
  }, logical(1))
  ids <- which(eligible)
  if (!length(ids)) return(integer())
  tail(ids, state$config$cohort_size)
}

ordinary_ongoing_decision <- function(state, patient_id, cycle,
                                      external_candidates = seq_len(state$config$J)) {
  patient <- state$patients[[patient_id]]
  previous_dose <- patient$doses[cycle - 1L]
  admissible <- intersect(
    population_admissible_doses(state$excluded, cycle),
    external_candidates
  )
  current_candidates <- admissible[admissible <= min(state$config$J, previous_dose + 1L)]
  current_recommendation <- select_by_utility(
    state$alpha, state$beta, cycle, current_candidates, state$config
  )
  if (is.na(current_recommendation)) {
    return(list(dose = NA_integer_, current_candidates = current_candidates,
                previous_candidates = integer(), fallback = TRUE,
                previous_component = NA_integer_, qualifying_ids = integer(),
                previous_anchor_doses = integer(), post_dlt = FALSE))
  }

  qualifying_ids <- qualifying_previous_destination(state, patient_id, cycle)
  if (!length(qualifying_ids)) {
    return(list(
      dose = current_recommendation,
      current_candidates = current_candidates,
      previous_candidates = integer(),
      fallback = TRUE,
      previous_component = NA_integer_,
      qualifying_ids = integer(),
      previous_anchor_doses = integer(),
      post_dlt = FALSE
    ))
  }

  anchors <- sort(unique(vapply(
    qualifying_ids,
    function(id) state$patients[[id]]$doses[cycle],
    integer(1)
  )))
  previous_recommendations <- integer()
  previous_candidates <- list()
  for (anchor in anchors) {
    candidates <- admissible[admissible <= min(state$config$J, anchor + 1L)]
    recommendation <- select_by_utility(
      state$alpha, state$beta, cycle, candidates, state$config
    )
    previous_candidates[[as.character(anchor)]] <- candidates
    if (!is.na(recommendation)) {
      previous_recommendations <- c(previous_recommendations, recommendation)
    }
  }
  previous_component <- if (length(previous_recommendations)) {
    min(previous_recommendations)
  } else {
    NA_integer_
  }
  assigned <- if (is.na(previous_component)) {
    current_recommendation
  } else {
    min(current_recommendation, previous_component)
  }
  list(
    dose = assigned,
    current_candidates = current_candidates,
    previous_candidates = previous_candidates,
    fallback = is.na(previous_component),
    previous_component = previous_component,
    qualifying_ids = qualifying_ids,
    previous_anchor_doses = anchors,
    post_dlt = FALSE
  )
}

post_dlt_decision <- function(state, patient_id, cycle,
                              external_candidates = seq_len(state$config$J)) {
  patient <- state$patients[[patient_id]]
  dlt_dose <- patient$doses[cycle - 1L]
  if (dlt_dose == 1L) {
    return(list(
      dose = NA_integer_, current_candidates = integer(),
      previous_candidates = integer(), fallback = TRUE,
      previous_component = NA_integer_, qualifying_ids = integer(),
      previous_anchor_doses = integer(), post_dlt = TRUE
    ))
  }
  admissible <- intersect(
    population_admissible_doses(state$excluded, cycle),
    external_candidates
  )
  candidates <- admissible[admissible <= dlt_dose - 1L]
  list(
    dose = select_by_utility(state$alpha, state$beta, cycle, candidates, state$config),
    current_candidates = candidates,
    previous_candidates = integer(),
    fallback = TRUE,
    previous_component = NA_integer_, qualifying_ids = integer(),
    previous_anchor_doses = integer(), post_dlt = TRUE
  )
}

decide_ongoing_patient <- function(state, patient_id, cycle,
                                   external_candidates = seq_len(state$config$J)) {
  previous_outcome <- state$patients[[patient_id]]$outcomes[cycle - 1L]
  if (previous_outcome == 1L) {
    post_dlt_decision(state, patient_id, cycle, external_candidates)
  } else {
    ordinary_ongoing_decision(state, patient_id, cycle, external_candidates)
  }
}

decide_new_patient <- function(state, patient_id,
                               external_candidates = seq_len(state$config$J)) {
  cohort_size <- state$config$cohort_size
  cohort_id <- ((patient_id - 1L) %/% cohort_size) + 1L
  cohort_member_ids <- which(vapply(state$patients, function(patient) {
    patient$cohort_id == cohort_id
  }, logical(1)))
  admissible <- intersect(
    population_admissible_doses(state$excluded, 1L),
    external_candidates
  )

  if (length(cohort_member_ids)) {
    anchor <- state$patients[[cohort_member_ids[1L]]]$doses[1L]
    if (anchor %in% admissible) {
      return(list(
        dose = anchor, candidates = anchor, cohort_id = cohort_id,
        cohort_anchor = anchor, cohort_completion = TRUE,
        safety_override = FALSE
      ))
    }
    candidates <- admissible[admissible <= min(state$config$J, anchor + 1L)]
    return(list(
      dose = select_by_utility(state$alpha, state$beta, 1L, candidates, state$config),
      candidates = candidates, cohort_id = cohort_id,
      cohort_anchor = anchor, cohort_completion = TRUE,
      safety_override = TRUE
    ))
  }

  if (patient_id == 1L) {
    anchor <- state$config$starting_dose
  } else {
    previous_ids <- which(vapply(state$patients, function(patient) {
      patient$cohort_id == cohort_id - 1L
    }, logical(1)))
    anchor <- state$patients[[tail(previous_ids, 1L)]]$doses[1L]
  }
  candidates <- admissible[admissible <= min(state$config$J, anchor + 1L)]
  list(
    dose = select_by_utility(state$alpha, state$beta, 1L, candidates, state$config),
    candidates = candidates, cohort_id = cohort_id,
    cohort_anchor = anchor, cohort_completion = FALSE,
    safety_override = FALSE
  )
}
