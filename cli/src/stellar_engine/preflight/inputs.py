# Copyright 2026 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Inputs for preflight checks and the loaders that resolve them.

Values come from command-line flags or `STELLAR_*` environment variables,
which Typer resolves, and then from an optional `scripts/config.env` file
that `scripts/deploy.sh` users already have. Flags always win.
"""

import pathlib

import dotenv
import pydantic

# Maps scripts/config.env keys to PreflightInputs fields.
CONFIG_ENV_KEYS = {
    "BILLING_ACCOUNT": "billing_account",
    "BOOTSTRAP_PROJECT_ID": "bootstrap_project",
    "COMPLIANCE_REGIME": "regime",
    "DIRECTORY_CUSTOMER_ID": "customer_id",
    "FULLY_QUALIFIED_DOMAIN_NAME": "domain",
    "ORGANIZATION_ID": "org_id",
    "PREFIX": "prefix",
    "REGION": "region",
}


class PreflightInputs(pydantic.BaseModel):
    """Deployment values that preflight checks validate against.

    Every field is optional. A check whose inputs are missing reports SKIP
    and names the flag that enables it.
    """

    model_config = pydantic.ConfigDict(extra="forbid", frozen=True)

    org_id: str | None = pydantic.Field(default=None, pattern=r"^[0-9]+$")
    billing_account: str | None = pydantic.Field(
        default=None, pattern=r"^[A-Z0-9]{6}-[A-Z0-9]{6}-[A-Z0-9]{6}$"
    )
    billing_no_iam: bool = False
    bootstrap_project: str | None = pydantic.Field(
        default=None, pattern=r"^[a-z][a-z0-9-]{4,28}[a-z0-9]$"
    )
    prefix: str | None = None
    regime: str | None = pydantic.Field(default=None, pattern=r"^[A-Z0-9_]+$")
    region: str | None = None
    domain: str | None = None
    customer_id: str | None = None
    bootstrap_user: str | None = pydantic.Field(
        default=None, pattern=r"^[^@\s]+@[^@\s]+\.[^@\s]+$"
    )
    groups: dict[str, str] = pydantic.Field(default_factory=dict)
    redeploy: bool = False


def load_config_env(path):
    """Reads PreflightInputs fields from a `scripts/config.env` file.

    Args:
        path: Path of the file, in the `KEY=value` format of
            `scripts/config.env.sample`.

    Returns:
        A dict of PreflightInputs field names to non-empty string values.

    Raises:
        FileNotFoundError: If the file does not exist.
    """
    path = pathlib.Path(path)
    if not path.is_file():
        raise FileNotFoundError(path)
    values = dotenv.dotenv_values(path)
    found = {
        field: (values.get(key) or "").strip()
        for key, field in CONFIG_ENV_KEYS.items()
    }
    return {field: value for field, value in found.items() if value}


def resolve(flags, config_env=None):
    """Merges flag values with an optional config.env file.

    Args:
        flags: Field values from the command line or environment. None means
            the operator did not set the value.
        config_env: Optional path of a `scripts/config.env` file whose values
            fill fields that flags leave unset.

    Returns:
        A validated PreflightInputs.

    Raises:
        pydantic.ValidationError: If a value has an invalid format.
        FileNotFoundError: If config_env does not exist.
    """
    merged = load_config_env(config_env) if config_env else {}
    merged.update({key: value for key, value in flags.items() if value})
    if isinstance(merged.get("regime"), str):
        merged["regime"] = merged["regime"].upper()
    return PreflightInputs.model_validate(merged)


def validate_against_repo(inputs, repo):
    """Rejects values that the Stage 0 variables would also reject.

    Args:
        inputs: Resolved PreflightInputs.
        repo: The `repo.Repo` whose Stage 0 variables define valid values.

    Raises:
        ValueError: If the regime is not in `regime_mapping`, or a group key
            is not a field of the Stage 0 `groups` variable.
    """
    regimes = repo.regime_names()
    if inputs.regime and inputs.regime not in regimes:
        raise ValueError(
            f"Unknown regime {inputs.regime}. Stage 0 accepts: "
            + ", ".join(regimes)
        )
    known = set(repo.default_groups())
    unknown = sorted(set(inputs.groups) - known)
    if unknown:
        raise ValueError(
            f"Unknown group keys {', '.join(unknown)}. Stage 0 accepts: "
            + ", ".join(sorted(known))
        )
