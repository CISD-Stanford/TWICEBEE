# Deterministic fictional event fixtures, never DLT draws.
event <- function(id, hour, type, ...) {
  row <- setNames(rep("", length(csv_columns)), csv_columns)
  row[c("event_id", "available_at_utc", "event_type")] <- c(
    as.character(id), format(as.POSIXct("2026-10-12T00:00:00", tz = "UTC") + hour * 3600,
                            "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), type)
  fields <- list(...)
  for (name in names(fields)) row[name] <- as.character(fields[[name]])
  as.data.frame(as.list(row), stringsAsFactors = FALSE)
}
join_events <- function(...) {
  result <- do.call(rbind, list(...))
  rownames(result) <- NULL
  result
}
initial_events <- function() join_events(
  event(1, 1, "REQUEST_NEW", subject_code = "F001", clinically_eligible = "TRUE"),
  event(2, 2, "CONFIRM_DOSE", recommendation_id = "R000001", dose = 1, clinically_eligible = "TRUE"))
test_expect_error <- function(action, pattern) {
  message <- tryCatch({ action(); "" }, error = function(e) conditionMessage(e))
  if (!nzchar(message) || !grepl(pattern, message, fixed = TRUE)) {
    stop("Expected error containing '", pattern, "'; got '", message, "'")
  }
  invisible(message)
}
