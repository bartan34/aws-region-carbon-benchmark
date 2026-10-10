# aws-region-carbon-benchmark

Run the same CPU-bound benchmark in several AWS regions and estimate the
lifecycle carbon footprint per unit of work using the Software Carbon
Intensity (SCI) formula from ISO/IEC 21031:2024.

    SCI = ((E × I) + M) / R

| Term | Meaning | Where it comes from |
|---|---|---|
| E | Energy (kWh) | Measured CPU utilisation (CloudWatch, 1-min) × published per-instance power curve (Teads) × AWS regional PUE |
| I | Grid carbon intensity (gCO₂e/kWh), location-based | Electricity Maps / Google Cloud region table / Ember |
| M | Embodied emissions (gCO₂e) allocated to the run | Boavizta API |
| R | Functional unit | sysbench events (per 10⁶) or one benchmark run |

Why estimate instead of measure: EC2 virtual machines do not expose RAPL
power counters, so every published cloud-carbon method (Teads, Cloud Carbon
Footprint, Boavizta, Dodge et al. 2022) models power from utilisation.
This repo makes that model explicit, parametric and reproducible.

## What you get

For each region: measured runtime, throughput (events/s), CPU utilisation,
and SCI under three accounting views side by side — location-based annual,
location-based hourly, and market-based. Plus a sensitivity (tornado)
analysis showing which coefficient drives the result.

Example output (placeholder until first run):

| Region | CPU model | events/s ± SD | E (Wh/run) | I annual | Operational (g) | Embodied (g) | SCI g/10⁶ ev |
|---|---|---|---|---|---|---|---|
| eu-north-1 | … | … | … | 19 | … | … | … |
| us-east-1 | … | … | … | 343 | … | … | … |

## Quick start

Prerequisites: AWS CLI v2 configured, `jq`, Python 3.10+, an IAM instance
profile named `carbon-bench-ec2-role` (see `docs/iam-policy.json`), and
an AWS Budget alarm. Set one up before launching anything.

```bash
# 1. Pilot: one region, 2-minute runs, confirm the pipeline end to end
./scripts/launch.sh us-east-1 m5.large 1 120 60

# 2. Full run: 5 × 10-min runs + 10-min idle baseline, per region
for r in us-east-1 us-west-2 eu-west-1 eu-north-1 ap-south-1; do
  ./scripts/launch.sh $r m5.large 5 600 600
done

# 3. After each instance reports done_utc in S3 (≈70 min), pull metrics
./scripts/pull-cloudwatch.sh us-east-1 i-0123456789abcdef0

# 4. Embodied emissions per region (country code, hours)
./scripts/boavizta.sh m5.large USA 0.1667

# 5. Compute SCI
python3 analysis/sci.py
```

The instance terminates itself when the benchmark finishes
(`--instance-initiated-shutdown-behavior terminate`). Run
`./scripts/cleanup.sh <region>` afterwards to confirm nothing is left.

## Repository layout

```
scripts/            launch, user-data (benchmark), metric pull, Boavizta, cleanup
data/coefficients/  every external number with source, year, access date
data/raw/<region>/  per-instance outputs: sysbench, lscpu, meta.json, cloudwatch.csv
data/processed/     sci-results.csv
analysis/           sci.py (computation), figures/
docs/               IAM policy, architecture diagram, write-ups
```

## Design choices

- **m5.large** — non-burstable (T-series credit/boost behaviour distorts
  runtime), measured in the Teads dataset, present in Boavizta.
- **sysbench cpu** — deterministic prime search, reports events/s, which
  becomes the functional unit R. Integer workload; power at 100% is an
  upper-bound estimate.
- **Ubuntu 24.04** via SSM Parameter Store — identical AMI in every region.
- **Same-region S3 bucket** for outputs, so no cross-region data movement.
- **UTC everywhere**, 1-minute CloudWatch detailed monitoring, lscpu saved
  per instance to detect CPU-model variation across regions.

## Assumptions and limitations

- Power is modelled, not measured; Teads data dates from 2021.
- PUE is AWS's published regional average, not per data centre.
- Grid intensity zone mapping is approximate for us-west-2 and ap-south-1.
- Boavizta covers the server share only (no network, storage, building).
- One CPU-bound workload; results do not transfer to memory/IO-bound jobs.
- Data-transfer and latency costs of actually moving a workload are out
  of scope (see Sukprasert et al. 2024).

## Coefficient sources

See `data/coefficients/*.csv` — each row carries source URL, year and
access date. Primary sources: Davy (2021, Teads), Cloud Carbon Footprint
methodology, Boavizta API, Amazon AWS sustainability page (PUE), Google
Cloud region carbon table, Electricity Maps, ISO/IEC 21031:2024.

## Licence

Code: MIT. Data under `data/`: CC BY 4.0 (compatible with the Teads
dataset licence). See `LICENSE` and `data/LICENSE`.

## Origin

Started as coursework for a cloud architecture module (TU Dublin, 2026),
answering "How do regions differ in carbon emissions for the same
workload?". The tool is general; the coursework write-up is not part of
this repository.
