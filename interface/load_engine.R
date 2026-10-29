# Interface-only loader: local, byte-identical primary TWICEBEE definitions.
csv_load_engine <- function(root) {
  engine <- new.env(parent = baseenv())
  engine$pbeta <- stats::pbeta
  engine$setNames <- stats::setNames
  engine$tail <- utils::tail
  for (name in c("configuration.R", "terminal_loss.R", "working_model.R",
                 "safety_admissibility.R", "sequential_decisions.R",
                 "trial_engine.R", "decision7_terminal.R")) {
    sys.source(file.path(root, "R", name), envir = engine)
  }
  lockEnvironment(engine, bindings = TRUE)
  engine
}
