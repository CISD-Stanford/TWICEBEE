# Population safety, strict-C closure, and retained enrollment stopping.

strict_c_upper_closure <- function(excluded, anchor_dose, anchor_cycle) {
  excluded[anchor_dose:nrow(excluded), seq_len(anchor_cycle)] <- TRUE
  excluded
}

refresh_overdose_exclusions <- function(alpha, beta, excluded, config) {
  q <- 1 - pbeta(config$theta0 + config$delta0, alpha, beta)
  anchors <- which(q > config$r_OD & !excluded, arr.ind = TRUE)
  updated <- excluded
  if (nrow(anchors)) {
    for (i in seq_len(nrow(anchors))) {
      updated <- strict_c_upper_closure(updated, anchors[i, 1], anchors[i, 2])
    }
  }
  list(
    excluded = updated,
    overdose_probability = q,
    new_cells = which(updated & !excluded, arr.ind = TRUE),
    triggering_anchors = anchors
  )
}

population_admissible_doses <- function(excluded, cycle) {
  which(!excluded[, cycle])
}

evaluate_retained_stopping <- function(alpha, beta, n_enrolled, config) {
  utilities <- utility_by_dose(alpha, beta, 1L, config)
  interim_mtd <- which.max(utilities)
  mtd_plus <- min(config$J, interim_mtd + 1L)
  threshold <- config$theta0 + config$delta0
  p_all_toxic <- 1 - pbeta(threshold, alpha[1, 1], beta[1, 1])
  p_mtd_plus_toxic <- 1 - pbeta(
    threshold, alpha[mtd_plus, 1], beta[mtd_plus, 1]
  )
  eligible <- n_enrolled >= config$minimum_enrollment
  rule_all_toxic <- eligible && p_all_toxic > config$r1
  rule_mtd_plus <- eligible && p_mtd_plus_toxic > config$r2
  list(
    eligible = eligible,
    interim_cycle1_mtd = interim_mtd,
    mtd_plus = mtd_plus,
    p_all_toxic = p_all_toxic,
    p_mtd_plus_toxic = p_mtd_plus_toxic,
    rule_all_toxic = rule_all_toxic,
    rule_mtd_plus = rule_mtd_plus,
    stop = rule_all_toxic || rule_mtd_plus
  )
}
