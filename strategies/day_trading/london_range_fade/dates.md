# london_range_fade — date ranges

- **In-sample (optimization):** 2018.01.01 – 2022.12.31
- **Out-of-sample (validation):** 2023.01.01 – 2025.12.31

Same split as `london_orb` (now in `_graveyard/`), for comparability.
All parameter sweeps and logic iteration happen only against the in-sample
range. Out-of-sample is used once, unmodified, as a final check.
