#!/usr/bin/env bash
# chaos_failover.sh — Simulate a regional Web App failure and prove Front Door
# reroutes traffic to the surviving region.
#
# Prerequisites:
#   - Azure CLI installed and logged in  (az login)
#   - jq installed                       (brew install jq)
#   - Terraform outputs already applied  (terraform output -json > ../infra/tf_outputs.json)
#
# Usage:
#   ./chaos_failover.sh kill     — disable the primary region, watch failover
#   ./chaos_failover.sh restore  — re-enable it, watch traffic return
#   ./chaos_failover.sh status   — show live health of both origins
#   ./chaos_failover.sh logs     — tail diagnostic logs with annotations

set -euo pipefail

# ─── CONFIG ──────────────────────────────────────────────────────────────────
# These are read from Terraform outputs so you never hard-code resource names.
OUTPUTS_FILE="$(dirname "$0")/../infra/tf_outputs.json"

if [[ ! -f "$OUTPUTS_FILE" ]]; then
  echo "[ERROR] Run this first from the infra/ directory:"
  echo "        terraform output -json > tf_outputs.json"
  exit 1
fi

RG=$(jq -r '.cosmos_account_name.value' "$OUTPUTS_FILE" | sed 's/-cosmos-.*//')"-rg-dev"
PRIMARY_APP=$(jq -r '.webapp_primary_name.value'   "$OUTPUTS_FILE")
SECONDARY_APP=$(jq -r '.webapp_secondary_name.value' "$OUTPUTS_FILE")
AFD_PROFILE=$(jq -r '.cosmos_account_name.value' "$OUTPUTS_FILE" | sed 's/-cosmos-.*//')"-afd-dev"
AFD_ENDPOINT=$(jq -r '.frontdoor_hostname.value'   "$OUTPUTS_FILE")
PROBE_URL="https://${AFD_ENDPOINT}/health"

# ─── COLOUR HELPERS ──────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

log()  { echo -e "${CYAN}[$(date '+%H:%M:%S')]${RESET} $*"; }
ok()   { echo -e "${GREEN}[$(date '+%H:%M:%S')] ✓${RESET} $*"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] ⚠${RESET} $*"; }
fail() { echo -e "${RED}[$(date '+%H:%M:%S')] ✗${RESET} $*"; }

# ─── PROBE LOOP ──────────────────────────────────────────────────────────────
# Hits the Front Door endpoint every 5 seconds, prints HTTP status and which
# origin served the response (via the x-azure-ref and x-cache headers).
watch_traffic() {
  local duration=${1:-120}   # seconds to watch (default 2 min)
  local end=$((SECONDS + duration))

  log "Watching traffic via Front Door for ${duration}s — Ctrl+C to stop early"
  echo -e "${BOLD}TIME      STATUS  ORIGIN-REGION                    X-AZURE-REF (truncated)${RESET}"
  echo    "────────  ──────  ───────────────────────────────  ──────────────────────────────"

  while [[ $SECONDS -lt $end ]]; do
    # -sS: silent but show errors | -o /dev/null: discard body | -D -: dump headers to stdout
    HEADERS=$(curl -sS --max-time 5 -o /dev/null -D - "$PROBE_URL" 2>&1 || true)

    HTTP_STATUS=$(echo "$HEADERS" | grep "^HTTP/" | awk '{print $2}' | tail -1)
    # x-azure-ref encodes the PoP and origin; last segment after _ is the region code
    AZURE_REF=$(echo "$HEADERS"   | grep -i "^x-azure-ref:"  | awk '{print $2}' | tr -d '\r' | cut -c1-40)
    # x-ms-routing-name is set by Front Door Standard and names the origin
    ORIGIN=$(echo "$HEADERS"      | grep -i "^x-ms-routing-name:" | awk '{print $2}' | tr -d '\r')
    [[ -z "$ORIGIN" ]] && ORIGIN="(check x-azure-ref)"

    if [[ "$HTTP_STATUS" == "200" ]]; then
      ok "$(printf '%-6s  %-32s  %s' "$HTTP_STATUS" "$ORIGIN" "$AZURE_REF")"
    else
      fail "$(printf '%-6s  %-32s  %s' "$HTTP_STATUS" "$ORIGIN" "$AZURE_REF")"
    fi

    sleep 5
  done
}

