#!/bin/bash
# On-demand Linux price per hour for one instance type in every region of regions.csv.
# Usage: ./scripts/pricing.sh [instance-type]
# Writes data/coefficients/pricing.csv. The Pricing API endpoint lives in us-east-1
# and needs pricing:GetProducts (not part of the EC2 instance role).
set -euo pipefail
ITYPE=${1:-m5.large}
cd "$(dirname "$0")/.."
OUT=data/coefficients/pricing.csv
ACCESSED=$(date -u +%F)
echo "region,instance_type,usd_per_hour,pricing_model,effective_date,publication_date,source,accessed" > "$OUT"
for REGION in $(tail -n +2 data/coefficients/regions.csv | cut -d, -f1); do
  aws pricing get-products --region us-east-1 --service-code AmazonEC2 --output json --filters \
    Type=TERM_MATCH,Field=instanceType,Value="$ITYPE" \
    Type=TERM_MATCH,Field=regionCode,Value="$REGION" \
    Type=TERM_MATCH,Field=operatingSystem,Value=Linux \
    Type=TERM_MATCH,Field=tenancy,Value=Shared \
    Type=TERM_MATCH,Field=preInstalledSw,Value=NA \
    Type=TERM_MATCH,Field=capacitystatus,Value=Used \
  | jq -r --arg r "$REGION" --arg t "$ITYPE" --arg a "$ACCESSED" '
      .PriceList[] | fromjson | . as $p
      | .terms.OnDemand[] | .effectiveDate as $eff
      | .priceDimensions[]
      | [$r, $t, (.pricePerUnit.USD | tonumber), "on-demand", ($eff[:10]), ($p.publicationDate[:10]),
         "AWS Price List Query API", $a] | @csv' \
  | tr -d '"' >> "$OUT"
done
cat "$OUT"
