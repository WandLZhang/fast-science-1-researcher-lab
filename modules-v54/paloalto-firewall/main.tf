locals {
  name_prefix = "${var.firewall_type}-firewall"
  base_name   = "gcp-${var.firewall_type}-firewall"
}

resource "google_compute_region_instance_template" "firewall" {
  project        = var.project_id
  name_prefix    = "${local.base_name}-"
  region         = var.region
  machine_type   = var.machine_type
  can_ip_forward = true
  tags           = ["${var.firewall_type}-firewall"]

  service_account {
    email  = var.service_account_email
    scopes = ["cloud-platform"]
  }

  disk {
    device_name  = "boot"
    source_image = var.firewall_image
    disk_size_gb = var.disk_size_gb
    auto_delete  = true
    boot         = true
  }

  dynamic "network_interface" {
    for_each = var.networks
    content {
      network    = var.vpcs[network_interface.value]
      subnetwork = var.subnets[network_interface.value]
    }
  }

  metadata = var.metadata

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_health_check" "firewall" {
  project = var.project_id
  name    = "${local.name_prefix}-health-check"

  tcp_health_check {
    port = 22
  }
}

resource "google_compute_region_instance_group_manager" "firewall_mig" {
  project            = var.project_id
  name               = "${local.name_prefix}-mig"
  base_instance_name = local.base_name
  region             = var.region
  target_size        = var.instances_per_mig

  distribution_policy_target_shape = "EVEN"

  version {
    instance_template = google_compute_region_instance_template.firewall.id
  }

  stateful_disk {
    device_name = "boot"
    delete_rule = "NEVER"
  }

  dynamic "stateful_internal_ip" {
    for_each = range(length(var.networks))
    content {
      interface_name = "nic${stateful_internal_ip.value}"
      delete_rule    = "NEVER"
    }
  }

  auto_healing_policies {
    health_check      = google_compute_health_check.firewall.id
    initial_delay_sec = 900
  }

  update_policy {
    type                         = "PROACTIVE"
    minimal_action               = "REPLACE"
    replacement_method           = "RECREATE"
    instance_redistribution_type = "NONE"
    max_surge_fixed              = 0
    max_unavailable_fixed        = 3
  }
}
