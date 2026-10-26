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

"""Tests for resolving preflight inputs from flags and config.env."""

import pydantic
import pytest

import conftest
from stellar_engine.preflight import inputs
from stellar_engine.preflight import regions

CONFIG_ENV = f"""
BILLING_ACCOUNT={conftest.BILLING}
BOOTSTRAP_PROJECT_ID={conftest.PROJECT}
COMPLIANCE_REGIME=fedramp_high
DIRECTORY_CUSTOMER_ID={conftest.CUSTOMER_ID}
DEPLOYER_EMAIL_ADDRESS={conftest.USER}
FULLY_QUALIFIED_DOMAIN_NAME={conftest.DOMAIN}
ORGANIZATION_ID={conftest.ORG_ID}
PREFIX=abc
REGION=us-east4
TENANT_NAME=
"""


@pytest.fixture
def config_env(tmp_path):
    path = tmp_path / "config.env"
    path.write_text(CONFIG_ENV, encoding="utf-8")
    return path


def test_config_env_mapping(config_env):
    values = inputs.load_config_env(config_env)
    assert values == {
        "billing_account": conftest.BILLING,
        "bootstrap_project": conftest.PROJECT,
        "regime": "fedramp_high",
        "customer_id": conftest.CUSTOMER_ID,
        "domain": conftest.DOMAIN,
        "org_id": conftest.ORG_ID,
        "prefix": "abc",
        "region": "us-east4",
    }


def test_shipped_sample_keys_are_known(repo):
    sample = repo.root / "scripts/config.env.sample"
    keys = {
        line.split("=", 1)[0].removeprefix("export ").strip()
        for line in sample.read_text(encoding="utf-8").splitlines()
        if "=" in line and not line.lstrip().startswith("#")
    }
    assert set(inputs.CONFIG_ENV_KEYS) <= keys


def test_flags_override_config_env(config_env):
    resolved = inputs.resolve({"prefix": "xyz", "region": None}, config_env)
    assert resolved.prefix == "xyz"
    assert resolved.region == "us-east4"
    assert resolved.regime == regions.Regime.FEDRAMP_HIGH


def test_flags_only():
    resolved = inputs.resolve({"org_id": "42", "regime": "il5"})
    assert resolved.org_id == "42"
    assert resolved.regime == regions.Regime.IL5
    assert resolved.groups == {}


@pytest.mark.parametrize(
    "flags",
    [
        {"org_id": "org-1"},
        {"billing_account": "nope"},
        {"bootstrap_project": "UPPER"},
        {"regime": "il-5"},
    ],
)
def test_invalid_values(flags):
    with pytest.raises(pydantic.ValidationError):
        inputs.resolve(flags)


def test_repo_accepts_every_regime_mapping_value(repo):
    for regime in ("CJIS", "IL5", "COMPLIANCE_REGIME_UNSPECIFIED"):
        inputs.validate_against_repo(inputs.resolve({"regime": regime}), repo)


def test_repo_rejects_unknown_regime(repo):
    with pytest.raises(ValueError, match="Unknown regime PCI"):
        inputs.validate_against_repo(inputs.resolve({"regime": "PCI"}), repo)


def test_repo_rejects_unknown_group_key(repo):
    resolved = inputs.resolve({"groups": {"gcp-devops": "a", "nope": "b"}})
    with pytest.raises(ValueError, match="Unknown group keys nope"):
        inputs.validate_against_repo(resolved, repo)


def test_missing_config_env(tmp_path):
    with pytest.raises(FileNotFoundError):
        inputs.load_config_env(tmp_path / "missing.env")
