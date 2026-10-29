# Source organization

This public overview explains the module relationships referenced by comments in the unchanged R files. Detailed preparation provenance and internal audit records are outside the source distribution.

| Files | Role |
|---|---|
| `R/configuration.R` | Retained research configuration and the `twicebee_config()` naming wrapper |
| `R/terminal_loss.R` | Retained symmetric expected-absolute-loss function |
| `R/working_model.R`, `safety_admissibility.R`, `sequential_decisions.R`, `trial_engine.R`, `decision7_terminal.R` | Primary working-state updates, safety, conduct and final recommendation processing |
| `R/illustration_scheduler.R` | Retained scheduling and outcome generation used by the fixed simulated example |
| `R/load_twicebee.R` | Local loader into an isolated primary-engine environment |
| `R/mob_working_state.R`, `mob_trial_engine.R`, `mob_scheduler.R`, `mob_engine_loader.R` | MOB working state, integrated conduct, explicit schedules and isolated loader |
| `interface/load_engine.R`, `csv_interface.R`, `twicebee_cli.R` | Primary-only CSV engine loader, event adapter and command-line entry point |

The CSV loader uses the same seven core files as the research implementation: configuration, terminal loss, working model, safety, sequential decisions, trial engine and terminal processing. No duplicate scientific core is needed. The MOB loader selects retained helper definitions and loads the MOB modules into a separate environment.

All R files in this combined release preserve their established source bytes. Combining the components changes documentation and distribution layout, not statistical rules or interface functions. See [API.md](API.md), [component versions](COMPONENT_VERSIONS.md) and [validation scope](VALIDATION_HISTORY.md).
