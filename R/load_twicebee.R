# Packaging-only loader. No statistical logic is implemented here.
twicebee_load <- function(directory = ".") {
  directory <- normalizePath(directory)
  engine <- new.env(parent = baseenv())
  engine$pbeta <- stats::pbeta
  engine$rbinom <- stats::rbinom
  engine$setNames <- stats::setNames
  engine$tail <- utils::tail
  for (file in c("configuration.R", "terminal_loss.R", "working_model.R",
                 "safety_admissibility.R", "sequential_decisions.R", "trial_engine.R",
                 "decision7_terminal.R", "illustration_scheduler.R", "mob_engine_loader.R")) {
    sys.source(file.path(directory, "R", file), envir = engine)
  }
  lockEnvironment(engine, bindings = TRUE)
  engine
}
