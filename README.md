# Chaos-Resilient Multi-Region Infrastructure on Azure

A production-grade, Active-Active infrastructure across two Azure regions using Terraform. Designed to survive regional failures with zero write loss and automatic traffic rerouting within ~90 seconds.

---

## Architecture

```
User  ──HTTPS──►  <name>.azurefd.net  (Azure Front Door)
                        │
              ┌─────────▼──────────┐
              │   Origin Group     │  GET /health every 30s
              │  weu  │  eus       │  3/4 failures = origin unhealthy
              └───┬───────┬────────┘
                  ▼       ▼
            West Europe  East US
            Web App      Web App
                  │       │
                  └───┬───┘
                      ▼
               Cosmos DB (multi-write)
               Both regions accept writes simultaneously
```

| Component | Role |
|---|---|
| **Azure Front Door** | Global Anycast entry point. Health-probes both origins every 30s and automatically drains traffic away from a failed region. |
| **Web Apps (×2)** | Linux Node.js apps, one per region. Both receive live traffic (Active-Active). |
| **Cosmos DB** | `enable_multiple_write_locations = true` — no single write master. If a region disappears the other was already accepting writes. |

---

## Project Structure

```
.
├── infra/                     Terraform
│   ├── providers.tf
│   ├── variables.tf
│   ├── main.tf                Wires all modules together
│   ├── outputs.tf
│   └── modules/
│       ├── cosmosdb/          Cosmos account, database, container
│       ├── webapp/            App Service Plan + Linux Web App (reused per region)
│       └── frontdoor/        Profile, endpoint, origin group, origins, route
├── app/                       Minimal Node.js app
│   ├── server.js              GET /health  +  POST /write
│   └── package.json
└── scripts/
    └── chaos_failover.sh      Chaos experiment tool
```

---

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) — run `az login` before deploying
- [jq](https://jqlang.github.io/jq/) — used by the chaos script
- An active Azure subscription

---

## Deploy

```bash
# 1. Authenticate
az login

# 2. Initialise and deploy infrastructure
cd infra
terraform init
terraform plan -out=tfplan
terraform apply tfplan

# 3. Save outputs for the chaos script
terraform output -json > tf_outputs.json

# 4. Package and deploy the app to both regions
cd ../app
npm install
zip -r ../app.zip .

az webapp deploy \
  --name $(cd ../infra && terraform output -raw webapp_primary_name) \
  --resource-group chaosinfra-rg-dev \
  --src-path ../app.zip --type zip

az webapp deploy \
  --name $(cd ../infra && terraform output -raw webapp_secondary_name) \
  --resource-group chaosinfra-rg-dev \
  --src-path ../app.zip --type zip
```

After apply, Terraform prints:

| Output | Description |
|---|---|
| `frontdoor_url` | The single URL your users hit |
| `webapp_primary_url` | West Europe direct URL (bypasses Front Door) |
| `webapp_secondary_url` | East US direct URL (bypasses Front Door) |
| `cosmos_endpoint` | Cosmos DB endpoint |

---

## Chaos Experiment

The chaos script simulates a full regional failure and lets you watch Front Door reroute traffic in real time.

```bash
# Confirm both regions are healthy before starting
./scripts/chaos_failover.sh status

# Kill the primary region (West Europe) — watch the failover happen
./scripts/chaos_failover.sh kill

# After the experiment — restore the region
./scripts/chaos_failover.sh restore

# Print the log-reading guide with KQL queries
./scripts/chaos_failover.sh logs
```

### What to expect

```
TIME      STATUS  ORIGIN
────────  ──────  ─────────────────────────────
09:00:05  200     origin-chaosinfra-app-weu-dev   ← normal, split traffic
09:00:10  200     origin-chaosinfra-app-eus-dev
# --- kill triggered ---
09:00:45  503     origin-chaosinfra-app-weu-dev   ← probe failures accumulating
09:01:30  200     origin-chaosinfra-app-eus-dev   ← FAILOVER COMPLETE (~90s)
09:01:35  200     origin-chaosinfra-app-eus-dev   ← 100% traffic on East US
```

**Failover is proven when:**
1. `weu` origin returns `503` — Front Door detected the failure
2. All subsequent `200`s come from `eus` — traffic fully rerouted
3. Time between first `503` and stable `200` is ≤ 90 seconds

### Proving zero write loss (Cosmos DB)

Run this in Azure Portal → Cosmos DB → Data Explorer after restoring:

```sql
SELECT c.regionOrigin, c.timestamp FROM c
WHERE c._ts >= <unix_timestamp_of_chaos_start>
ORDER BY c._ts ASC
```

Records with `regionOrigin = "East US"` timestamped *during* the outage window confirm that writes never stopped — multi-write was active the entire time.

---

## Key Configuration Decisions

**Why `BoundedStaleness` consistency?**
Strong consistency blocks writes until all regions confirm — too slow for multi-write. Eventual consistency risks reading stale data in the same session. BoundedStaleness (≤5 min, ≤100k operations behind) is the practical middle ground for most applications.

**Why Active-Active instead of Active-Passive?**
Active-Passive means the secondary sits idle until needed. Active-Active means both regions serve real traffic at all times — so the secondary is already warm, already connected to Cosmos DB, and proven healthy when the primary fails. Failover is a traffic shift, not a cold start.

**Why `priority = 1` on both origins?**
Front Door priority controls which origin group tier is preferred. Equal priority (both = 1) means load-balanced across both. Setting secondary to `priority = 2` would make it Active-Passive.

---

## Tear Down

```bash
cd infra
terraform destroy
```

> The provider config sets `prevent_deletion_if_contains_resources = true` on the resource group. Remove that block or run `terraform destroy` — do not delete the resource group manually first or Terraform state will desync.
