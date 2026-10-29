# Load a separate MOB engine; never overwrite functions in the caller's session.
mob_load_engine <- function(repository = ".") {
  repository <- normalizePath(repository)
  retained <- new.env(parent = baseenv())
  retained$pbeta <- stats::pbeta
  retained$tail <- utils::tail
  # Evaluate the original definitions unchanged. No calibrated updater or
  # stochastic driver is imported into the MOB dependency environment.
  imports <- list(
    "working_model.R" = c("expected_osla_utility", "utility_by_dose", "select_by_utility"),
    "safety_admissibility.R" = c("strict_c_upper_closure", "refresh_overdose_exclusions",
      "population_admissible_doses", "evaluate_retained_stopping"),
    "sequential_decisions.R" = c("qualifying_previous_destination", "ordinary_ongoing_decision",
      "post_dlt_decision", "decide_ongoing_patient", "decide_new_patient"),
    "trial_engine.R" = c("new_trial_state", "close_enrollment", "refresh_stage2_safety",
      "make_patient", "append_decision_log", "assign_stage1", "finalize_trial_state"),
    "configuration.R" = "package_a_config",
    "terminal_loss.R" = "eu_symmetric_loss",
    "decision7_terminal.R" = c("decision7_terminal_result", "attach_decision7")
  )
  for (file in names(imports)) {
    definitions <- as.list(parse(file.path(repository, "R", file)))
    for (name in imports[[file]]) {
      definition <- Filter(function(x) is.call(x) && identical(x[[1]], as.name("<-")) &&
        identical(x[[2]], as.name(name)), definitions)
      stopifnot(length(definition) == 1L)
      eval(definition[[1]], retained)
    }
  }
  lockEnvironment(retained, bindings = TRUE)
  engine <- new.env(parent = retained)
  development <- repository
  for (file in c("mob_working_state.R", "mob_trial_engine.R", "mob_scheduler.R")) {
    sys.source(file.path(development, "R", file), envir = engine)
  }
  lockEnvironment(engine, bindings = TRUE)
  engine
}
