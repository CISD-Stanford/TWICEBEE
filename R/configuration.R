# Required current functions extracted unchanged; see docs/SOURCE_MAPPING.md.

package_a_config <- function(max_enrollment = 12L) {
  J <- 4L
  C <- 8L
  prior_means <- matrix(rep(c(0.10, 0.20, 0.30, 0.40), C),
                        nrow = J, ncol = C)
  list(
    J = J, C = C, theta0 = 0.30, starting_dose = 1L,
    n0 = 6L, max_enrollment = as.integer(max_enrollment), cohort_size = 3L,
    prior_means = prior_means, prior_ess = 4,
    initial_alpha = 4 * prior_means,
    initial_beta = 4 * (1 - prior_means),
    under_penalty = 1, over_penalty = 1,
    delta0 = 0.05, r1 = 0.50, r2 = 0.95, r_OD = 0.95,
    minimum_enrollment = 6L,
    enrollment_interval = 11, cycle_duration = 10
  )
}


# Publication-facing name only; the retained configuration is unchanged.
twicebee_config <- function(max_enrollment = 12L) package_a_config(max_enrollment)
