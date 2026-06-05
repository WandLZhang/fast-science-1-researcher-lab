output "mig_instance_group" {
  description = "Self-link of the regional MIG instance group, for ILB backends."
  value       = google_compute_region_instance_group_manager.firewall_mig.instance_group
}
