# Decision 7: terminal reporting from a completed revised TWICEBEE state.
# eu_symmetric_loss() is the established closed-form EU-SYM loss in
# package_b_terminal.R; sequential dosing restrictions are not used here.

decision7_terminal_result <- function(state) {
  if (!isTRUE(state$trial_complete) || isTRUE(state$enrollment_open) ||
      any(!is.na(state$dose_history) & !state$outcome_availability)) {
    stop("Decision 7 requires ended enrollment and resolved follow-up")
  }

  cycles <- lapply(seq_len(state$config$C), function(cycle) {
    admissible <- which(!state$excluded[, cycle])
    direct_by_dose <- state$direct_dlt[, cycle] + state$direct_nondlt[, cycle]
    direct_n <- sum(direct_by_dose)
    status <- if (!length(admissible)) {
      "NO_ADMISSIBLE_DOSE"
    } else if (direct_n == 0L) {
      "INSUFFICIENT_DIRECT_INFORMATION"
    } else {
      "RECOMMENDED"
    }

    dose <- NA_integer_
    if (status == "RECOMMENDED") {
      loss <- eu_symmetric_loss(
        state$config$theta0, state$alpha[admissible, cycle],
        state$beta[admissible, cycle]
      )
      tied <- admissible[abs(loss - min(loss)) <= 1e-12]
      dose <- min(tied)
    }
    data.frame(
      cycle = cycle, status = status, dose = dose,
      direct_n = direct_n, admissible_n = length(admissible),
      selected_cell_direct_n = if (is.na(dose)) NA_integer_ else direct_by_dose[dose],
      stringsAsFactors = FALSE
    )
  })
  cycle_result <- do.call(rbind, cycles)

  first_unsupported <- which(cycle_result$status != "RECOMMENDED")[1L]
  if (is.na(first_unsupported)) first_unsupported <- NA_integer_
  in_sequence <- if (is.na(first_unsupported)) {
    rep(TRUE, state$config$C)
  } else {
    seq_len(state$config$C) < first_unsupported
  }
  sequence_result <- data.frame(
    cycle = cycle_result$cycle,
    dose = ifelse(in_sequence, cycle_result$dose, NA_integer_),
    in_recommended_sequence = in_sequence
  )

  list(
    specification_version = "v0.5 (2026-09-22)",
    cycle_specific = cycle_result,
    sequence = sequence_result,
    recommended_sequence = cycle_result$dose[in_sequence],
    first_unsupported_cycle = first_unsupported
  )
}

attach_decision7 <- function(state) {
  state$decision7 <- decision7_terminal_result(state)
  state
}
