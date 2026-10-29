# Only the two supplied examples are executed, once each, in this clean session.
# Run from the candidate root: R --vanilla --slave -f tests/run_release_checks.R
package_root <- normalizePath(".")
source("R/load_twicebee.R")
twicebee <- twicebee_load(package_root)
mob <- twicebee$mob_load_engine(package_root)
checks <- list()
check <- function(name, passed, expected, observed) {
  checks[[length(checks) + 1L]] <<- data.frame(
    check = name, passed = isTRUE(passed), expected = expected, observed = observed
  )
  if (!isTRUE(passed)) stop(paste("Release-copy check failed:", name))
}
check("Clean load of both engines", is.environment(twicebee) && is.environment(mob),
      "TWICEBEE and MOB environments", "TWICEBEE and MOB environments")
illustration <- new.env(parent = globalenv())
sys.source("examples/twicebee_illustration.R", envir = illustration)
x <- illustration$illustration_result
check("Enrolled patients", identical(x$enrolled, 6L), "6", as.character(x$enrolled))
check("Evaluable patient-cycles", x$evaluable_patient_cycles == 43L,
      "43", as.character(x$evaluable_patient_cycles))
check("DLT-positive patient-cycles", x$dlt_positive_patient_cycles == 12L,
      "12", as.character(x$dlt_positive_patient_cycles))
check("C1-C8 terminal statuses", identical(x$terminal$cycle, 1:8) &&
        identical(x$terminal$status, rep("RECOMMENDED", 8L)),
      paste(rep("RECOMMENDED", 8L), collapse = ","), paste(x$terminal$status, collapse = ","))
expected_doses <- c(1L, 2L, 2L, 2L, 2L, 3L, 3L, 3L)
check("C1-C8 terminal doses", identical(x$terminal$dose, expected_doses),
      paste(expected_doses, collapse = ","), paste(x$terminal$dose, collapse = ","))
check("Supported contiguous sequence", identical(x$sequence, expected_doses),
      paste(expected_doses, collapse = ","), paste(x$sequence, collapse = ","))
fixture <- new.env(parent = globalenv())
sys.source("examples/mob_working_update.R", envir = fixture)
# Analytical Test-2 expectations, expressed with prior/count arithmetic for
# bit-exact comparisons of floating shapes and subtraction-derived increments.
# Decimal .9/.8 expectations retain the historical fixture's 1e-12 convention.
expected_direct_alpha <- fixture$a0 + fixture$delta_y
expected_direct_beta <- fixture$b0 + fixture$delta_m
expected_alpha <- matrix(rep(.2 + 1L, 3L), ncol = 1L)
expected_beta <- fixture$b0
expected_hplus <- expected_alpha - expected_direct_alpha
expected_hminus <- expected_beta - expected_direct_beta
expected_update <- list(tilde_alpha = expected_direct_alpha,
                        tilde_beta = expected_direct_beta,
                        alpha = expected_alpha, beta = expected_beta,
                        Delta_Hplus = expected_hplus, Delta_Hminus = expected_hminus)
expected_state <- list(
  a0 = fixture$a0, b0 = fixture$b0, alpha = expected_alpha, beta = expected_beta,
  cumulative_direct_DLT = fixture$delta_y,
  cumulative_direct_nonDLT = fixture$delta_m,
  cumulative_borrowed_DLT = expected_hplus,
  cumulative_borrowed_nonDLT = expected_hminus
)
check("MOB fixture exact shapes, update and ledgers",
      identical(fixture$mob_result, list(state = expected_state, update = expected_update)),
      "direct alpha 1.2,0.3,0.4; H+ 0,0.9,0.8; alpha 1.2,1.2,1.2; beta 0.8,0.7,0.6; H- 0,0,0",
      paste("direct alpha", paste(fixture$mob_result$update$tilde_alpha, collapse = ","),
            "; H+", paste(fixture$mob_result$update$Delta_Hplus, collapse = ","),
            "; alpha", paste(fixture$mob_result$state$alpha, collapse = ","),
            "; beta", paste(fixture$mob_result$state$beta, collapse = ","),
            "; H-", paste(fixture$mob_result$update$Delta_Hminus, collapse = ",")))
check("MOB historical decimal expectations",
      isTRUE(all.equal(fixture$mob_result$update$Delta_Hplus,
                       matrix(c(0, .9, .8), ncol = 1L), tolerance = 1e-12, scale = 1)),
      "0,0.9,0.8 within absolute-scale 1e-12", "0,0.9,0.8 within absolute-scale 1e-12")
output_paths <- c(illustration$example_output, fixture$example_output)
check("Example output containment", all(startsWith(normalizePath(output_paths),
      paste0(package_root, "/examples/output/"))),
      "Both output directories inside examples/output", "Both output directories inside examples/output")
check_output <- file.path(package_root, "tests/output")
dir.create(check_output, recursive = TRUE, showWarnings = FALSE)
write.csv(do.call(rbind, checks), file.path(check_output, "release_checks.csv"), row.names = FALSE)
writeLines(c(R.version.string, R.version$platform, capture.output(sessionInfo())),
           file.path(check_output, "environment.txt"))
cat("PASS: two examples executed once each; all release-copy comparisons passed.\n")
