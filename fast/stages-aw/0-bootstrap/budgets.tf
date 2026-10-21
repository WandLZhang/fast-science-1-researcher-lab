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

# tfdoc:file:description Billing budgets.

locals {
  # Upstream referenced module.no-compliance-folder, which this fork replaced
  # with module.managed-folder. Both regimes resolve to the same display name,
  # which local.managed_folder_name already computes in main.tf.
  folder_name = local.managed_folder_name
}

module "billing-account-budget" {
  source = "../../../modules/billing-account"
  count  = var.billing_budget_amount != null ? 1 : 0
  id     = var.billing_account.id
  budgets = {
    aw-folder-budget = {
      display_name = "Budget for ${local.folder_name} Folder"
      amount = {
        units = var.billing_budget_amount.amount
      }
      threshold_rules = [
        for t in var.billing_budget_amount.threshold_rules : {
          percent = t
        }
      ]
      filter = {
        resource_ancestors = [
          local.assured_workload_folder
        ]
      }
    }
  }
}
