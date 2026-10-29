# TWICEBEE Research Code

Release **1.0.0** provides standalone R source for **TWICEBEE: A Two-stage Intra-patient Curve-free Bayesian Decision-Theoretic Dose Escalation Design**. The software supports research on dose decisions across successive treatment cycles, using observed binary dose-limiting toxicity (DLT) outcomes and cycle-specific final toxicity-based recommendations.

This distribution includes three components:

| Component | Version | Purpose |
|---|---|---|
| Primary revised TWICEBEE research code | 1.0.0 | Strict dose-cycle ordering, recursive effective-sample-size calibration, conduct/safety rules and final recommendation processing |
| TWICEBEE-MOB | 0.1 | An alternative evaluated working-information construction using complete direct-observation batches and minimum additive shape closure, without ESS calibration |
| CSV User Interface | 0.1 | An observed-event workflow for **primary TWICEBEE only**; it is not a TWICEBEE-MOB interface |

MOB retains the TWICEBEE conduct, safety and terminal rule forms. Its inclusion does not imply uniform superiority. The repository release version and component versions are distinct; see [component versions](docs/COMPONENT_VERSIONS.md).

This is research software. It is not a clinically validated decision-support system, and no regulatory qualification is claimed. Clinical eligibility, recovery, dose administration and protocol suitability require clinical and scientific judgment. Toxicity-based recommendations alone do not determine a recommended phase 2 dose (RP2D) schedule.

## Obtain the source and requirements

Extract the supplied `TWICEBEE-v1.0.0.zip`; its root directory is `TWICEBEE/`. A source checkout, when supplied by the authors, uses the same layout. The intended public repository is `CISD-Stanford/TWICEBEE`; this document does not establish that the repository or a public release is already available.

Use R with its standard `base`, `stats`, `utils` and `tools` functionality. No contributed R packages, JAGS, database or external source tree is required. This is **not an installable R package**: use `source()` for the research engines and `Rscript` for the CSV workflow.

The previously verified environment is **R 4.4.1 on macOS 26.6, Apple arm64 (`aarch64-apple-darwin20`)**. A broader R-version or operating-system compatibility range is not established. Keep the extracted source-directory path and the R temporary-directory path free of spaces on the verified R 4.4.1 environment: its script-path handling does not support a space-containing source path. Quoted trial-directory paths containing spaces are supported. CSV v0.1 requires a local POSIX filesystem with symbolic links and atomic rename; Windows, network drives and cloud-synchronized trial directories are outside its verification scope.

## Load the research engines

Start a clean R session with `TWICEBEE/` as the working directory:

```r
source("R/load_twicebee.R")
twicebee <- twicebee_load(".")
config <- twicebee$twicebee_config()
mob <- twicebee$mob_load_engine(".")
```

Functions reside in separate engine environments. The retained default configuration has four doses, eight cycles, target DLT probability 0.30, prior ESS 4 and maximum enrollment 12. These are research defaults, not a recommended clinical protocol. See [the state and conduct API](docs/API.md) for the observed-state workflow and MOB's explicit schedule interface.

TWICEBEE assumes clinically defensible increasing toxicity with dose and nonincreasing working toxicity across cycles. Working Beta quantities are population-level working summaries rather than patient-specific conditional toxicity probabilities. The code does not establish the suitability of these assumptions for a particular setting.

## Run illustrative examples

From `TWICEBEE/` in Terminal:

```sh
Rscript --vanilla examples/twicebee_illustration.R
Rscript --vanilla examples/mob_working_update.R
```

The first command runs the existing fixed seed-314159 simulated illustration once: six enrolled patients, 43 evaluable patient-cycles, 12 DLT-positive patient-cycles and terminal doses `1,2,2,2,2,3,3,3`, all with status `RECOMMENDED`. The second performs a deterministic fractional-borrowing MOB update. Both write small CSVs under `examples/output/`; they overwrite only their example outputs. These examples do not estimate comparative operating characteristics. See [expected outputs](docs/EXAMPLE_OUTPUTS.md).

## Use the CSV interface

The CSV workflow supports **primary revised TWICEBEE, not TWICEBEE-MOB**. From `TWICEBEE/`, using a new or empty local trial directory:

```sh
Rscript --vanilla interface/twicebee_cli.R init /path/to/new-trial
Rscript --vanilla interface/twicebee_cli.R process /path/to/new-trial
Rscript --vanilla interface/twicebee_cli.R status /path/to/new-trial
```

Initialization creates `trial_events.csv`. Append observed events using its exact header and inspect previews before confirming administration. Use dose-level indices, not physical dose amounts. For a complete example with explicitly fictional outcomes:

```sh
Rscript --vanilla examples/run_manual_example.R /path/to/new-fictional-trial
```

The trial directory must be new or empty; quote paths containing spaces. The example launches fresh R processes and checks reopening and idempotence. Read the [CSV reference](README_CSV_INTERFACE.md) and [manual Quick Start](docs/CSV_QUICK_START.md) before using this workflow.

## Run the included bounded checks

From `TWICEBEE/`:

```sh
R --vanilla --slave -f tests/run_release_checks.R
Rscript --vanilla tests/run_targeted_tests.R /path/to/new-csv-check-results
```

The first command loads both research engines and runs both research examples once, checking ten established comparisons. It writes compact check records to `tests/output/` and refreshes the research example CSVs. The second runs seven deterministic CSV operational test groups with constructed fictional histories; its result files go to the supplied directory. It needs no contributed packages.

These bounded checks do not rerun the scientific validation suites or production simulation studies. Their scope and limitations are described in [validation history](docs/VALIDATION_HISTORY.md).

## Documentation and citation

- [State and conduct API](docs/API.md)
- [CSV fields, events, outputs, recovery and limitations](README_CSV_INTERFACE.md)
- [CSV manual Quick Start](docs/CSV_QUICK_START.md)
- [CSV usability checklist](docs/CSV_USABILITY_CHECKLIST.md)
- [Example expectations](docs/EXAMPLE_OUTPUTS.md)
- [Component versions](docs/COMPONENT_VERSIONS.md)
- [Validation scope](docs/VALIDATION_HISTORY.md)

Software authors are **Dehua Bi and Ying Lu**, in that order. Cite **Bi, Dehua; Lu, Ying. TWICEBEE Research Code, version 1.0.0 (software)**. Machine-readable metadata is in [CITATION.cff](CITATION.cff), and [AUTHORS.md](AUTHORS.md) records software authorship. No DOI or published-manuscript status is asserted.

## License

Distributed under the [MIT License](LICENSE).

Copyright (c) 2026 Dehua Bi, Jiapeng Xu, and Ying Lu.
