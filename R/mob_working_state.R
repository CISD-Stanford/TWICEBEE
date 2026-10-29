# Isolated TWICEBEE-MOB-dev v0.1 working state; rows are doses, columns cycles.

mob_strict_c_relation <- function(j, c, j2, c2) {
  if (j == j2 && c == c2) return("same")
  if (j <= j2 && c >= c2) return("less")
  if (j >= j2 && c <= c2) return("more")
  "incomparable"
}

mob_working_update <- function(alpha, beta, delta_y, delta_m) {
  # One call represents the complete batch available before one decision.
  if (all(delta_y == 0) && all(delta_m == 0)) {
    return(list(
      tilde_alpha = alpha, tilde_beta = beta, alpha = alpha, beta = beta,
      Delta_Hplus = alpha * 0, Delta_Hminus = beta * 0
    ))
  }

  tilde_alpha <- alpha + delta_y
  tilde_beta <- beta + delta_m
  J <- nrow(alpha)
  C <- ncol(alpha)
  alpha_new <- tilde_alpha
  beta_new <- tilde_beta

  for (j in seq_len(J)) {
    for (c in seq_len(C)) {
      # The rectangles include equality and every comparable predecessor or
      # successor. All maxima read the completed direct batch, not loop output.
      alpha_new[j, c] <- max(tilde_alpha[seq_len(j), c:C, drop = FALSE])
      beta_new[j, c] <- max(tilde_beta[j:J, seq_len(c), drop = FALSE])
    }
  }

  list(
    tilde_alpha = tilde_alpha, tilde_beta = tilde_beta,
    alpha = alpha_new, beta = beta_new,
    Delta_Hplus = alpha_new - tilde_alpha,
    Delta_Hminus = beta_new - tilde_beta
  )
}

mob_new_state <- function(a0, b0) {
  zero <- matrix(0L, nrow(a0), ncol(a0), dimnames = dimnames(a0))
  list(
    a0 = a0, b0 = b0, alpha = a0, beta = b0,
    cumulative_direct_DLT = zero,
    cumulative_direct_nonDLT = zero,
    cumulative_borrowed_DLT = zero,
    cumulative_borrowed_nonDLT = zero
  )
}

mob_original_state <- function() {
  # The original revised-TWICEBEE prior in package_a_config(): four doses,
  # eight cycles, means (0.10, 0.20, 0.30, 0.40) and prior ESS 4 at each cell.
  prior_means <- matrix(rep(c(0.10, 0.20, 0.30, 0.40), 8L), nrow = 4L)
  mob_new_state(4 * prior_means, 4 * (1 - prior_means))
}

mob_update_state <- function(state, delta_y, delta_m) {
  update <- mob_working_update(state$alpha, state$beta, delta_y, delta_m)
  if (all(delta_y == 0) && all(delta_m == 0)) {
    return(list(state = state, update = update))
  }

  state$alpha <- update$alpha
  state$beta <- update$beta
  state$cumulative_direct_DLT <- state$cumulative_direct_DLT + delta_y
  state$cumulative_direct_nonDLT <- state$cumulative_direct_nonDLT + delta_m
  state$cumulative_borrowed_DLT <-
    state$cumulative_borrowed_DLT + update$Delta_Hplus
  state$cumulative_borrowed_nonDLT <-
    state$cumulative_borrowed_nonDLT + update$Delta_Hminus
  list(state = state, update = update)
}

mob_stage2_handoff <- function(state) {
  # The caller first applies any newly evaluable transition batch once with
  # mob_update_state(). This representation carries that completed state as is.
  list(stage = 2L, working_state = state)
}
