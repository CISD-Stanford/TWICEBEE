args <- commandArgs(trailingOnly = TRUE)
script <- sub("^--file=", "", commandArgs()[grepl("^--file=", commandArgs())])
root <- dirname(dirname(normalizePath(script)))
source(file.path(root, "interface", "load_engine.R"))
source(file.path(root, "interface", "csv_interface.R"))
source(file.path(root, "tests", "event_helpers.R"))
engine <- csv_load_engine(root)
config <- engine$twicebee_config()
replay <- function(events) csv_replay(events, config, engine)
work <- tempfile("twicebee-csv-targeted-")
dir.create(work)
results <- data.frame(check = character(), result = character(), detail = character())
check <- function(name, detail, action) {
  action()
  results <<- rbind(results, data.frame(check = name, result = "PASS", detail = detail))
  cat(name, ": PASS\n", sep = "")
}
append_process <- function(directory, events) {
  write.csv(events, file.path(directory, "trial_events.csv"), row.names = FALSE, na = "")
  csv_process(directory, root)
}
output_hashes <- function(directory) unname(tools::md5sum(file.path(directory, csv_output_names)))


# All doses are issued/confirmed through the interface; all outcomes below are
# fixed fictional 1s. No scientific shapes, counts, or exclusions are edited.
append_fixed <- function(events, type, ...) {
  n <- nrow(events) + 1L
  join_events(events, event(n, n, type, ...))
}
enrollment_fixture <- function(pending_before_last = FALSE) {
  events <- csv_empty(csv_columns)
  for (i in 1:12) {
    if (i == 12L && pending_before_last) events <- append_fixed(events, "REQUEST_NEW",
      subject_code = "WAIT", clinically_eligible = "TRUE")
    events <- append_fixed(events, "REQUEST_NEW", subject_code = paste0("T", i), clinically_eligible = "TRUE")
    recommendation <- tail(replay(events)$recommendations, 1)
    events <- append_fixed(events, "CONFIRM_DOSE", recommendation_id = recommendation$recommendation_id,
                           dose = recommendation$recommended_dose, clinically_eligible = "TRUE")
  }
  events
}

