# Run from the candidate root: Rscript --vanilla examples/mob_working_update.R
# Existing validated fractional pseudo-DLT fixture; no random data are generated.
package_root <- normalizePath(".")
source(file.path(package_root, "R/mob_engine_loader.R"), local = TRUE)
mob <- mob_load_engine(package_root)
a0 <- matrix(c(.2, .3, .4), ncol = 1L)
b0 <- matrix(c(.8, .7, .6), ncol = 1L)
initial_state <- mob$mob_new_state(a0, b0)
delta_y <- delta_m <- matrix(0L, 3L, 1L)
delta_y[1L, 1L] <- 1L
mob_result <- mob$mob_update_state(initial_state, delta_y, delta_m)
mob_table <- data.frame(
  dose = 1:3, cycle = 1L,
  prior_alpha = a0[, 1L], prior_beta = b0[, 1L],
  direct_dlt = delta_y[, 1L], direct_nondlt = delta_m[, 1L],
  direct_alpha = mob_result$update$tilde_alpha[, 1L],
  direct_beta = mob_result$update$tilde_beta[, 1L],
  borrowed_dlt = mob_result$update$Delta_Hplus[, 1L],
  borrowed_nondlt = mob_result$update$Delta_Hminus[, 1L],
  ordered_alpha = mob_result$state$alpha[, 1L],
  ordered_beta = mob_result$state$beta[, 1L]
)
example_output <- file.path(package_root, "examples/output/mob")
dir.create(example_output, recursive = TRUE, showWarnings = FALSE)
write.csv(mob_table, file.path(example_output, "working_update.csv"), row.names = FALSE)
print(mob_table)
