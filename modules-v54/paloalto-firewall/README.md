# Palo Alto VM-Series Firewall MIG

This module deploys a stateful regional managed instance group of Palo Alto VM-Series firewall appliances. Multi-NIC interfaces are attached in order from the `networks` list, so the same module produces either a 2-NIC east/west firewall (e.g. `["mngt", "trust"]`) or a 3-NIC north/south firewall (e.g. `["mngt", "trust", "untrust"]`) by switching `firewall_type` and the network list. Instances bootstrap from GCS and auto-register with Panorama via the values passed in instance `metadata`.

## Example

```hcl
module "ns-firewall" {
  source                = "./fabric/modules/paloalto-firewall"
  project_id            = var.project_id
  region                = var.region
  firewall_type         = "ns"
  networks              = ["mngt", "trust", "untrust"]
  machine_type          = "n2-standard-4"
  firewall_image        = "projects/paloaltonetworksgcp-public/global/images/vmseries-flex-bundle2-1022h2"
  instances_per_mig     = 2
  service_account_email = "panw-fw-sa@${var.project_id}.iam.gserviceaccount.com"
  vpcs = {
    mngt    = module.vpc-mngt.id
    trust   = module.vpc-trust.id
    untrust = module.vpc-untrust.id
  }
  subnets = {
    mngt    = module.vpc-mngt.subnet_ids["${var.region}/mngt"]
    trust   = module.vpc-trust.subnet_ids["${var.region}/trust"]
    untrust = module.vpc-untrust.subnet_ids["${var.region}/untrust"]
  }
  metadata = {
    mgmt-interface-swap                  = "enable"
    vmseries-bootstrap-gce-storagebucket = "panw-bootstrap-${var.project_id}"
    serial-port-enable                   = "true"
    panorama-server                      = "10.0.0.10"
    tplname                              = "ns-template-stack"
    dgname                               = "ns-device-group"
  }
}
```

## Variables

| name | description | type | required | default |
|---|---|:---:|:---:|:---:|
| [firewall_image](variables.tf) | Firewall image to use. | <code>string</code> | ✓ |  |
| [firewall_type](variables.tf) | Firewall type (`ew` or `ns`). | <code>string</code> | ✓ |  |
| [instances_per_mig](variables.tf) | Number of instances per MIG. | <code>number</code> | ✓ |  |
| [machine_type](variables.tf) | Machine type for firewall instances. | <code>string</code> | ✓ |  |
| [networks](variables.tf) | List of network names to attach (e.g., `[mngt, trust]` or `[mngt, trust, untrust]`). | <code>list&#40;string&#41;</code> | ✓ |  |
| [project_id](variables.tf) | GCP Project ID. | <code>string</code> | ✓ |  |
| [region](variables.tf) | GCP Region. | <code>string</code> | ✓ |  |
| [service_account_email](variables.tf) | Service account email for firewall instances. | <code>string</code> | ✓ |  |
| [subnets](variables.tf) | Map of subnet IDs by name. | <code>map&#40;string&#41;</code> | ✓ |  |
| [vpcs](variables.tf) | Map of VPC IDs by name. | <code>map&#40;string&#41;</code> | ✓ |  |
| [disk_size_gb](variables.tf) | Boot disk size in GB. | <code>number</code> |  | <code>60</code> |
| [metadata](variables.tf) | Metadata to apply to firewall instances. | <code>map&#40;string&#41;</code> |  | <code>&#123;&#125;</code> |

## Outputs

| name | description | sensitive |
|---|---|:---:|
| [mig_instance_group](outputs.tf) | Self-link of the regional MIG instance group, for ILB backends. |  |
