/**
 * Copyright 2023 Google LLC
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

# tfdoc:file:description Organization-level IAM bindings locals.

# Upstream sets exact members (google_organization_iam_binding) for most
# org-level roles. This fork adds members one at a time
# (google_organization_iam_member) for every principal, so an apply or a
# destroy leaves members granted outside this stage alone, such as the
# groups Google Cloud Setup creates and break-glass admins.
#
# The one exception is roles/billing.creator. Google grants it to the
# whole domain when an organization is created. This stage resets it to the
# billing admins group, as Cloud Setup does, or to no one when the billing
# account belongs to another organization.
#
# Moving an existing deployment to this file: removing an exact-members
# binding from the configuration empties that role. Before the first plan,
# drop those bindings from state so Terraform forgets them instead:
#
#   terraform state list \
#     | grep 'module.organization.google_organization_iam_binding.authoritative' \
#     | grep -v 'roles/billing.creator' \
#     | while read -r a; do terraform state rm "$a"; done
#
# The next apply adds each member, and leaves every other member as it is.

locals {
  # IAM roles in the org to reset to the members set below
  iam_delete_roles = [
    "roles/billing.creator"
  ]
  # domain IAM bindings
  iam_domain_bindings = var.organization.domain == null ? {} : {
    "domain:${var.organization.domain}" = {
      authoritative = []
      additive      = ["roles/browser"]
    }
  }
  # human (groups) IAM bindings; authoritative lists feed iam_by_principals
  iam_principal_bindings = {
    (local.principals.gcp-billing-admins) = {
      authoritative = local.billing_mode != "org" ? [] : ["roles/billing.creator"]
      additive = (
        local.billing_mode != "org" ? [] : [
          "roles/billing.admin"
        ]
      )
    }
    (local.principals.gcp-vpc-network-admins) = {
      authoritative = []
      additive = [
        "roles/cloudasset.owner",
        "roles/cloudsupport.techSupportEditor",
        "roles/compute.orgFirewallPolicyAdmin",
        "roles/compute.xpnAdmin"
      ]
    }
    (local.principals.gcp-organization-admins) = {
      authoritative = []
      additive = concat(
        [
          "roles/axt.admin",
          "roles/cloudasset.owner",
          "roles/cloudsupport.admin",
          "roles/iam.organizationRoleAdmin",
          "roles/resourcemanager.folderAdmin",
          "roles/resourcemanager.organizationAdmin",
          "roles/resourcemanager.projectCreator",
          "roles/resourcemanager.tagAdmin",
          "roles/iam.workforcePoolAdmin",
          "roles/assuredworkloads.admin",
          "roles/orgpolicy.policyAdmin"
        ],
        local.billing_mode != "org" ? [] : [
          "roles/billing.admin"
        ]
      )
    }
    (local.principals.gcp-security-admins) = {
      authoritative = []
      additive = [
        "roles/cloudasset.owner",
        "roles/cloudsupport.techSupportEditor",
        "roles/iam.securityReviewer",
        "roles/logging.admin",
        "roles/securitycenter.admin",
        "roles/accesscontextmanager.policyAdmin",
        "roles/iam.organizationRoleAdmin",
        "roles/orgpolicy.policyAdmin"
      ]
    }
    (local.principals.gcp-support) = {
      authoritative = []
      additive = [
        "roles/cloudsupport.techSupportEditor",
        "roles/logging.viewer",
        "roles/monitoring.viewer",
      ]
    }
  }
  # machine (service accounts) IAM bindings, in logical format
  # the service account module's "magic" outputs allow us to use dynamic values
  iam_sa_bindings = {
    (module.automation-tf-bootstrap-sa.iam_email) = {
      authoritative = []
      additive = concat(
        [
          "roles/essentialcontacts.admin",
          "roles/logging.admin",
          "roles/resourcemanager.organizationAdmin",
          "roles/resourcemanager.projectCreator",
          "roles/resourcemanager.projectMover",
          "roles/resourcemanager.tagAdmin",
          "roles/assuredworkloads.admin",
          "roles/iam.organizationRoleAdmin",
          "roles/orgpolicy.policyAdmin"
        ],
        local.billing_mode != "org" ? [] : [
          "roles/billing.admin"
        ]
      )
    }
    (module.automation-tf-bootstrap-r-sa.iam_email) = {
      authoritative = []
      additive = concat(
        [
          "roles/essentialcontacts.viewer",
          "roles/logging.viewer",
          "roles/resourcemanager.folderViewer",
          "roles/resourcemanager.tagViewer",
          "roles/assuredworkloads.reader",
          # the organizationAdminViewer custom role is granted via the SA module
          "roles/iam.organizationRoleViewer",
          "roles/orgpolicy.policyViewer"
        ],
        local.billing_mode != "org" ? [] : [
          "roles/billing.viewer"
        ]
      )
    }
    (module.automation-tf-resman-sa.iam_email) = {
      authoritative = []
      additive = concat(
        [
          "roles/assuredworkloads.admin",
          "roles/logging.admin",
          "roles/resourcemanager.folderAdmin",
          "roles/resourcemanager.projectCreator",
          "roles/resourcemanager.tagAdmin",
          "roles/resourcemanager.tagUser",
          "roles/orgpolicy.policyAdmin"
        ],
        local.billing_mode != "org" ? [] : [
          "roles/billing.admin"
        ]
      )
    }
    (module.automation-tf-resman-r-sa.iam_email) = {
      authoritative = []
      additive = concat(
        [
          "roles/assuredworkloads.reader",
          "roles/logging.viewer",
          "roles/resourcemanager.folderViewer",
          "roles/resourcemanager.tagViewer",
          "roles/serviceusage.serviceUsageViewer",
          # the organizationAdminViewer custom role is granted via the SA module
          "roles/orgpolicy.policyViewer"
        ],
        local.billing_mode != "org" ? [] : [
          "roles/billing.viewer"
        ]
      )
    }
  }
  # bootstrap user bindings
  iam_user_bootstrap_bindings = var.bootstrap_user == null ? {} : {
    "user:${var.bootstrap_user}" = {
      authoritative = []
      # TODO: align additive roles with the README
      additive = concat(
        [
          "roles/logging.admin",
          "roles/resourcemanager.folderAdmin",
          "roles/resourcemanager.organizationAdmin",
          "roles/resourcemanager.projectCreator",
          "roles/resourcemanager.tagAdmin",
          "roles/iam.organizationRoleAdmin"
        ],
        local.billing_mode != "org" ? [] : [
          "roles/billing.admin"
        ]
      )
    }
  }
}
