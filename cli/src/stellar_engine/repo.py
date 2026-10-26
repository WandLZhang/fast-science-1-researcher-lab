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

"""Reads deployment facts from the Stellar Engine repository.

The CLI never duplicates lists that already live in the repository, such as
the roles granted by `setIAM.sh` or the APIs enabled by `enableServices.sh`.
This module parses those files so that the CLI and the manual flow in
`docs/ddg.md` always agree.
"""

import dataclasses
import enum
import functools
import json
import pathlib
import re

import hcl2
from packaging import version
import yaml

BOOTSTRAP_DIR = pathlib.Path("fast/stages-aw/0-bootstrap")

_SERVICES_RE = re.compile(r'^list_of_services="([^"]+)"', re.MULTILINE)
_PREFIX_LIMIT_RE = re.compile(r"length\(var\.prefix\),\s*0\)\s*<=\s*(\d+)")
_GROUP_DEFAULT_RE = re.compile(
    r'([\w-]+)\s*=\s*optional\(string,\s*"([^"]+)"\)'
)
# python-hcl2 returns a conditional such as `cond ? {} : { ... }` as one
# expression string, so the map literal in its else branch is parsed again.
_CONDITIONAL_MAP_RE = re.compile(
    r"^\$\{.*?\?\s*\{\}\s*:\s*(\{.*\})\}$", re.DOTALL
)
_HOLDER_KEY_RE = re.compile(
    r"^(?:\$\{\(local\.principals\.(?P<group>[\w-]+)\)\}"
    r"|\$\{\(module\.(?P<module>[\w-]+)\.iam_email\)\}"
    r"|(?P<user>user):\$\{var\.bootstrap_user\}"
    r"|(?P<domain>domain):\$\{var\.organization\.domain\})$"
)
_VERSION_FLOOR_RE = re.compile(r">=\s*([0-9.]+)")


class RepoError(Exception):
    """Raised when the repository layout does not match expectations."""


class HolderKind(enum.StrEnum):
    """Kinds of principal that Stage 0 binds to organization roles."""

    GROUP = "group"
    SERVICE_ACCOUNT = "serviceAccount"
    BOOTSTRAP_USER = "bootstrapUser"
    DOMAIN = "domain"


@dataclasses.dataclass(frozen=True)
class Holder:
    """A principal that Stage 0 binds to an organization role.

    Attributes:
        kind: Kind of principal.
        key: Group key such as `gcp-devops`, or service account name such as
            `bootstrap-0`. None for the bootstrap user and the domain.
    """

    kind: HolderKind
    key: str | None = None


def _unquote(value):
    """Strips the HCL quoting that python-hcl2 keeps on strings and labels."""
    if isinstance(value, str) and value.startswith('"') and value.endswith('"'):
        return json.loads(value)
    return value


def _load_hcl(path):
    with path.open(encoding="utf-8") as handle:
        return hcl2.load(handle)


def _literal_map(value, name):
    """Returns a parsed HCL map, unwrapping a `cond ? {} : {...}` value.

    Raises:
        RepoError: If the value is neither a map nor that conditional.
    """
    if isinstance(value, dict):
        return value
    match = _CONDITIONAL_MAP_RE.match(value) if isinstance(value, str) else None
    if not match:
        raise RepoError(f"Cannot read local.{name} as a map")
    return hcl2.loads(f"value = {match.group(1)}")["value"]


def find_root(start=None):
    """Finds the Stellar Engine repository root.

    Args:
        start: Directory to start searching from. Defaults to the current
            working directory, then the location of this package.

    Returns:
        The repository root path.

    Raises:
        RepoError: If no directory containing `fast/stages-aw` is found.
    """
    candidates = [pathlib.Path(start) if start else pathlib.Path.cwd()]
    candidates.append(pathlib.Path(__file__).resolve())
    for candidate in candidates:
        for directory in [candidate, *candidate.parents]:
            if (directory / "fast" / "stages-aw").is_dir():
                return directory
    raise RepoError(
        "Cannot find the Stellar Engine repository root. Run the command "
        "from inside a checkout or pass --repo."
    )


