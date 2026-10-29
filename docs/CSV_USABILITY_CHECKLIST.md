# CSV User Interface v0.1 usability checklist

Use a fresh source extraction on macOS with a new local fictional-trial directory. Follow [the Quick Start](CSV_QUICK_START.md); do not use real patient identifiers or change scientific sources. This interface supports primary TWICEBEE, not TWICEBEE-MOB.

Record the R version, operating system and date when using this checklist.

| Check | Expected behavior |
|---|---|
| Setup | `init` and `status` succeed; input and outputs appear |
| First preview | F001 gets R000001 / C1 DL1 / PENDING without enrollment |
| First administration | Confirmation changes R000001 to CONFIRMED and allocates patient_id 1 |
| Second patient | F002 preview/confirmation allocates patient_id 2 at C1 DL1 |
| Outcomes before request | Submit guide rows 5–7 together; patient 1's outcome precedes patient 2's outcome, then the next request |
| Next preview | F001 gets R000003 / C2 DL2 / PENDING; F002's DL1 DLT statistically discontinues guidance |
| Confirmation | F001 C2 DL2 is CONFIRMED |
| Restart | Reopen and inspect status, recommendations, patient status and decision history |
| Complete example | In a separate new directory: three evaluable cycles, one DLT, supported prefix [1,3] |

If a check fails, preserve the complete fictional trial directory and report the command, full error, relevant fictional event IDs/times, R version and `sessionInfo()`. Do not edit accepted event history or scientific code to make a check pass. Do not share actual patient data.

This checklist assesses research-software usability, not clinical eligibility, parameter suitability, operating characteristics or regulatory validation.