check("A", "Incremental administered histories agree exactly with direct core calls", function() {
  d <- file.path(work, "incremental")
  csv_init(d, root)
  first <- initial_events()
  actual <- append_process(d, first)
  direct <- engine$enroll_patient(engine$new_trial_state(config), csv_time(first$available_at_utc[2]))$state
  stopifnot(identical(actual$state, direct))
  full <- join_events(first,
    event(3, 3, "OUTCOME", patient_id = 1, cycle = 1, outcome = 0),
    event(4, 4, "REQUEST_NEXT", patient_id = 1, clinically_eligible = "TRUE"),
    event(5, 5, "CONFIRM_DOSE", recommendation_id = "R000002", dose = 2, clinically_eligible = "TRUE"),
    event(6, 6, "OUTCOME", patient_id = 1, cycle = 2, outcome = 1))
  append_process(d, full[1:3, ])
  preview <- append_process(d, full[1:4, ])
  stopifnot(is.na(preview$state$patients[[1]]$doses[2]))
  append_process(d, full[1:5, ])
  actual <- append_process(d, full)
  direct <- engine$incorporate_outcome(direct, 1L, 1L, 0L, csv_time(full$available_at_utc[3]))
  direct <- engine$assign_next_cycle(direct, 1L, csv_time(full$available_at_utc[5]))$state
  direct <- engine$incorporate_outcome(direct, 1L, 2L, 1L, csv_time(full$available_at_utc[6]))
  stopifnot(identical(actual$state, direct), actual$state$stage == 2L,
            sum(actual$state$direct_dlt) == 1L, sum(actual$state$direct_nondlt) == 1L)
})
check("B", "Duplicate outcomes/confirmations and pending-outcome bypass rejected", function() {
  first <- initial_events()
  test_expect_error(function() replay(join_events(first,
    event(3, 3, "CONFIRM_DOSE", recommendation_id = "R000001", dose = 1, clinically_eligible = "TRUE"))),
    "not pending")
  test_expect_error(function() replay(join_events(first,
    event(3, 3, "REQUEST_NEXT", patient_id = 1, clinically_eligible = "TRUE"))), "awaiting_assigned_cycle_outcome")
  observed <- join_events(first, event(3, 3, "OUTCOME", patient_id = 1, cycle = 1, outcome = 0))
  test_expect_error(function() replay(join_events(observed,
    event(4, 4, "OUTCOME", patient_id = 1, cycle = 1, outcome = 1))), "Duplicate outcome")
  test_expect_error(function() replay(join_events(first,
    event(3, 3, "OUTCOME", patient_id = 1, cycle = 2, outcome = 0))), "confirmed assignment")
  stopifnot(sum(replay(observed)$state$direct_nondlt) == 1L)
})
check("C", "Noncommitting previews/cancellation; inconsistent and genuinely stale confirmation", function() {
  preview <- replay(initial_events()[1, ])
  stopifnot(identical(preview$state, engine$new_trial_state(config)))
  canceled <- replay(join_events(initial_events()[1, ], event(2, 2, "CANCEL_PREVIEW", recommendation_id = "R000001")))
  stopifnot(identical(canceled$state, engine$new_trial_state(config)), canceled$recommendations$status == "CANCELED")
  test_expect_error(function() replay(join_events(initial_events()[1, ],
    event(2, 2, "CONFIRM_DOSE", recommendation_id = "R000001", dose = 2, clinically_eligible = "TRUE"))), "inconsistent")
  # A pending new-patient Stage-1 preview becomes stale after six actual
  # enrollments enter Stage 2 and the next starting-dose cohort changes dose.
  stale <- csv_empty(csv_columns)
  for (i in 1:5) stale <- join_events(stale,
    event(2*i-1, 2*i-1, "REQUEST_NEW", subject_code = paste0("S00", i), clinically_eligible = "TRUE"),
    event(2*i, 2*i, "CONFIRM_DOSE", recommendation_id = sprintf("R%06d", i), dose = 1, clinically_eligible = "TRUE"))
  stale <- join_events(stale,
    event(11, 11, "REQUEST_NEW", subject_code = "STALE", clinically_eligible = "TRUE"),
    event(12, 12, "REQUEST_NEW", subject_code = "S006", clinically_eligible = "TRUE"),
    event(13, 13, "CONFIRM_DOSE", recommendation_id = "R000007", dose = 1, clinically_eligible = "TRUE"))
  current <- replay(stale)
  fresh <- engine$enroll_patient(current$state, csv_time(event(14, 14, "FINALIZE")$available_at_utc))
  stopifnot(fresh$assigned, fresh$dose != 1L)
  test_expect_error(function() replay(join_events(stale,
    event(14, 14, "CONFIRM_DOSE", recommendation_id = "R000006", dose = 1, clinically_eligible = "TRUE"))), "Stale")
  events <- enrollment_fixture(TRUE)
  before <- replay(events)
  waiting <- before$recommendations[before$recommendations$subject_code == "WAIT", ]
  stopifnot(!before$state$enrollment_open, length(before$state$patients) == 12L)
  confirmed <- append_fixed(events, "CONFIRM_DOSE", recommendation_id = waiting$recommendation_id,
                            dose = waiting$recommended_dose, clinically_eligible = "TRUE")
  denied <- replay(confirmed)
  expected <- engine$enroll_patient(before$state, csv_time(tail(confirmed$available_at_utc, 1)))$state
  stopifnot(identical(denied$state, expected), length(denied$state$patients) == 12L,
            denied$recommendations$status[denied$recommendations$subject_code == "WAIT"] == "INVALIDATED_NO_DOSE",
            denied$recommendations$confirmed_dose[denied$recommendations$subject_code == "WAIT"] == "")
  denied_request <- replay(append_fixed(confirmed, "REQUEST_NEW", subject_code = "NO_SLOT", clinically_eligible = "TRUE"))
  stopifnot(identical(denied_request$state, expected), tail(denied_request$recommendations$status, 1) == "NO_DOSE_AVAILABLE")
  closed <- replay(join_events(initial_events()[1, ],
    event(2, 2, "CLOSE_ENROLLMENT", reason = "authorized administrative closure"),
    event(3, 3, "REQUEST_NEW", subject_code = "F002", clinically_eligible = "TRUE")))
  stopifnot(!closed$state$enrollment_open, length(closed$state$patients) == 0L,
            tail(closed$recommendations$status, 1) == "NO_DOSE_AVAILABLE")
})
check("D", "Equal-time outcomes first in patient-ID order; backdating and contradictions rejected", function() {
  events <- join_events(initial_events(),
    event(3, 3, "REQUEST_NEW", subject_code = "F002", clinically_eligible = "TRUE"),
    event(4, 4, "CONFIRM_DOSE", recommendation_id = "R000002", dose = 1, clinically_eligible = "TRUE"),
    event(5, 5, "REQUEST_NEXT", patient_id = 1, clinically_eligible = "TRUE"),
    event(6, 5, "OUTCOME", patient_id = 2, cycle = 1, outcome = 1),
    event(7, 5, "OUTCOME", patient_id = 1, cycle = 1, outcome = 0))
  r <- replay(events)
  stopifnot(identical(tail(r$processing_status$event_id, 3), c("7", "6", "5")))
  direct <- engine$enroll_patient(engine$new_trial_state(config), csv_time(events$available_at_utc[2]))$state
  direct <- engine$enroll_patient(direct, csv_time(events$available_at_utc[4]))$state
  direct <- engine$incorporate_outcome(direct, 1L, 1L, 0L, csv_time(events$available_at_utc[7]))
  direct <- engine$incorporate_outcome(direct, 2L, 1L, 1L, csv_time(events$available_at_utc[6]))
  stopifnot(identical(r$state, direct),
            as.integer(r$recommendations$recommended_dose[3]) ==
              engine$assign_next_cycle(direct, 1L, csv_time(events$available_at_utc[5]))$dose)
  d <- file.path(work, "chronology"); csv_init(d, root); append_process(d, initial_events())
  before <- output_hashes(d)
  edited <- initial_events(); edited$available_at_utc[1] <- "2026-10-12T00:30:00Z"
  test_expect_error(function() append_process(d, edited), "accepted event history")
  test_expect_error(function() append_process(d, join_events(initial_events(),
    event(3, 2, "OUTCOME", patient_id = 1, cycle = 1, outcome = 0))), "later than")
  test_expect_error(function() append_process(d, join_events(initial_events(),
    event(3, 1, "OUTCOME", patient_id = 1, cycle = 1, outcome = 0))), "nondecreasing")
  stopifnot(identical(before, output_hashes(d)))
  for (modified in list(initial_events()[1, ], initial_events()[2:1, ])) {
    test_expect_error(function() append_process(d, modified), "accepted event history")
  }
  repeated_id <- initial_events(); repeated_id$event_id[2] <- "1"
  test_expect_error(function() replay(repeated_id), "unique and strictly increasing")
  test_expect_error(function() replay(join_events(initial_events(),
    event(3, 3, "HOLD", patient_id = 1, reason = "recovery"),
    event(4, 3, "RELEASE_HOLD", patient_id = 1, clinically_eligible = "TRUE"))), "Contradictory")
})
check("E", "Holds require release/renewed eligibility; clinical stops retain outstanding outcomes", function() {
  held <- join_events(initial_events(), event(3, 3, "HOLD", patient_id = 1, reason = "fictional recovery"),
    event(4, 4, "OUTCOME", patient_id = 1, cycle = 1, outcome = 0))
  r <- replay(held)
  stopifnot(r$clinical[[1]]$held, sum(r$state$direct_nondlt) == 1)
  test_expect_error(function() replay(join_events(held,
    event(5, 5, "REQUEST_NEXT", patient_id = 1, clinically_eligible = "TRUE"))), "clinical_hold")
  test_expect_error(function() replay(join_events(held,
    event(5, 5, "RELEASE_HOLD", patient_id = 1, clinically_eligible = "FALSE"))), "clinically_eligible=TRUE")
  released <- join_events(held, event(5, 5, "RELEASE_HOLD", patient_id = 1, clinically_eligible = "TRUE"),
    event(6, 6, "REQUEST_NEXT", patient_id = 1, clinically_eligible = "TRUE"))
  r <- replay(released)
  stopifnot(!r$clinical[[1]]$held, is.na(r$state$patients[[1]]$doses[2]))
  test_expect_error(function() replay(join_events(released,
    event(7, 7, "CONFIRM_DOSE", recommendation_id = "R000002", dose = 2, clinically_eligible = "FALSE"))), "clinically_eligible=TRUE")
  held_preview <- join_events(released, event(7, 7, "HOLD", patient_id = 1, reason = "new clinical hold"))
  test_expect_error(function() replay(join_events(held_preview,
    event(8, 8, "CONFIRM_DOSE", recommendation_id = "R000002", dose = 2, clinically_eligible = "TRUE"))), "clinical_hold")
  stopped <- join_events(initial_events(), event(3, 3, "DISCONTINUE", patient_id = 1, reason = "fictional clinical stop"))
  r <- replay(stopped)
  stopifnot(identical(r$state$patients[[1]]$doses, replay(initial_events())$state$patients[[1]]$doses),
            csv_patient_status(r)$outstanding_assigned_cycles == "1")
  test_expect_error(function() replay(join_events(stopped,
    event(4, 4, "REQUEST_NEXT", patient_id = 1, clinically_eligible = "TRUE"))), "external_clinical_discontinuation")
  r <- replay(join_events(stopped, event(4, 4, "OUTCOME", patient_id = 1, cycle = 1, outcome = 1)))
  stopifnot(sum(r$state$direct_dlt) == 1, r$state$patients[[1]]$guided_status == "statistical_discontinued",
            r$clinical[[1]]$discontinued)
})
check("F", "Multi-session replay/idempotence/atomic rejection/config and output integrity/single writer", function() {
  d <- file.path(work, "incremental")
  events <- csv_read_events(file.path(d, "trial_events.csv"))
  saved <- csv_status(d, root)
  stopifnot(identical(saved, replay(events)))
  before <- output_hashes(d); pointer <- Sys.readlink(file.path(d, ".current"))
  again <- csv_process(d, root)
  stopifnot(identical(saved, again), identical(before, output_hashes(d)),
            identical(pointer, Sys.readlink(file.path(d, ".current"))))
  invalid <- join_events(events,
    event(7, 7, "REQUEST_NEW", subject_code = "F003", clinically_eligible = "TRUE"),
    event(8, 8, "OUTCOME", patient_id = 1, cycle = 2, outcome = 1))
  test_expect_error(function() append_process(d, invalid), "Duplicate")
  stopifnot(identical(before, output_hashes(d)), identical(pointer, Sys.readlink(file.path(d, ".current"))))
  write.csv(events, file.path(d, "trial_events.csv"), row.names = FALSE)
  dir.create(file.path(d, ".writer-lock"))
  test_expect_error(function() csv_process(d, root), "writer lock exists")
  unlink(file.path(d, ".writer-lock"), recursive = TRUE)
  # Confirm output edits and configuration edits are detected, then restore bytes.
  path <- file.path(d, "recommendations.csv"); bytes <- readBin(path, "raw", n = file.info(path)$size)
  write("edited", path, append = TRUE)
  test_expect_error(function() csv_status(d, root), "Saved outputs were altered")
  writeBin(bytes, path)
  path <- file.path(d, "trial_config.rds"); bytes <- readBin(path, "raw", n = file.info(path)$size)
  changed <- config; changed$theta0 <- 0.2; saveRDS(changed, path)
  test_expect_error(function() csv_process(d, root), "Saved outputs were altered")
  writeBin(bytes, path)
  stopifnot(identical(saved, csv_status(d, root)))
  path <- file.path(d, "patient_status.csv")
  unlink(path); writeLines("replaced report link", path)
  test_expect_error(function() csv_status(d, root), "Output link was replaced")
  unlink(path); stopifnot(file.symlink(file.path(".current", "patient_status.csv"), path))
  # A staging/commit precondition failure leaves the existing generation intact.
  valid <- join_events(events, event(7, 7, "REQUEST_NEW", subject_code = "F004", clinically_eligible = "TRUE"))
  orphan <- file.path(d, ".commits", "g000000007"); dir.create(orphan)
  test_expect_error(function() append_process(d, valid), "Generation already exists")
  stopifnot(identical(before, output_hashes(d)), identical(pointer, Sys.readlink(file.path(d, ".current"))))
  unlink(orphan, recursive = TRUE)
  write.csv(events, file.path(d, "trial_events.csv"), row.names = FALSE)
})
check("G", "Finalization gates and exact original Decision-7 statuses/contiguous sequence", function() {
  first <- initial_events()
  test_expect_error(function() replay(join_events(first, event(3, 3, "FINALIZE"))), "closed enrollment")
  closed <- join_events(first, event(3, 3, "CLOSE_ENROLLMENT", reason = "authorized"))
  test_expect_error(function() replay(join_events(closed, event(4, 4, "FINALIZE"))), "all assigned outcomes")
  stopped <- join_events(closed, event(4, 4, "DISCONTINUE", patient_id = 1, reason = "fictional stop"))
  test_expect_error(function() replay(join_events(stopped, event(5, 5, "FINALIZE"))), "all assigned outcomes")
  observed <- join_events(closed, event(4, 4, "OUTCOME", patient_id = 1, cycle = 1, outcome = 0))
  test_expect_error(function() replay(join_events(observed, event(5, 5, "FINALIZE"))), "no active patients")
  complete <- join_events(stopped, event(5, 5, "OUTCOME", patient_id = 1, cycle = 1, outcome = 0),
                         event(6, 6, "FINALIZE"))
  r <- replay(complete)
  direct <- replay(complete[1:5, ])$state
  direct <- engine$attach_decision7(engine$finalize_trial_state(direct, csv_time(complete$available_at_utc[6])))
  stopifnot(identical(r$state, direct), length(r$state$decision7$recommended_sequence) == 1L,
    identical(r$state$decision7$cycle_specific$status, c("RECOMMENDED", rep("INSUFFICIENT_DIRECT_INFORMATION", 7))),
    identical(r$state$decision7$sequence$in_recommended_sequence, c(TRUE, rep(FALSE, 7))))
  # A fully recorded fictional history reaches original safety exclusions.
  # Follow-up continues after maximum enrollment; fixed DLT outcomes lead to
  # the original patient-specific dose reductions/discontinuations.
  toxic <- enrollment_fixture()
  # One patient has a fully recorded DLT-free C1-C3 path and then an external
  # stop, providing a later conditional estimate after early-cycle exclusion.
  toxic <- append_fixed(toxic, "OUTCOME", patient_id = 12, cycle = 1, outcome = 0)
  for (cycle in 2:3) {
    toxic <- append_fixed(toxic, "REQUEST_NEXT", patient_id = 12, clinically_eligible = "TRUE")
    recommendation <- tail(replay(toxic)$recommendations, 1)
    toxic <- append_fixed(toxic, "CONFIRM_DOSE", recommendation_id = recommendation$recommendation_id,
                          dose = recommendation$recommended_dose, clinically_eligible = "TRUE")
    toxic <- append_fixed(toxic, "OUTCOME", patient_id = 12, cycle = cycle, outcome = 0)
  }
  toxic <- append_fixed(toxic, "DISCONTINUE", patient_id = 12, reason = "fictional completed follow-up")
  for (id in 1:11) toxic <- append_fixed(toxic, "OUTCOME", patient_id = id, cycle = 1, outcome = 1)
  for (id in 1:11) {
    for (step in 1:3) {
      current <- replay(toxic)
      if (current$state$patients[[id]]$guided_status != "active") break
      toxic <- append_fixed(toxic, "REQUEST_NEXT", patient_id = id, clinically_eligible = "TRUE")
      recommendation <- tail(replay(toxic)$recommendations, 1)
      if (recommendation$status != "PENDING") break
      toxic <- append_fixed(toxic, "CONFIRM_DOSE", recommendation_id = recommendation$recommendation_id,
                            dose = recommendation$recommended_dose, clinically_eligible = "TRUE")
      toxic <- append_fixed(toxic, "OUTCOME", patient_id = id, cycle = recommendation$cycle, outcome = 1)
    }
  }
  before_final <- replay(toxic)$state
  toxic <- append_fixed(toxic, "FINALIZE")
  terminal <- replay(toxic)$state
  expected <- engine$attach_decision7(engine$finalize_trial_state(before_final, csv_time(tail(toxic$available_at_utc, 1))))
  stopifnot(identical(terminal, expected), any(terminal$decision7$cycle_specific$status == "NO_ADMISSIBLE_DOSE"),
            terminal$decision7$cycle_specific$status[3] == "RECOMMENDED",
            !any(terminal$decision7$sequence$in_recommended_sequence))
  d <- file.path(work, "finalized"); csv_init(d, root); append_process(d, complete)
  stopifnot(csv_status(d, root)$state$trial_complete,
            nrow(read.csv(file.path(d, "terminal_cycle_specific.csv"))) == 8L)
})
if (length(args)) {
  dir.create(args[1], recursive = TRUE, showWarnings = FALSE)
  write.csv(results, file.path(args[1], "targeted_tests.csv"), row.names = FALSE)
  writeLines(c(R.version.string, paste("Platform:", R.version$platform),
               "Deterministic constructed histories only; no simulations/JAGS or scientific suites."),
             file.path(args[1], "test_environment.txt"))
}
unlink(work, recursive = TRUE)
cat("7/7 targeted groups PASS\n")
