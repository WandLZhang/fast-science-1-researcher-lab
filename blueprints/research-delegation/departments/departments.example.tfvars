###############################################################################
# blueprints/research-delegation/departments/departments.example.tfvars
#
# Template overlay for delegating folder + project creation to academic
# departments / colleges / PIs while keeping IT in control of guardrails.
#
# How to use:
#   1. Copy this file into:
#        fast/stages-aw/1-resman/
#      (rename it however you like; the *.auto.tfvars suffix is what matters)
#
#   2. Replace every <PLACEHOLDER> below with values for your institution.
#
#   3. Apply:
#        cd fast/stages-aw/1-resman
#        terraform plan      # review the diff
#        terraform apply
#
# What gets created (per departments entry):
#   * Folder: <descriptive_name>                    (parent = dept_folder_parent:
#                                                    the org root, or the AW
#                                                    folder for a compliance regime)
#   * Folder: <descriptive_name>/Development
#   * Folder: <descriptive_name>/Production
#   * Tag:    department=<key>                      (bound to the department folder)
#   * SA:     <prefix>-prod-teams-<key>-0           (in the automation project)
#   * GCS:    <prefix>-prod-teams-<key>-0           (Terraform state for this team)
#
# IAM granted automatically by branch-edu.tf:
#   On the department folder, to prod-teams-<key>-0 SA:
#     - roles/owner
#     - roles/logging.admin
#     - roles/resourcemanager.folderAdmin
#     - roles/resourcemanager.projectCreator
#     - roles/compute.xpnAdmin
#   On prod-teams-<key>-0 SA, to impersonation_principals:
#     - roles/iam.serviceAccountTokenCreator
#   On the organization, to department_admin_principals:
#     - roles/orgpolicy.policyAdmin, with an IAM condition that matches only
#       resources tagged department=<key>
#
# IAM granted via this overlay (iam_by_principals):
#   On the department folder, to the PI Google Group:
#     - roles/resourcemanager.folderViewer
#     - roles/resourcemanager.projectCreator
#     - roles/resourcemanager.folderCreator   (so PIs can make their own subfolders)
#   On the department folder, to the department admin group (chair / IT liaison):
#     - roles/resourcemanager.folderAdmin
#
# Why the tag-conditioned orgpolicy.policyAdmin grant?
#   The org policies in `../org-policies/` are intentionally a BASELINE applied
#   on each department folder. Department admins can OVERRIDE any of them at
#   their own folder or project scope (e.g., a sandbox project that needs a
#   public IP can loosen `compute.vmExternalIpAccess`). orgpolicy.policyAdmin
#   can only be granted on the organization, so the IAM condition limits it to
#   the department's subtree. The two project templates in
#   `../project-templates/` show both directions: sandbox-project.yaml.sample
#   loosens the baseline; hardened-project.yaml.sample re-enforces it locally
#   plus adds extra controls.
#
# What this overlay does NOT do (handled by sibling blueprint dirs):
#   * Baseline org policies on each department folder — see ../org-policies/
#   * Master billing.user grants                      — see ../billing/
#   * Auto-lien Eventarc + CF                         — see ../auto-lien/
###############################################################################

# The project factory service accounts get rights on each department's
# Development and Production folders. This block replaces fast_features from
# 0-globals, so keep any other features you use.
fast_features = {
  data_platform   = false
  gcve            = false
  gke             = false
  project_factory = true
  sandbox         = false
}

# Add one entry per academic unit you want to delegate to. The map key is a
# short slug used in resource names (SAs, buckets) and as the department tag
# value; descriptive_name is the display name shown in the Console folder tree.
departments = {

  # Example 1: a college / school
  engineering = {
    descriptive_name = "College of Engineering"
    iam_by_principals = {
      # PIs in the college: can browse the folder, create projects, and create
      # PI-scoped subfolders for their labs.
      "group:engineering-pis@<UNIVERSITY_DOMAIN>" = [
        "roles/resourcemanager.folderViewer",
        "roles/resourcemanager.projectCreator",
        "roles/resourcemanager.folderCreator",
      ]
      # Department / college admin: full folder admin within this subtree
      # (can move projects, set IAM).
      "group:engineering-admins@<UNIVERSITY_DOMAIN>" = [
        "roles/resourcemanager.folderAdmin",
      ]
    }
    # Members of these groups can impersonate the team SA, which is the
    # auditable path for "I created this on behalf of the department."
    impersonation_principals = [
      "group:engineering-admins@<UNIVERSITY_DOMAIN>",
      "group:engineering-pis@<UNIVERSITY_DOMAIN>",
    ]
    # Org policy admin for this department's subtree only. Add the PI group
    # too if PIs should manage their own policy exceptions.
    department_admin_principals = [
      "group:engineering-admins@<UNIVERSITY_DOMAIN>",
    ]
    # Folder-level presets from branch-edu.tf: loose Development, strict
    # Production. Leave one out to keep the baseline unchanged there.
    dev_org_policies_preset  = "sandbox"
    prod_org_policies_preset = "hardened"
    # cicd block omitted; uncomment and fill in if you want a per-team
    # GitHub/GitLab CI workflow to manage projects via PR.
  }

  # Example 2: a research institute / center spanning multiple colleges
  computational-sciences = {
    descriptive_name = "Institute for Computational Sciences"
    iam_by_principals = {
      "group:cs-pis@<UNIVERSITY_DOMAIN>" = [
        "roles/resourcemanager.folderViewer",
        "roles/resourcemanager.projectCreator",
        "roles/resourcemanager.folderCreator",
      ]
      "group:cs-admins@<UNIVERSITY_DOMAIN>" = [
        "roles/resourcemanager.folderAdmin",
      ]
    }
    impersonation_principals = [
      "group:cs-admins@<UNIVERSITY_DOMAIN>",
      "group:cs-pis@<UNIVERSITY_DOMAIN>",
    ]
    department_admin_principals = [
      "group:cs-admins@<UNIVERSITY_DOMAIN>",
    ]
    dev_org_policies_preset  = "sandbox"
    prod_org_policies_preset = "hardened"
  }

  # Add more departments here as you onboard them. Each entry is independent;
  # adding a new one does not affect existing ones.
}