# ─── KILL ────────────────────────────────────────────────────────────────────
kill_region() {
  echo ""
  echo -e "${RED}${BOLD}━━━  CHAOS: KILLING PRIMARY REGION  ━━━${RESET}"
  log "Stopping Web App: ${PRIMARY_APP} in resource group: ${RG}"

  # Stopping the Web App makes /health return 503 — exactly what a real
  # regional outage looks like to Front Door's health probe.
  az webapp stop \
    --name "$PRIMARY_APP" \
    --resource-group "$RG" \
    --output none

  ok "Primary Web App stopped."
  warn "Front Door probes /health every 30s and needs 3/4 failures → allow ~90s for reroute."
  echo ""
  log "Starting traffic watch — look for the ORIGIN column to switch from weu → eus"
  echo ""

  # Capture a timestamp so you can correlate with Front Door access logs later
  CHAOS_START=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  echo "$CHAOS_START" > /tmp/chaos_start.txt

  watch_traffic 180   # watch for 3 minutes — enough to see the failover
}

# ─── RESTORE ─────────────────────────────────────────────────────────────────
restore_region() {
  echo ""
  echo -e "${GREEN}${BOLD}━━━  RESTORE: BRINGING PRIMARY REGION BACK  ━━━${RESET}"
  log "Starting Web App: ${PRIMARY_APP}"

  az webapp start \
    --name "$PRIMARY_APP" \
    --resource-group "$RG" \
    --output none

  ok "Primary Web App started."
  warn "Front Door needs 3/4 successful probes to mark origin healthy again (~90s)."
  echo ""
  log "Watching for traffic to shift back to weu..."
  echo ""

  watch_traffic 180
}

# ─── STATUS ──────────────────────────────────────────────────────────────────
show_status() {
  echo ""
  echo -e "${BOLD}── Web App States ────────────────────────────────────${RESET}"

  for APP in "$PRIMARY_APP" "$SECONDARY_APP"; do
    STATE=$(az webapp show \
      --name "$APP" \
      --resource-group "$RG" \
      --query "state" -o tsv 2>/dev/null || echo "unknown")

    if [[ "$STATE" == "Running" ]]; then
      ok "${APP}: ${GREEN}${STATE}${RESET}"
    else
      fail "${APP}: ${RED}${STATE}${RESET}"
    fi
  done

  echo ""
  echo -e "${BOLD}── Front Door Origin Health ──────────────────────────${RESET}"
  # Front Door exposes origin health via az afd origin list — state field
  az afd origin list \
    --profile-name "$AFD_PROFILE" \
    --origin-group-name "$(az afd origin-group list \
        --profile-name "$AFD_PROFILE" \
        --resource-group "$RG" \
        --query "[0].name" -o tsv)" \
    --resource-group "$RG" \
    --query "[].{Name:name, Enabled:enabledState, Host:hostName}" \
    --output table 2>/dev/null || warn "Run 'az login' if this fails."

  echo ""
  echo -e "${BOLD}── Live Probe ─────────────────────────────────────────${RESET}"
  log "Sending single probe to: ${PROBE_URL}"
  curl -sS --max-time 5 -D - -o /dev/null "$PROBE_URL" \
    | grep -E "^HTTP/|x-azure-ref|x-ms-routing|x-cache" || true
}