@dataclasses.dataclass(frozen=True)
class Repo:
    """Read-only view of the deployment facts stored in the repository.

    Attributes:
        root: Path of the repository root.
    """

    root: pathlib.Path

    @property
    def bootstrap_dir(self):
        """Returns the Stage 0 bootstrap directory."""
        return self.root / BOOTSTRAP_DIR

    @functools.cached_property
    def _bootstrap_variables(self):
        parsed = _load_hcl(self.bootstrap_dir / "variables.tf")
        variables = {}
        for block in parsed.get("variable", []):
            for name, body in block.items():
                variables[_unquote(name)] = body
        return variables

    def required_roles(self):
        """Returns the organization roles that `setIAM.sh` grants.

        Returns:
            Role names in file order, for example `roles/owner`.
        """
        path = self.bootstrap_dir / "setIAM.yaml.sample"
        policy = json.loads(path.read_text(encoding="utf-8"))
        return [binding["role"] for binding in policy["bindings"]]

    def required_apis(self):
        """Returns the APIs that `enableServices.sh` enables.

        Returns:
            Fully qualified service names such as `iam.googleapis.com`.

        Raises:
            RepoError: If the service list cannot be found in the script.
        """
        script = (self.bootstrap_dir / "enableServices.sh").read_text(
            encoding="utf-8"
        )
        match = _SERVICES_RE.search(script)
        if not match:
            raise RepoError("Cannot find list_of_services in enableServices.sh")
        return [f"{name}.googleapis.com" for name in match.group(1).split()]

    def prefix_max_length(self):
        """Returns the prefix length limit from the Stage 0 validation block.

        Raises:
            RepoError: If the validation block cannot be found.
        """
        text = (self.bootstrap_dir / "variables.tf").read_text(encoding="utf-8")
        match = _PREFIX_LIMIT_RE.search(text)
        if not match:
            raise RepoError("Cannot find the prefix length validation")
        return int(match.group(1))

    def default_groups(self):
        """Returns the default group names from the Stage 0 `groups` type.

        Returns:
            A mapping of group key to group name, for example
            `{"gcp-support": "gcp-devops"}`.
        """
        group_type = self._bootstrap_variables["groups"]["type"]
        return dict(_GROUP_DEFAULT_RE.findall(group_type))

    def regime_names(self):
        """Returns the compliance regimes in the Stage 0 `regime_mapping`."""
        default = self._bootstrap_variables["regime_mapping"].get("default", {})
        return sorted(_unquote(name) for name in default)

    def log_sink_names(self):
        """Returns the default organization log sink names."""
        default = self._bootstrap_variables["log_sinks"].get("default", {})
        return sorted(_unquote(name) for name in default)

    def custom_role_ids(self):
        """Returns the organization custom role IDs that Stage 0 creates.

        A role file without a `name` key falls back to its file name, which
        matches how the organization module names it.
        """
        role_ids = []
        for path in sorted(
            (self.bootstrap_dir / "data/custom-roles").glob("*.yaml")
        ):
            data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
            role_ids.append(data.get("name") or path.stem)
        return role_ids

    def custom_constraint_names(self):
        """Returns the organization custom constraint names Stage 0 creates."""
        names = []
        directory = self.bootstrap_dir / "data/custom-constraint-policies"
        for path in sorted(directory.glob("*.yaml")):
            data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
            names.extend(data)
        return names

    def _module_names(self, filename):
        """Maps each module in a Stage 0 file to its `name` argument."""
        names = {}
        for block in _load_hcl(self.bootstrap_dir / filename).get("module", []):
            for label, body in block.items():
                if "name" in body:
                    names[_unquote(label)] = _unquote(body["name"])
        return names

    def automation_service_accounts(self):
        """Maps Stage 0 automation service account modules to their names.

        Returns:
            For example `{"automation-tf-bootstrap-sa": "bootstrap-0"}`. The
            account email is `<prefix>-prod-<name>@<prefix>-prod-iac-core-0`.
        """
        return {
            module: name
            for module, name in self._module_names("automation.tf").items()
            if module.endswith("-sa")
        }

    def stage0_project_names(self):
        """Returns the names of the projects Stage 0 creates.

        The project ID is `<prefix>-prod-<name>`.
        """
        names = [self._module_names("automation.tf")["automation-project"]]
        names.append(self._module_names("log-export.tf")["log-export-project"])
        names.append(self._module_names("billing.tf")["billing-export-project"])
        return names

    def authoritative_bindings(self):
        """Returns the principals Stage 0 keeps on each authoritative role.

        Stage 0 removes every other principal from these roles on its first
        apply, as defined in `organization-iam.tf`. Roles in
        `iam_delete_roles` keep no principal at all.

        Returns:
            A dict of role to a set of `Holder` values.

        Raises:
            RepoError: If a binding refers to an unknown principal or service
                account, or a binding local is not a map.
        """
        local_values = {}
        path = self.bootstrap_dir / "organization-iam.tf"
        for block in _load_hcl(path).get("locals", []):
            local_values.update(block)
        accounts = self.automation_service_accounts()
        bindings = {}
        for name, value in local_values.items():
            if not name.endswith("_bindings"):
                continue
            for key, body in _literal_map(value, name).items():
                holder = self._holder(_unquote(key), accounts)
                roles = body.get("authoritative", [])
                if not isinstance(roles, list):
                    raise RepoError(f"Cannot read the roles of {key}")
                for role in roles:
                    bindings.setdefault(_unquote(role), set()).add(holder)
        for role in local_values.get("iam_delete_roles", []):
            bindings[_unquote(role)] = set()
        return bindings

    @staticmethod
    def _holder(key, accounts):
        """Returns the Holder for an `organization-iam.tf` binding key."""
        match = _HOLDER_KEY_RE.match(key)
        if not match:
            raise RepoError(f"Unknown principal {key}")
        if match.group("group"):
            return Holder(HolderKind.GROUP, match.group("group"))
        if match.group("module"):
            module = match.group("module")
            if module not in accounts:
                raise RepoError(f"Unknown service account {module}")
            return Holder(HolderKind.SERVICE_ACCOUNT, accounts[module])
        if match.group("user"):
            return Holder(HolderKind.BOOTSTRAP_USER)
        return Holder(HolderKind.DOMAIN)

    def authoritative_org_roles(self):
        """Returns organization roles that Stage 0 manages authoritatively."""
        return sorted(self.authoritative_bindings())

    def min_terraform_version(self):
        """Returns the highest Terraform `required_version` floor of modules.

        Stages pull in many modules, so the effective minimum is the highest
        `>=` constraint declared under `modules/*/versions.tf`.

        Raises:
            RepoError: If no module declares a `>=` constraint.
        """
        floors = []
        for path in (self.root / "modules").glob("*/versions.tf"):
            for block in _load_hcl(path).get("terraform", []):
                constraint = _unquote(block.get("required_version", ""))
                floors.extend(
                    version.Version(found)
                    for found in _VERSION_FLOOR_RE.findall(constraint)
                )
        if not floors:
            raise RepoError("No module declares a required_version floor")
        return str(max(floors))
