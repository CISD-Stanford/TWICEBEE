# Administrative event adapter. Scientific decisions are delegated to the core.
csv_columns <- c("event_id", "available_at_utc", "event_type", "subject_code",
                 "patient_id", "cycle", "outcome", "recommendation_id", "dose",
                 "clinically_eligible", "reason")
csv_fields <- list(
  REQUEST_NEW = c("subject_code", "clinically_eligible"),
  REQUEST_NEXT = c("patient_id", "clinically_eligible"),
  CONFIRM_DOSE = c("recommendation_id", "dose", "clinically_eligible"),
  OUTCOME = c("patient_id", "cycle", "outcome"),
  HOLD = c("patient_id", "reason"),
  RELEASE_HOLD = c("patient_id", "clinically_eligible"),
  DISCONTINUE = c("patient_id", "reason"),
  CANCEL_PREVIEW = "recommendation_id",
  CLOSE_ENROLLMENT = "reason", FINALIZE = character())

csv_empty <- function(columns) {
  as.data.frame(setNames(rep(list(character()), length(columns)), columns),
                stringsAsFactors = FALSE)
}
csv_integer <- function(value, field, allow_zero = FALSE) {
  if (!grepl(if (allow_zero) "^(0|[1-9][0-9]*)$" else "^[1-9][0-9]*$", value)) {
    stop(field, " must be a canonical integer")
  }
  number <- suppressWarnings(as.integer(value))
  if (is.na(number)) stop(field, " exceeds the supported integer size")
  number
}
csv_time <- function(value) {
  if (!grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$", value)) {
    stop("available_at_utc must use YYYY-MM-DDTHH:MM:SSZ")
  }
  time <- as.POSIXct(value, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  if (is.na(time) || format(time, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC") != value) {
    stop("Invalid UTC timestamp")
  }
  as.numeric(time) # Seconds since 1970-01-01 UTC; no biological-onset model.
}
csv_read_events <- function(path) {
  x <- read.csv(path, colClasses = "character", na.strings = NULL,
                check.names = FALSE, stringsAsFactors = FALSE,
                strip.white = FALSE, blank.lines.skip = FALSE, fill = FALSE)
  if (!identical(names(x), csv_columns) || anyNA(x)) {
    stop("trial_events.csv must contain exactly the documented columns and blank inapplicable fields")
  }
  x
}
csv_validate_events <- function(events) {
  if (!nrow(events)) return(numeric())
  ids <- vapply(events$event_id, csv_integer, integer(1), field = "event_id")
  if (any(diff(ids) <= 0L)) stop("Event IDs must be unique and strictly increasing")
  times <- vapply(events$available_at_utc, csv_time, numeric(1))
  if (any(diff(times) < 0)) stop("Events must be in nondecreasing availability-time order")
  for (i in seq_len(nrow(events))) {
    e <- events[i, ]
    type <- e$event_type
    if (!type %in% names(csv_fields)) stop("Unknown event_type at event ", e$event_id)
    required <- csv_fields[[type]]
    if (any(e[required] == "")) stop("Missing required field at event ", e$event_id)
    unused <- setdiff(csv_columns, c(csv_columns[1:3], required))
    if (any(e[unused] != "")) stop("Inapplicable fields must be blank at event ", e$event_id)
    if ("clinically_eligible" %in% required && e$clinically_eligible != "TRUE") {
      stop("Explicit clinically_eligible=TRUE required at event ", e$event_id)
    }
    for (f in intersect(required, c("patient_id", "cycle", "dose"))) csv_integer(e[[f]], f)
    if (type == "OUTCOME" && !e$outcome %in% c("0", "1")) stop("OUTCOME must be 0 or 1")
  }
  times
}
csv_source_identity <- function(root) {
  paths <- c(file.path("R", c("configuration.R", "terminal_loss.R", "working_model.R",
             "safety_admissibility.R", "sequential_decisions.R", "trial_engine.R",
             "decision7_terminal.R")), file.path("interface", c("load_engine.R", "csv_interface.R", "twicebee_cli.R")))
  setNames(unname(tools::md5sum(file.path(root, paths))), paths)
}
csv_new_record <- function(config) {
  list(state = NULL, accepted_events = csv_empty(csv_columns),
       recommendations = csv_empty(c("recommendation_id", "subject_code", "patient_id",
         "decision_time_utc", "cycle", "recommended_dose", "status", "explanation",
         "request_event_id", "confirmation_event_id", "confirmation_time_utc", "confirmed_dose")),
       subjects = character(), clinical = list(),
       decision_history = csv_empty(c("processing_order", "source_event_id", "event_type",
         "decision_time_utc", "subject_code", "patient_id", "cycle", "stage", "decision_status",
         "recommendation_id", "recommended_dose", "confirmed_dose", "reason")),
       processing_status = csv_empty(c("event_id", "processing_order", "processing_status", "detail")),
       config = config, last_processing_time = NA_real_)
}
csv_patient <- function(record, value) {
  id <- csv_integer(value, "patient_id")
  if (id > length(record$state$patients)) stop("Unknown patient_id: ", value)
  id
}
csv_ready_reason <- function(record, id) {
  p <- record$state$patients[[id]]
  a <- record$clinical[[id]]
  if (a$discontinued) return(paste0("external_clinical_discontinuation: ", a$discontinuation_reason))
  if (p$guided_status != "active") return(paste(p$guided_status, p$discontinuation_reason))
  if (a$held) return(paste0("clinical_hold: ", a$hold_reason))
  if (any(!is.na(p$doses) & !p$outcome_available)) return("awaiting_assigned_cycle_outcome")
  if (!any(p$outcome_available)) return("no_evaluable_preceding_cycle")
  if (max(which(!is.na(p$doses))) >= record$config$C) return("completed_max_cycle")
  ""
}
csv_require_ready <- function(record, id) {
  why <- csv_ready_reason(record, id)
  if (nzchar(why)) stop("Patient ", id, " unavailable: ", why)
}
csv_pending <- function(record, subject = "", id = "") {
  r <- record$recommendations
  which(r$status == "PENDING" & ((nzchar(subject) & r$subject_code == subject) |
                                  (nzchar(id) & r$patient_id == id)))
}
csv_recommendation <- function(record, value) {
  i <- match(value, record$recommendations$recommendation_id)
  if (is.na(i)) stop("Unknown recommendation_id: ", value)
  if (record$recommendations$status[i] != "PENDING") stop("Recommendation is not pending: ", value)
  i
}
csv_history <- function(record, e, status, id = "", subject = "", cycle = "",
                        recommendation = "", recommended = "", confirmed = "", reason = "",
                        stage = record$state$stage) {
  h <- data.frame(processing_order = as.character(nrow(record$decision_history) + 1L),
    source_event_id = e$event_id, event_type = e$event_type,
    decision_time_utc = e$available_at_utc, subject_code = subject, patient_id = id,
    cycle = cycle, stage = as.character(stage), decision_status = status,
    recommendation_id = recommendation, recommended_dose = recommended,
    confirmed_dose = confirmed, reason = reason, stringsAsFactors = FALSE)
  record$decision_history <- rbind(record$decision_history, h)
  record
}

csv_replay <- function(events, config, engine) {
  times <- csv_validate_events(events)
  record <- csv_new_record(config)
  record$state <- engine$new_trial_state(config)
  for (time in unique(times)) {
    indices <- which(times == time)
    batch <- events[indices, , drop = FALSE]
    csv_check_simultaneous(record, batch)
    outcomes <- which(batch$event_type == "OUTCOME")
    if (length(outcomes)) outcomes <- outcomes[order(as.integer(batch$patient_id[outcomes]),
                                                  as.integer(batch$cycle[outcomes]))]
    ordering <- c(outcomes, which(batch$event_type != "OUTCOME"))
    for (j in ordering) {
      e <- batch[j, , drop = FALSE]
      record <- tryCatch(csv_apply_event(record, e, engine, time), error = function(err) {
        stop("Event ", e$event_id, " (", e$event_type, "): ", conditionMessage(err), call. = FALSE)
      })
    }
    record$last_processing_time <- time
  }
  record$accepted_events <- events
  record
}
csv_patient_status <- function(record) {
  columns <- c("patient_id", "subject_code", "last_confirmed_cycle", "last_observed_cycle",
    "last_evaluable_outcome", "outstanding_assigned_cycles", "guided_status", "statistical_reason",
    "clinical_hold", "hold_reason", "clinical_discontinued", "clinical_discontinuation_reason",
    "pending_recommendation_id", "may_request_decision", "unavailable_reason")
  result <- csv_empty(columns)
  for (id in seq_along(record$state$patients)) {
    p <- record$state$patients[[id]]; a <- record$clinical[[id]]
    last <- if (any(p$outcome_available)) max(which(p$outcome_available)) else NA_integer_
    pending <- csv_pending(record, id = as.character(id))
    reason <- csv_ready_reason(record, id)
    if (!nzchar(reason) && length(pending)) reason <- "pending_preview: confirm_or_cancel"
    if (record$state$trial_complete) reason <- "trial_finalized"
    row <- c(as.character(id), a$subject_code, as.character(max(which(!is.na(p$doses)))),
      if (is.na(last)) "" else as.character(last),
      if (is.na(last)) "" else as.character(p$outcomes[last]),
      paste(which(!is.na(p$doses) & !p$outcome_available), collapse = ";"),
      p$guided_status, if (p$guided_status == "statistical_discontinued") p$discontinuation_reason else "",
      as.character(a$held), a$hold_reason, as.character(a$discontinued), a$discontinuation_reason,
      paste(record$recommendations$recommendation_id[pending], collapse = ";"),
      as.character(!nzchar(reason)), reason)
    result <- rbind(result, setNames(as.data.frame(as.list(row), stringsAsFactors = FALSE), columns))
  }
  result
}

# Generation directories and one atomic POSIX symlink replacement make all outputs
# switch together. Reports and the state always resolve to the same generation.
csv_output_names <- c("trial_state.rds", "trial_config.rds", "recommendations.csv",
                      "patient_status.csv", "decision_history.csv", "accepted_events.csv",
                      "event_processing_status.csv", "terminal_cycle_specific.csv", "terminal_sequence.csv")
csv_write_generation <- function(directory, record, identity) {
  commits <- file.path(directory, ".commits")
  dir.create(commits, showWarnings = FALSE)
  stage <- tempfile("staged-", tmpdir = commits)
  dir.create(stage)
  on.exit(unlink(stage, recursive = TRUE), add = TRUE)
  saveRDS(list(interface_version = "0.1-dev", source_identity = identity, record = record),
          file.path(stage, "trial_state.rds"), version = 3)
  saveRDS(record$config, file.path(stage, "trial_config.rds"), version = 3)
  tables <- list(recommendations = record$recommendations,
    patient_status = csv_patient_status(record), decision_history = record$decision_history,
    accepted_events = record$accepted_events, event_processing_status = record$processing_status,
    terminal_cycle_specific = if (record$state$trial_complete) record$state$decision7$cycle_specific else
      csv_empty(c("cycle", "status", "dose", "direct_n", "admissible_n", "selected_cell_direct_n")),
    terminal_sequence = if (record$state$trial_complete) record$state$decision7$sequence else
      csv_empty(c("cycle", "dose", "in_recommended_sequence")))
  for (name in names(tables)) write.csv(tables[[name]], file.path(stage, paste0(name, ".csv")),
                                      row.names = FALSE, na = "")
  hashes <- setNames(unname(tools::md5sum(file.path(stage, csv_output_names))), csv_output_names)
  saveRDS(hashes, file.path(stage, "output_integrity.rds"))
  generation <- sprintf("g%09d", nrow(record$accepted_events))
  final <- file.path(commits, generation)
  if (dir.exists(final)) stop("Generation already exists; inspect orphaned commit before retrying: ", final)
  if (!file.rename(stage, final)) stop("Cannot complete staged output directory")
  link <- file.path(directory, ".current-next")
  if (nzchar(Sys.readlink(link))) unlink(link)
  if (!file.symlink(file.path(".commits", generation), link)) stop("POSIX symlink support is required")
  if (!file.rename(link, file.path(directory, ".current"))) stop("Cannot atomically commit output generation")
  invisible(record)
}
csv_with_lock <- function(directory, action) {
  lock <- file.path(directory, ".writer-lock")
  if (!dir.create(lock, showWarnings = FALSE)) stop("Trial writer lock exists: ", lock,
    ". Close the other process; if interrupted, follow README recovery instructions.")
  on.exit(unlink(lock, recursive = TRUE), add = TRUE)
  writeLines(as.character(Sys.getpid()), file.path(lock, "pid"))
  action()
}
csv_check_prefix <- function(events, accepted) {
  n <- nrow(accepted)
  if (nrow(events) < n || !identical(events[seq_len(n), , drop = FALSE], accepted)) {
    stop("Previously accepted event history was edited, deleted, or reordered")
  }
}
csv_load_verified <- function(directory, root, engine) {
  generation <- file.path(directory, ".current")
  for (name in csv_output_names) {
    if (!identical(Sys.readlink(file.path(directory, name)), file.path(".current", name))) {
      stop("Output link was replaced: ", name, "; restore its documented .current link")
    }
  }
  saved <- readRDS(file.path(generation, "trial_state.rds"))
  if (!identical(saved$source_identity, csv_source_identity(root))) stop("Engine/interface identity changed since initialization")
  expected <- readRDS(file.path(generation, "output_integrity.rds"))
  actual <- setNames(unname(tools::md5sum(file.path(generation, names(expected)))), names(expected))
  if (!identical(expected, actual)) stop("Saved outputs were altered; restore the committed generation from backup")
  if (!identical(readRDS(file.path(generation, "trial_config.rds")), saved$record$config) ||
      !identical(saved$record$config, engine$twicebee_config())) stop("Initialized configuration changed")
  replay <- csv_replay(saved$record$accepted_events, saved$record$config, engine)
  if (!identical(replay, saved$record)) stop("Accepted-event replay does not reproduce saved state/decisions")
  saved$record
}
csv_init <- function(directory, root) {
  if (dir.exists(directory) && length(list.files(directory, all.files = TRUE, no.. = TRUE))) {
    stop("init requires a new or empty trial directory")
  }
  dir.create(directory, recursive = TRUE, showWarnings = FALSE)
  directory <- normalizePath(directory)
  csv_with_lock(directory, function() {
    engine <- csv_load_engine(root)
    record <- csv_replay(csv_empty(csv_columns), engine$twicebee_config(), engine)
    write.csv(record$accepted_events, file.path(directory, "trial_events.csv"), row.names = FALSE)
    for (name in csv_output_names) {
      if (!file.symlink(file.path(".current", name), file.path(directory, name))) {
        stop("Cannot create output links; v0.1 requires a POSIX local filesystem")
      }
    }
    csv_write_generation(directory, record, csv_source_identity(root))
    record
  })
}
csv_process <- function(directory, root) {
  directory <- normalizePath(directory)
  csv_with_lock(directory, function() {
    engine <- csv_load_engine(root)
    saved <- csv_load_verified(directory, root, engine)
    events <- csv_read_events(file.path(directory, "trial_events.csv"))
    csv_check_prefix(events, saved$accepted_events)
    if (nrow(events) == nrow(saved$accepted_events)) return(saved)
    times <- csv_validate_events(events)
    new_indices <- seq.int(nrow(saved$accepted_events) + 1L, nrow(events))
    if (!is.na(saved$last_processing_time) && any(times[new_indices] <= saved$last_processing_time)) {
      stop("New events must be later than the last committed timestamp; submit equal-time events together")
    }
    # Replay once in full: no persisted observation is applied to persisted counts.
    record <- csv_replay(events, saved$config, engine)
    prefix_replay <- csv_replay(events[seq_len(nrow(saved$accepted_events)), , drop = FALSE], saved$config, engine)
    if (!identical(prefix_replay, saved)) stop("Previously issued decisions do not reproduce")
    # Re-read to detect an input file changed by an editor while processing.
    if (!identical(events, csv_read_events(file.path(directory, "trial_events.csv")))) {
      stop("Input changed during processing; no outputs committed")
    }
    csv_write_generation(directory, record, csv_source_identity(root))
    record
  })
}
csv_status <- function(directory, root) {
  csv_with_lock(directory, function() {
    record <- csv_load_verified(directory, root, csv_load_engine(root))
    csv_check_prefix(csv_read_events(file.path(directory, "trial_events.csv")), record$accepted_events)
    record
  })
}
csv_cli <- function(action, directory, root) {
  record <- switch(action, init = csv_init(directory, root), process = csv_process(directory, root),
                   status = csv_status(directory, root))
  cat("Accepted events:", nrow(record$accepted_events), " | Stage:", record$state$stage,
      " | Enrollment open:", record$state$enrollment_open,
      " | Finalized:", record$state$trial_complete, "\n")
  if (length(record$state$enrollment_closure_reasons)) cat("Closure reasons:",
    paste(record$state$enrollment_closure_reasons, collapse = ";"), "\n")
  pending <- record$recommendations[record$recommendations$status == "PENDING", , drop = FALSE]
  if (nrow(pending)) print(pending[, c("recommendation_id", "subject_code", "patient_id", "cycle", "recommended_dose", "status")], row.names = FALSE)
  patients <- csv_patient_status(record)
  if (nrow(patients)) print(patients[, c("patient_id", "subject_code", "guided_status", "outstanding_assigned_cycles",
                                     "may_request_decision", "unavailable_reason")], row.names = FALSE)
  cat("Outputs:", normalizePath(directory), "\n")
  invisible(record)
}
csv_no_dose_reason <- function(result, id = NULL) {
  if (is.null(id)) paste(result$state$enrollment_closure_reasons, collapse = ";") else
    result$state$patients[[id]]$discontinuation_reason
}

# Outcomes can coexist with a hold/discontinuation of their recipient.
csv_check_simultaneous <- function(record, batch) {
  targets <- batch$patient_id
  rec <- record$recommendations
  # Resolve previews requested earlier in this same timestamp as well.
  future_id <- nrow(rec)
  for (i in seq_len(nrow(batch))) {
    if (batch$event_type[i] %in% c("REQUEST_NEW", "REQUEST_NEXT")) {
      future_id <- future_id + 1L
      rec <- rbind(rec, data.frame(
        recommendation_id = sprintf("R%06d", future_id),
        subject_code = batch$subject_code[i], patient_id = batch$patient_id[i],
        decision_time_utc = "", cycle = "", recommended_dose = "", status = "",
        explanation = "", request_event_id = "", confirmation_event_id = "",
        confirmation_time_utc = "", confirmed_dose = "", stringsAsFactors = FALSE))
    }
  }
  for (i in seq_len(nrow(batch))) {
    if (batch$event_type[i] %in% c("CONFIRM_DOSE", "CANCEL_PREVIEW")) {
      m <- match(batch$recommendation_id[i], rec$recommendation_id)
      if (!is.na(m)) targets[i] <- rec$patient_id[m]
    }
  }
  for (id in unique(targets[nzchar(targets)])) {
    actions <- batch$event_type[targets == id]
    if (("HOLD" %in% actions && any(actions %in% c("RELEASE_HOLD", "REQUEST_NEXT", "CONFIRM_DOSE"))) ||
        ("DISCONTINUE" %in% actions && any(actions %in% c("HOLD", "RELEASE_HOLD", "REQUEST_NEXT", "CONFIRM_DOSE")))) {
      stop("Contradictory simultaneous clinical instructions for patient ", id)
    }
  }
  if ("CLOSE_ENROLLMENT" %in% batch$event_type && "REQUEST_NEW" %in% batch$event_type) {
    stop("Contradictory simultaneous new-enrollment request and closure")
  }
}
csv_apply_event <- function(record, e, engine, time) {
  type <- e$event_type
  if (isTRUE(record$state$trial_complete)) stop("Trial is finalized; no additional events allowed")
  id <- ""; subject <- ""; cycle <- ""; rid <- ""; dose <- ""; confirmed <- ""
  detail <- ""; status <- "ACCEPTED"
  decision_stage <- NULL
  enrollment_was_open <- record$state$enrollment_open
  prior_statistical_ids <- which(vapply(record$state$patients,
    function(p) p$guided_status == "statistical_discontinued", logical(1)))
  if (nzchar(e$patient_id)) {
    id <- csv_patient(record, e$patient_id)
    subject <- record$clinical[[id]]$subject_code
  }
  if (type == "OUTCOME") {
    cycle <- csv_integer(e$cycle, "cycle")
    p <- record$state$patients[[id]]
    if (cycle > record$config$C || is.na(p$doses[cycle])) stop("OUTCOME requires a confirmed assignment")
    if (p$outcome_available[cycle]) stop("Duplicate outcome for patient-cycle")
    if (time <= p$assignment_times[cycle]) stop("OUTCOME must become available after confirmed assignment")
    record$state <- engine$incorporate_outcome(record$state, id, cycle, as.integer(e$outcome), time)
    status <- "OUTCOME_INCORPORATED"
    detail <- paste0("outcome=", e$outcome)
  } else if (type %in% c("REQUEST_NEW", "REQUEST_NEXT")) {
    if (type == "REQUEST_NEW") {
      subject <- e$subject_code
      if (subject %in% vapply(record$clinical, function(a) a$subject_code, character(1))) stop("Subject already enrolled")
      if (length(csv_pending(record, subject = subject))) stop("Subject has a pending preview; cancel it first")
      record$subjects <- unique(c(record$subjects, subject))
      result <- engine$enroll_patient(record$state, time)
      cycle <- 1L
    } else {
      csv_require_ready(record, id)
      if (length(csv_pending(record, id = as.character(id)))) stop("Patient has a pending preview; cancel it first")
      cycle <- max(which(record$state$patients[[id]]$outcome_available)) + 1L
      result <- engine$assign_next_cycle(record$state, id, time)
    }
    rid <- sprintf("R%06d", nrow(record$recommendations) + 1L)
    status <- if (isTRUE(result$assigned)) "PENDING" else "NO_DOSE_AVAILABLE"
    if (isTRUE(result$assigned)) {
      dose <- as.character(result$dose)
      decision_stage <- tail(result$state$decision_log, 1)[[1]]$stage
      # Do not retain previewed enrollment, assignments, or stage transition.
    } else {
      record$state <- result$state # Mandatory statistical consequence, no dose.
      detail <- csv_no_dose_reason(result, if (type == "REQUEST_NEXT") id else NULL)
    }
    record$recommendations <- rbind(record$recommendations, data.frame(
      recommendation_id = rid, subject_code = subject,
      patient_id = as.character(id), decision_time_utc = e$available_at_utc,
      cycle = as.character(cycle), recommended_dose = dose, status = status,
      explanation = detail, request_event_id = e$event_id, confirmation_event_id = "",
      confirmation_time_utc = "", confirmed_dose = "", stringsAsFactors = FALSE))
  } else if (type == "CONFIRM_DOSE") {
    i <- csv_recommendation(record, e$recommendation_id)
    r <- record$recommendations[i, ]
    rid <- r$recommendation_id; subject <- r$subject_code; cycle <- as.integer(r$cycle)
    dose <- r$recommended_dose
    if (nzchar(r$patient_id)) {
      id <- csv_patient(record, r$patient_id)
      csv_require_ready(record, id)
      result <- engine$assign_next_cycle(record$state, id, time)
    } else {
      result <- engine$enroll_patient(record$state, time)
    }
    if (!isTRUE(result$assigned)) {
      record$state <- result$state
      status <- "INVALIDATED_NO_DOSE"
      detail <- csv_no_dose_reason(result, if (nzchar(r$patient_id)) id else NULL)
      # An attempted confirmation cannot create an administered dose.
    } else {
      if (result$cycle != cycle || as.character(result$dose) != dose || e$dose != dose) {
        stop("Stale or inconsistent confirmation; cancel preview and request a new recommendation")
      }
      record$state <- result$state
      id <- result$patient_id
      if (!nzchar(r$patient_id)) record$clinical[[id]] <- list(
        subject_code = subject, held = FALSE, hold_reason = "", discontinued = FALSE,
        discontinuation_reason = "")
      confirmed <- dose
      status <- "CONFIRMED"
      decision_stage <- tail(result$state$decision_log, 1)[[1]]$stage
    }
    record$recommendations$status[i] <- status
    record$recommendations$explanation[i] <- detail
    record$recommendations$patient_id[i] <- as.character(id)
    record$recommendations$confirmation_event_id[i] <- e$event_id
    record$recommendations$confirmation_time_utc[i] <- e$available_at_utc
    record$recommendations$confirmed_dose[i] <- confirmed
  } else if (type == "CANCEL_PREVIEW") {
    i <- csv_recommendation(record, e$recommendation_id)
    r <- record$recommendations[i, ]
    rid <- r$recommendation_id; id <- r$patient_id; subject <- r$subject_code; cycle <- r$cycle
    dose <- r$recommended_dose
    record$recommendations$status[i] <- "CANCELED"
    status <- "CANCELED"
  } else if (type == "HOLD") {
    if (record$clinical[[id]]$discontinued || record$state$patients[[id]]$guided_status != "active") {
      stop("Cannot hold an inactive patient")
    }
    if (record$clinical[[id]]$held) stop("Patient is already held")
    record$clinical[[id]]$held <- TRUE
    record$clinical[[id]]$hold_reason <- e$reason
    status <- "CLINICAL_HOLD"; detail <- e$reason
  } else if (type == "RELEASE_HOLD") {
    if (!record$clinical[[id]]$held || record$clinical[[id]]$discontinued ||
        record$state$patients[[id]]$guided_status != "active") stop("No releasable clinical hold")
    record$clinical[[id]]$held <- FALSE
    record$clinical[[id]]$hold_reason <- ""
    status <- "HOLD_RELEASED"
  } else if (type == "DISCONTINUE") {
    if (record$clinical[[id]]$discontinued) stop("Patient already clinically discontinued")
    record$clinical[[id]]$discontinued <- TRUE
    record$clinical[[id]]$discontinuation_reason <- e$reason
    # Represent external eligibility in the engine's conduct-status field.
    # Preserve any prior statistical or max-cycle status and its reason.
    if (record$state$patients[[id]]$guided_status == "active") {
      record$state$patients[[id]]$guided_status <- "external_clinical_discontinued"
      record$state$patients[[id]]$discontinuation_reason <- e$reason
    }
    pending <- csv_pending(record, id = as.character(id))
    record$recommendations$status[pending] <- "CANCELED_CLINICAL_DISCONTINUATION"
    record$recommendations$explanation[pending] <- e$reason
    status <- "EXTERNAL_CLINICAL_DISCONTINUATION"; detail <- e$reason
  } else if (type == "CLOSE_ENROLLMENT") {
    record$state <- engine$close_enrollment(record$state, time, paste0("administrative: ", e$reason))
    pending <- which(record$recommendations$status == "PENDING" & record$recommendations$patient_id == "")
    record$recommendations$status[pending] <- "CANCELED_ENROLLMENT_CLOSURE"
    record$recommendations$explanation[pending] <- e$reason
    status <- "ENROLLMENT_CLOSED"
    detail <- paste(record$state$enrollment_closure_reasons, collapse = ";")
  } else if (type == "FINALIZE") {
    if (record$state$enrollment_open) stop("FINALIZE requires closed enrollment")
    if (any(vapply(record$state$patients, function(p) any(!is.na(p$doses) & !p$outcome_available), logical(1)))) {
      stop("FINALIZE requires all assigned outcomes to be resolved, including discontinued patients")
    }
    if (any(vapply(record$state$patients, function(p) p$guided_status == "active", logical(1)))) {
      stop("FINALIZE requires no active patients awaiting treatment/follow-up decisions")
    }
    if (any(record$recommendations$status == "PENDING")) stop("Cancel pending previews before FINALIZE")
    record$state <- engine$attach_decision7(engine$finalize_trial_state(record$state, time))
    status <- "FINALIZED"
  }
  if (enrollment_was_open && !record$state$enrollment_open) {
    detail <- paste(c(detail[nzchar(detail)], paste0("enrollment_closed: ",
      paste(record$state$enrollment_closure_reasons, collapse = ";"))), collapse = ";")
  }
  if (nzchar(as.character(id)) && !as.integer(id) %in% prior_statistical_ids &&
      record$state$patients[[as.integer(id)]]$guided_status == "statistical_discontinued") {
    detail <- paste(c(detail[nzchar(detail)], paste0("statistical_discontinued: ",
      record$state$patients[[as.integer(id)]]$discontinuation_reason)), collapse = ";")
  }
  record <- csv_history(record, e, status, as.character(id), subject, as.character(cycle),
                        rid, dose, confirmed, detail,
                        if (is.null(decision_stage)) record$state$stage else decision_stage)
  record$processing_status <- rbind(record$processing_status, data.frame(
    event_id = e$event_id, processing_order = as.character(nrow(record$processing_status) + 1L),
    processing_status = status, detail = detail, stringsAsFactors = FALSE))
  record
}
