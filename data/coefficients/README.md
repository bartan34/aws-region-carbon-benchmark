# Coefficients

Every external number used by `analysis/sci.py` lives here with its source,
year and access date:

- `power.csv`: m5.large power at Idle/10/50/100% load (Teads), plus the
  Cloud Carbon Footprint coefficients used in the sensitivity analysis.
- `pue.csv`: AWS regional PUE.
- `grid-intensity.csv`: annual location-based grid intensity per region,
  with an alternative source used in the sensitivity analysis.
- `em-hourly.csv`: Electricity Maps readings taken at run time (one row
  per region per reading); the screenshots are kept outside the repository.
- `boavizta-<type>-<ISO3>.json`: embodied emissions, produced by
  `scripts/boavizta.sh`.
- `pricing.csv`: on-demand USD per hour, produced by `scripts/pricing.sh`.
- `regions.csv`: the regions in the analysis and why each was chosen.

If a per-instance `data/raw/<region>/<iid>/em-history.json` exists (from the
Electricity Maps API), `sci.py` uses it for the hourly view instead of
`em-hourly.csv`.
