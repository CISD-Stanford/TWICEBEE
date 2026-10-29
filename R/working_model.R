# Working-information updates for the revised TWICEBEE conduct engine.

strict_c_relation <- function(j, c, j2, c2) {
  if (j == j2 && c == c2) return("same")
  if (j <= j2 && c >= c2) return("less")
  if (j >= j2 && c <= c2) return("more")
  "incomparable"
}

apply_working_increment <- function(alpha, beta, dose, cycle, outcome) {
  J <- nrow(alpha)
  C <- ncol(alpha)
  a <- alpha
  b <- beta

  for (j in seq_len(J)) {
    for (c in seq_len(C)) {
      if (j == dose && c == cycle) {
        a[j, c] <- a[j, c] + outcome
        b[j, c] <- b[j, c] + 1 - outcome
      } else if (outcome == 1L &&
                 strict_c_relation(dose, cycle, j, c) == "less") {
        # A DLT propagates only toward cells strictly more toxic than treated.
        a[j, c] <- a[j, c] + 1
      } else if (outcome == 0L &&
                 strict_c_relation(dose, cycle, j, c) == "more") {
        # A non-DLT propagates only toward cells strictly less toxic than treated.
        b[j, c] <- b[j, c] + 1
      }
    }
  }
  list(alpha = a, beta = b)
}

calibrate_working_state <- function(alpha, beta) {
  ess <- alpha + beta
  average_ess <- mean(ess)
  ratio <- ess / average_ess
  list(
    alpha = alpha / ratio,
    beta = beta / ratio,
    average_ess = average_ess,
    pre_calibration_ess = ess
  )
}

recursive_working_update <- function(alpha, beta, dose, cycle, outcome) {
  intermediate <- apply_working_increment(alpha, beta, dose, cycle, outcome)
  calibrated <- calibrate_working_state(intermediate$alpha, intermediate$beta)
  c(calibrated, list(
    intermediate_alpha = intermediate$alpha,
    intermediate_beta = intermediate$beta
  ))
}

expected_osla_utility <- function(target, alpha, beta,
                                  under_penalty = 1, over_penalty = 1) {
  mu <- alpha / (alpha + beta)
  lower_loss_component <- target * pbeta(target, alpha, beta) -
    mu * pbeta(target, alpha + 1, beta)
  -(under_penalty + over_penalty) * lower_loss_component -
    over_penalty * (mu - target)
}

utility_by_dose <- function(alpha, beta, cycle, config) {
  expected_osla_utility(
    config$theta0,
    alpha[, cycle],
    beta[, cycle],
    config$under_penalty,
    config$over_penalty
  )
}

select_by_utility <- function(alpha, beta, cycle, candidates, config) {
  candidates <- sort(unique(as.integer(candidates)))
  if (!length(candidates)) return(NA_integer_)
  utilities <- utility_by_dose(alpha, beta, cycle, config)
  # which.max returns the first maximum; sorted candidates implement the
  # source-supported lower-dose convention for exact sequential ties.
  candidates[which.max(utilities[candidates])]
}

strict_c_order_check <- function(mu, tolerance = 1e-10) {
  J <- nrow(mu)
  C <- ncol(mu)
  rows <- list()
  k <- 0L
  maximum <- 0
  for (j in seq_len(J)) {
    for (c in seq_len(C)) {
      for (j2 in seq_len(J)) {
        for (c2 in seq_len(C)) {
          if (strict_c_relation(j, c, j2, c2) == "less") {
            discrepancy <- mu[j, c] - mu[j2, c2]
            maximum <- max(maximum, discrepancy)
            if (discrepancy > tolerance) {
              k <- k + 1L
              rows[[k]] <- data.frame(
                less_dose = j, less_cycle = c,
                more_dose = j2, more_cycle = c2,
                less_mean = mu[j, c], more_mean = mu[j2, c2],
                discrepancy = discrepancy
              )
            }
          }
        }
      }
    }
  }
  list(
    violation = length(rows) > 0L,
    maximum_positive_discrepancy = maximum,
    offending_pairs = if (length(rows)) do.call(rbind, rows) else data.frame()
  )
}
