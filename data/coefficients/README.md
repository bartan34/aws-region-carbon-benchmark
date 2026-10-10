# Coefficients

Every external number used by `analysis/sci.py` lives here with its source,
year and access date. Rows marked `TODO` must be filled before analysis:

- `power.csv` — read m5.large Instance@Idle/10/50/100 from the Teads sheet.
- `grid-intensity.csv` — Ireland annual value; Electricity Maps tier for Oregon and Mumbai.
- `pue.csv` — confirm the latest regional year on the Amazon page.
- `boavizta-<type>-<ISO3>.json` — produced by `scripts/boavizta.sh`.

Hourly grid values for actual run windows go to `data/raw/<region>/<iid>/em-history.json`.