# ─── LOGS ────────────────────────────────────────────────────────────────────
read_logs() {
  CHAOS_START=${1:-$(cat /tmp/chaos_start.txt 2>/dev/null || date -u -v-10M '+%Y-%m-%dT%H:%M:%SZ')}

  echo ""
  echo -e "${BOLD}━━━  HOW TO READ THE LOGS  ━━━${RESET}"
  echo ""
  echo -e "${CYAN}1. Front Door Access Logs (Azure Monitor)${RESET}"
  echo "   These show every request and which backend served it."
  echo "   Run in Azure Portal → Monitor → Log Analytics → your workspace:"
  echo ""
  cat << 'KUSTO'
  // Paste this KQL query into Log Analytics:
  AzureDiagnostics
  | where TimeGenerated >= datetime(CHAOS_START_PLACEHOLDER)
  | where ResourceType == "FRONTDOORS"
  | where OperationName == "Microsoft.Network/FrontDoor/AccessLog/Write"
  | project TimeGenerated,
            backendHostname_s,     // ← which origin served the request
            httpStatusCode_d,      // ← 200 = healthy, 503 = origin down
            timeTakenMs_d,         // ← latency spike during failover
            clientIp_s,
            requestUri_s
  | order by TimeGenerated asc
KUSTO
  echo ""
  echo -e "   Replace ${YELLOW}CHAOS_START_PLACEHOLDER${RESET} with: ${CHAOS_START}"
  echo ""

  echo -e "${CYAN}2. What to look for in the log output${RESET}"
  echo ""
  echo -e "   ${BOLD}Phase 1 — Normal (before chaos):${RESET}"
  echo "   backendHostname_s alternates between weu and eus app hostnames"
  echo "   httpStatusCode_d = 200 consistently"
  echo ""
  echo -e "   ${BOLD}Phase 2 — Failover window (~0–90s after kill):${RESET}"
  echo "   Some requests to weu return 503 (app stopped, /health failing)"
  echo "   Front Door may briefly return 503 to users during probe accumulation"
  echo "   timeTakenMs_d spikes as Front Door retries on the healthy origin"
  echo ""
  echo -e "   ${BOLD}Phase 3 — Stable on secondary (>90s after kill):${RESET}"
  echo "   backendHostname_s = ONLY the eus app hostname"
  echo "   httpStatusCode_d = 200 again — full failover confirmed"
  echo ""

  echo -e "${CYAN}3. Web App logs (real-time stream)${RESET}"
  echo "   Run these in two separate terminals to watch both regions live:"
  echo ""
  echo -e "   ${YELLOW}# Terminal 1 — Primary (West Europe)${RESET}"
  echo "   az webapp log tail --name ${PRIMARY_APP} --resource-group ${RG}"
  echo ""
  echo -e "   ${YELLOW}# Terminal 2 — Secondary (East US)${RESET}"
  echo "   az webapp log tail --name ${SECONDARY_APP} --resource-group ${RG}"
  echo ""
  echo "   During failover you'll see the secondary log fill with requests"
  echo "   while the primary goes silent — that's the proof."
  echo ""

  echo -e "${CYAN}4. Cosmos DB — prove no writes were lost${RESET}"
  echo "   After restore, run this in Azure Portal → Cosmos DB → Data Explorer:"
  echo ""
  cat << 'COSMOS'
  SELECT c.id, c.regionOrigin, c._ts
  FROM c
  WHERE c._ts >= CHAOS_TS_UNIX
  ORDER BY c._ts ASC
COSMOS
  echo ""
  echo "   If records exist with regionOrigin = 'East US' timestamped DURING"
  echo "   the outage window, writes never stopped. That's multi-write working."
  echo ""
}

# ─── ENTRYPOINT ──────────────────────────────────────────────────────────────
case "${1:-help}" in
  kill)    kill_region ;;
  restore) restore_region ;;
  status)  show_status ;;
  logs)    read_logs "${2:-}" ;;
  *)
    echo ""
    echo -e "${BOLD}chaos_failover.sh — Azure Front Door chaos testing tool${RESET}"
    echo ""
    echo "  Commands:"
    echo "    kill             Stop the primary (West Europe) Web App, watch failover"
    echo "    restore          Restart it, watch traffic return"
    echo "    status           Show live health of both Web Apps + origins"
    echo "    logs [ISO_DATE]  Print log-reading guide (optional: chaos start time)"
    echo ""
    echo "  Typical flow:"
    echo "    1. terraform output -json > infra/tf_outputs.json"
    echo "    2. ./scripts/chaos_failover.sh status    # confirm both healthy"
    echo "    3. ./scripts/chaos_failover.sh kill      # trigger chaos"
    echo "    4. ./scripts/chaos_failover.sh logs      # interpret what happened"
    echo "    5. ./scripts/chaos_failover.sh restore   # heal the region"
    echo ""
    ;;
esac
