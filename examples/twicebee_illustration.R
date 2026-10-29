# Run from the candidate root: Rscript --vanilla examples/twicebee_illustration.R
# Fixed illustration only; scientific functions and scheduling are copied unchanged.
package_root <- normalizePath(".")
source(file.path(package_root, "R/load_twicebee.R"), local = TRUE)
engine <- twicebee_load(package_root)
config <- engine$twicebee_config(12L)
config$J <- 3L; config$C <- 8L; config$cohort_size <- 1L
config$prior_means <- matrix(rep(c(.2, .3, .4), 8), 3, 8)
config$initial_alpha <- config$prior_ess * config$prior_means
config$initial_beta <- config$prior_ess * (1 - config$prior_means)
surface <- rbind(c(.30, .25, .20, .15, .10, .08, .06, .05),
                 c(.40, .35, .30, .25, .20, .18, .16, .15),
                 c(.50, .45, .40, .35, .30, .28, .26, .25))
RNGkind("Mersenne-Twister", "Inversion", "Rejection")
illustration_state <- engine$run_stochastic_trial(
  surface, 314159L, config, 1L, "twicebee-illustration"
)
illustration_state <- engine$attach_decision7(illustration_state)
illustration_result <- list(
  enrolled = length(illustration_state$patients),
  evaluable_patient_cycles = sum(illustration_state$outcome_availability),
  dlt_positive_patient_cycles = sum(illustration_state$outcome_history, na.rm = TRUE),
  terminal = illustration_state$decision7$cycle_specific,
  sequence = illustration_state$decision7$recommended_sequence
)
example_output <- file.path(package_root, "examples/output/twicebee")
dir.create(example_output, recursive = TRUE, showWarnings = FALSE)
write.csv(data.frame(
  enrolled = illustration_result$enrolled,
  evaluable_patient_cycles = illustration_result$evaluable_patient_cycles,
  dlt_positive_patient_cycles = illustration_result$dlt_positive_patient_cycles
), file.path(example_output, "summary.csv"), row.names = FALSE)
write.csv(illustration_result$terminal, file.path(example_output, "terminal.csv"),
          row.names = FALSE)
write.csv(data.frame(cycle = seq_along(illustration_result$sequence),
                     dose = illustration_result$sequence),
          file.path(example_output, "supported_sequence.csv"), row.names = FALSE)
print(illustration_result)
