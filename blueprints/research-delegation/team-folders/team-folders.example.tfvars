###############################################################################
# blueprints/research-delegation/team-folders/team-folders.example.tfvars
#
# Template overlay for delegating folder + project creation to academic
# departments / colleges / PIs while keeping IT in control of guardrails.
#
# How to use:
#   1. Copy this file into:
#        fast-science-1-researcher-lab/fast/stages-aw/1-resman/
#      (rename it however you like; the *.auto.tfvars suffix is what matters)
#
#   2. Replace every <PLACEHOLDER> below with values for your institution.
#
#   3. Apply:
#        cd fast-science-1-researcher-lab/fast/stages-aw/1-resman
#        terraform plan      # review the diff
#        terraform apply
#
# What gets created (per team_folders entry):
#   * Folder: Teams                                 (parent = AW folder)
#   * Folder: Teams/<descriptive_name>              (the department folder)
#   * Folder: Teams/<descriptive_name>/Development
#   * Folder: Teams/<descriptive_name>/Production
#   * SA:     <prefix>-prod-teams-<key>-0           (in the automation project)
#   * GCS:    <prefix>-prod-teams-<key>-0           (Terraform state for this team)
#
# IAM granted automatically by branch-teams.tf:
#   On the department folder, to prod-teams-<key>-0 SA:
#     - roles/owner
#     - roles/logging.admin
#     - roles/resourcemanager.folderAdmin
#     - roles/resourcemanager.projectCreator
#     - roles/compute.xpnAdmin
#   On prod-teams-<key>-0 SA, to impersonation_principals:
#     - roles/iam.serviceAccountTokenCreator
#
# IAM granted via this overlay (iam_by_principals + folder_iam):
#   On the department folder, to the PI Google Group:
#     - roles/resourcemanager.folderViewer
#     - roles/resourcemanager.projectCreator
#     - roles/resourcemanager.folderCreator   (so PIs can make their own subfolders)
#     - roles/orgpolicy.policyAdmin           (so PIs can override inherited
#                                              org policies on their own folders
#                                              / projects, e.g. for sandbox use)
#   On the department folder, to the department admin group (chair / IT liaison):
#     - roles/resourcemanager.folderAdmin
#     - roles/orgpolicy.policyAdmin           (department-wide policy overrides)
#   On the Teams parent folder, to each team SA:
#     - roles/resourcemanager.lienModifier    (so the auto-lien CF can place liens)
#
# Why the orgpolicy.policyAdmin grants?
#   The org policies in `../org-policies/` are intentionally a BASELINE applied
#   at the Teams folder. PIs and dept admins can OVERRIDE any of them at their
#   own folder or project scope (e.g., a sandbox project that needs a public IP
#   can loosen `compute.vmExternalIpAccess`). The two project templates in
#   `../project-templates/` show both directions: sandbox-project.yaml.sample
#   loosens the baseline; hardened-project.yaml.sample re-enforces it locally
#   plus adds extra controls.
#
# What this overlay does NOT do (handled by sibling blueprint dirs):
#   * Org policies on the Teams folder — see ../org-policies/
#   * Master billing.user grants     — see ../billing/
#   * Auto-lien Eventarc + CF        — see ../auto-lien/
###############################################################################

fast_features = {
  data_platform   = false
  gcve            = false
  gke             = false
  project_factory = true
  sandbox         = false
  teams           = true   # enables the team_folders branch in 1-resman
}

# Add one entry per academic unit you want to delegate to. The map key is a
# short slug used in resource names (SAs, buckets); descriptive_name is the
# display name shown in the Console folder tree.
team_folders = {

  # Example 1: a college / school
  engineering = {
    descriptive_name = "College of Engineering"
    iam_by_principals = {
      # PIs in the college: can browse the folder, create projects, create
      # PI-scoped subfolders for their labs, AND override org policies on
      # their own folders/projects (e.g., loosen `compute.vmExternalIpAccess`
      # for a specific lab that needs a public-facing demo VM).
      "group:engineering-pis@<UNIVERSITY_DOMAIN>" = [
        "roles/resourcemanager.folderViewer",
        "roles/resourcemanager.projectCreator",
        "roles/resourcemanager.folderCreator",
        "roles/orgpolicy.policyAdmin",
      ]
      # Department / college admin: full folder admin within this subtree
      # (can move projects, set IAM, manage org-policy exceptions).
      # orgpolicy.policyAdmin lets them tighten OR loosen any policy
      # inherited from the Teams folder for their entire department.
      "group:engineering-admins@<UNIVERSITY_DOMAIN>" = [
        "roles/resourcemanager.folderAdmin",
        "roles/orgpolicy.policyAdmin",
      ]
    }
    # Members of these groups can impersonate the team SA, which is the
    # auditable path for "I created this on behalf of the department."
    impersonation_principals = [
      "group:engineering-admins@<UNIVERSITY_DOMAIN>",
      "group:engineering-pis@<UNIVERSITY_DOMAIN>",
    ]
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
        "roles/orgpolicy.policyAdmin",
      ]
      "group:cs-admins@<UNIVERSITY_DOMAIN>" = [
        "roles/resourcemanager.folderAdmin",
        "roles/orgpolicy.policyAdmin",
      ]
    }
    impersonation_principals = [
      "group:cs-admins@<UNIVERSITY_DOMAIN>",
      "group:cs-pis@<UNIVERSITY_DOMAIN>",
    ]
  }

  # Add more departments here as you onboard them. Each entry is independent;
  # adding a new one does not affect existing ones.
}

# Extend the Teams parent folder IAM with lien-modifier rights for each team SA.
# branch-teams.tf merges var.folder_iam.teams with its hardcoded SA roles, so
# this only adds; it does not replace the FAST-managed bindings.
#
# The auto-lien Cloud Function (../auto-lien/) impersonates the team SA to place
# liens on Console-created projects — that's why the SA needs lienModifier on
# the parent folder (so the lien permission cascades into all team subfolders).
folder_iam = {
  teams = {
    "roles/resourcemanager.lienModifier" = [
      # One entry per team_folders key above. Replace <PREFIX> with the prefix
      # you chose at L0 Stage 0, and <AUTOMATION_PROJECT> with the value of
      # output `automation_project_id` from L0 Stage 0 (typically
      # <PREFIX>-prod-iac-core-0).
      "serviceAccount:<PREFIX>-prod-teams-engineering-0@<AUTOMATION_PROJECT>.iam.gserviceaccount.com",
      "serviceAccount:<PREFIX>-prod-teams-computational-sciences-0@<AUTOMATION_PROJECT>.iam.gserviceaccount.com",
    ]
  }
}
