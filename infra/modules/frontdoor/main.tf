# ─── PROFILE ─────────────────────────────────────────────────────────────────
# The profile is the top-level Front Door container.
# Standard_AzureFrontDoor includes WAF, caching, and health probes.
# Premium_AzureFrontDoor adds Private Link origins — we don't need that here.
resource "azurerm_cdn_frontdoor_profile" "main" {
  name                = "${var.project_name}-afd-${var.environment}"
  resource_group_name = var.resource_group_name
  sku_name            = "Standard_AzureFrontDoor"

  tags = {
    environment = var.environment
    project     = var.project_name
  }
}

# ─── ENDPOINT ────────────────────────────────────────────────────────────────
# An endpoint is a public-facing hostname: <name>.azurefd.net
# All user traffic enters through this single URL regardless of which
# backend region actually serves the request.
resource "azurerm_cdn_frontdoor_endpoint" "main" {
  name                     = "${var.project_name}-ep-${var.environment}"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.main.id

  tags = {
    environment = var.environment
    project     = var.project_name
  }
}

# ─── ORIGIN GROUP ────────────────────────────────────────────────────────────
# An origin group is a pool of backends (your two Web Apps).
# Front Door load-balances across healthy origins in the group.
resource "azurerm_cdn_frontdoor_origin_group" "main" {
  name                     = "${var.project_name}-og-${var.environment}"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.main.id

  # If a request fails, retry once on a different origin before returning error.
  # This is the first line of defense during a partial regional failure.
  session_affinity_enabled = false

  restore_traffic_time_to_healed_or_new_endpoint_in_minutes = 10

  load_balancing {
    # How many probe samples Front Door collects before making a health decision
    sample_size                 = 4
    # How many of those samples must succeed for the origin to be "healthy"
    successful_samples_required = 3
    # Extra latency (ms) tolerated before preferring the closer origin.
    # 50ms means: "don't switch to a farther region unless the near one is >50ms slower"
    additional_latency_in_milliseconds = 50
  }

  health_probe {
    path                = "/health"      # must match health_check_path in Web App
    protocol            = "Https"
    request_type        = "GET"
    interval_in_seconds = 30             # probe every 30 seconds
  }
}

# ─── ORIGINS ─────────────────────────────────────────────────────────────────
# Each origin is one of your regional Web Apps.
# priority = 1 on both means Active-Active (equal weight).
# If you wanted Active-Passive, set primary priority=1, secondary priority=2.

resource "azurerm_cdn_frontdoor_origin" "primary" {
  name                          = "origin-${var.primary_app_name}"
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.main.id

  host_name          = var.primary_app_hostname
  origin_host_header = var.primary_app_hostname  # SNI header must match the cert
  http_port          = 80
  https_port         = 443

  priority = 1   # same as secondary = Active-Active
  weight   = 500 # equal weight; Front Door splits traffic 50/50

  # certificate_name_check_enabled prevents man-in-the-middle on the
  # Front Door → origin leg (the backend connection, not the user-facing one)
  certificate_name_check_enabled = true

  enabled = true
}

resource "azurerm_cdn_frontdoor_origin" "secondary" {
  name                          = "origin-${var.secondary_app_name}"
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.main.id

  host_name          = var.secondary_app_hostname
  origin_host_header = var.secondary_app_hostname
  http_port          = 80
  https_port         = 443

  priority = 1
  weight   = 500

  certificate_name_check_enabled = true

  enabled = true
}

# ─── ROUTE ───────────────────────────────────────────────────────────────────
# A route maps: incoming request pattern → origin group
# "/*" catches everything and sends it to our two-Web-App pool.
resource "azurerm_cdn_frontdoor_route" "main" {
  name                          = "default-route"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.main.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.main.id

  cdn_frontdoor_origin_ids = [
    azurerm_cdn_frontdoor_origin.primary.id,
    azurerm_cdn_frontdoor_origin.secondary.id,
  ]

  supported_protocols    = ["Https"]        # HTTPS only at the edge
  patterns_to_match      = ["/*"]
  forwarding_protocol    = "HttpsOnly"      # Front Door → origin also HTTPS
  https_redirect_enabled = true             # redirect any stray HTTP to HTTPS
  link_to_default_domain = true

  # Disable caching so dynamic app responses always reach the origins.
  # Enable this later for static assets to reduce origin load.
  cache {
    query_string_caching_behavior = "IgnoreQueryString"
    compression_enabled           = true
    content_types_to_compress = [
      "application/json",
      "text/html",
      "text/plain",
    ]
  }
}
