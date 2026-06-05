/**
 * Copyright 2026 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

# tfdoc:file:description Palo Alto NGFW routing: default trust-vpc route to the
# N/S firewall ILB plus policy-based routes (PBR) that bypass / divert traffic
# through the E/W firewall ILB. All resources gated on local.paloalto_enabled.

# Default 0.0.0.0/0 route on the trust VPC pointing at the N/S firewall ILB
# (next-hop ILB by forwarding-rule self-link).
resource "google_compute_route" "pa_trust_default_to_ns" {
  count        = local.paloalto_enabled ? 1 : 0
  project      = local.pa_project_id
  name         = "default-trust-to-ns-ilb"
  network      = local.pa_vpcs["trust"]
  dest_range   = "0.0.0.0/0"
  next_hop_ilb = module.ilb_ns_firewall_trust[0].forwarding_rule_self_links[""]
  priority     = 100
}

# PBR: on-prem -> on-prem on hosts tagged ew-firewall must bypass the trust
# default route and fall back to system routing.
resource "google_network_connectivity_policy_based_route" "pa_ew_bypass" {
  count    = local.paloalto_enabled ? 1 : 0
  project  = local.pa_project_id
  name     = "ew-firewall-bypass"
  network  = local.pa_vpcs["trust"]
  priority = 10
  filter {
    protocol_version = "IPV4"
    src_range        = var.paloalto.onprem_cidr
    dest_range       = var.paloalto.onprem_cidr
  }
  next_hop_other_routes = "DEFAULT_ROUTING"
  virtual_machine {
    tags = ["ew-firewall"]
  }
}

# PBR: on-prem -> mngt CIDR must bypass the firewalls so management traffic
# uses default routing instead of being hairpinned.
resource "google_network_connectivity_policy_based_route" "pa_mngt_bypass" {
  count    = local.paloalto_enabled ? 1 : 0
  project  = local.pa_project_id
  name     = "mngt-bypass"
  network  = local.pa_vpcs["trust"]
  priority = 50
  filter {
    protocol_version = "IPV4"
    src_range        = var.paloalto.onprem_cidr
    dest_range       = var.paloalto.mngt_cidr
  }
  next_hop_other_routes = "DEFAULT_ROUTING"
}

# PBR: on-prem -> on-prem traffic (non-ew-firewall hosts) goes through the
# E/W firewall ILB (next-hop is the ILB's forwarding-rule IP address).
resource "google_network_connectivity_policy_based_route" "pa_internal_to_ew" {
  count    = local.paloalto_enabled ? 1 : 0
  project  = local.pa_project_id
  name     = "internal-to-ew-firewall"
  network  = local.pa_vpcs["trust"]
  priority = 100
  filter {
    protocol_version = "IPV4"
    src_range        = var.paloalto.onprem_cidr
    dest_range       = var.paloalto.onprem_cidr
  }
  next_hop_ilb_ip = module.ilb_ew_firewall_trust[0].forwarding_rule_addresses[""]
}
