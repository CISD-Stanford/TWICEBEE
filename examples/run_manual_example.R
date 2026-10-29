# Constructed fictional outcomes; no RNG, DLT draws, or clinical evidence.
# Each CLI invocation starts a fresh R process to exercise save/resume.
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1L) stop("Usage: Rscript --vanilla examples/run_manual_example.R /path/to/new-example-trial")
script <- sub("^--file=", "", commandArgs()[grepl("^--file=", commandArgs())])
root <- dirname(dirname(normalizePath(script)))
trial <- args[1L]
cli <- file.path(root, "interface", "twicebee_cli.R")
rscript <- file.path(R.home("bin"), "Rscript")
run <- function(action) {
  status <- system2(rscript, c("--vanilla", shQuote(cli), action, shQuote(trial)))
  if (status != 0L) stop("Example CLI ", action, " failed")
}
events <- read.csv(file.path(root, "examples", "fictional_events.csv"),
                   colClasses = "character", na.strings = NULL, check.names = FALSE)
run("init")
for (last in c(1L, 2L, 3L, 4L, 7L, 8L, 9L, 10L, 11L, 12L, 13L, 14L)) {
  cat("\nAppend through event", last, "\n")
  write.csv(events[seq_len(last), ], file.path(trial, "trial_events.csv"), row.names = FALSE)
  run("process")
  if (last %in% c(1L, 7L, 9L)) run("status")
}
run("status")
rec <- read.csv(file.path(trial, "recommendations.csv"))
patients <- read.csv(file.path(trial, "patient_status.csv"))
print(rec[, c("recommendation_id", "subject_code", "cycle", "recommended_dose", "confirmed_dose", "status")], row.names = FALSE)
print(patients, row.names = FALSE)
saved <- readRDS(file.path(trial, "trial_state.rds"))$record
stopifnot(identical(as.integer(rec$recommended_dose), c(1L, 1L, 2L)),
          all(rec$status == "CONFIRMED"), saved$state$trial_complete,
          sum(saved$state$direct_dlt) == 1L, sum(saved$state$direct_nondlt) == 2L)
before <- unname(tools::md5sum(file.path(trial, c("trial_state.rds", "recommendations.csv", "patient_status.csv"))))
run("process")
after <- unname(tools::md5sum(file.path(trial, c("trial_state.rds", "recommendations.csv", "patient_status.csv"))))
stopifnot(identical(before, after))
cat("MANUAL EXAMPLE PASS: fresh-session resume and idempotence verified.\n")
