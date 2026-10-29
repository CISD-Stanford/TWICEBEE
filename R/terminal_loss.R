# Required current functions extracted unchanged; see docs/SOURCE_MAPPING.md.

eu_symmetric_loss <- function(theta, alpha, beta) {
  mu <- alpha / (alpha + beta)
  f0 <- pbeta(theta, alpha, beta)
  f1 <- pbeta(theta, alpha + 1, beta)
  mu - theta + 2 * (theta * f0 - mu * f1)
}

