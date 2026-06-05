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

# tfdoc:file:description Palo Alto NGFW internal load balancers (E/W + N/S) on
# the trust VPC, with CLIENT_IP_NO_DESTINATION session affinity. Gated on
# local.paloalto_enabled.

module "ilb_ew_firewall_trust" {
  count      = local.paloalto_enabled ? 1 : 0
  source     = "../../../modules-v54/net-lb-int"
  project_id = local.pa_project_id
  region     = local.pa_region
  name       = "ilb-ew-firewall-trust"
  vpc_config = {
    network    = local.pa_vpcs["trust"]
    subnetwork = local.pa_subnets["trust"]
  }
  backends = [
    { group = module.ew_firewall[0].mig_instance_group }
  ]
  backend_service_config = {
    session_affinity = "CLIENT_IP_NO_DESTINATION"
    connection_tracking = {
      track_per_session         = true
      persist_conn_on_unhealthy = "NEVER_PERSIST"
    }
  }
  health_check_config = {
    tcp = { port = 22 }
  }
  context = {
    project_ids = local.ctx_projects.project_ids
    networks    = local.ctx_vpcs.self_links
    subnets     = local.ctx_vpcs.subnets_by_vpc
  }
}

module "ilb_ns_firewall_trust" {
  count      = local.paloalto_enabled ? 1 : 0
  source     = "../../../modules-v54/net-lb-int"
  project_id = local.pa_project_id
  region     = local.pa_region
  name       = "ilb-ns-firewall-trust"
  vpc_config = {
    network    = local.pa_vpcs["trust"]
    subnetwork = local.pa_subnets["trust"]
  }
  backends = [
    { group = module.ns_firewall[0].mig_instance_group }
  ]
  backend_service_config = {
    session_affinity = "CLIENT_IP_NO_DESTINATION"
    connection_tracking = {
      track_per_session         = true
      persist_conn_on_unhealthy = "NEVER_PERSIST"
    }
  }
  health_check_config = {
    tcp = { port = 22 }
  }
  context = {
    project_ids = local.ctx_projects.project_ids
    networks    = local.ctx_vpcs.self_links
    subnets     = local.ctx_vpcs.subnets_by_vpc
  }
}
