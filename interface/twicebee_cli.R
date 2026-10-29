#!/usr/bin/env Rscript
args <- commandArgs(trailingOnly = TRUE)
script <- sub("^--file=", "", commandArgs()[grepl("^--file=", commandArgs())])
root <- dirname(dirname(normalizePath(script)))
source(file.path(root, "interface", "load_engine.R"))
source(file.path(root, "interface", "csv_interface.R"))
tryCatch({
  if (length(args) != 2L || !args[1L] %in% c("init", "process", "status")) {
    stop("Usage: Rscript --vanilla interface/twicebee_cli.R {init|process|status} /path/to/trial")
  }
  csv_cli(args[1L], args[2L], root)
}, error = function(e) {
  cat("TWICEBEE CSV error: ", conditionMessage(e), "\n", sep = "", file = stderr())
  quit(status = 1L)
})
