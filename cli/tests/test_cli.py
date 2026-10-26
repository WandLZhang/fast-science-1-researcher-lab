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

"""Tests for the `stellar` command line."""

import json

import pytest
from typer import testing

import conftest
import stellar_engine
from stellar_engine import cli

BASE_ARGS = [
    "preflight",
    "--org",
    conftest.ORG_ID,
    "--billing-account",
    conftest.BILLING,
    "--project",
    conftest.PROJECT,
    "--prefix",
    "tst",
    "--regime",
    "IL5",
    "--region",
    "us-east4",
    "--repo",
    str(conftest.REPO_ROOT),
]


@pytest.fixture
def fake_cloud(monkeypatch):
    cloud = conftest.FakeCloud()
    monkeypatch.setattr(cli.live, "LiveCloudApi", lambda: cloud)
    monkeypatch.setattr(cli.tools_lib, "SystemTools", conftest.FakeTools)
    for name in ("GOOGLE_IMPERSONATE_SERVICE_ACCOUNT", "STELLAR_PREFIX"):
        monkeypatch.delenv(name, raising=False)
    return cloud


@pytest.fixture
def runner():
    return testing.CliRunner()


def test_version(runner):
    outcome = runner.invoke(cli.app, ["--version"])
    assert outcome.exit_code == 0
    assert stellar_engine.__version__ in outcome.output


def test_preflight_json_passes(runner, fake_cloud):
    outcome = runner.invoke(cli.app, [*BASE_ARGS, "--json"])
    assert outcome.exit_code == 0, outcome.output
    document = json.loads(outcome.stdout)
    assert document["summary"]["fail"] == 0
    assert document["inputs"]["prefix"] == "tst"


def test_preflight_table_fails(runner, fake_cloud):
    fake_cloud.projects = {}
    outcome = runner.invoke(cli.app, BASE_ARGS)
    assert outcome.exit_code == 1
    assert "Bootstrap project" in outcome.stdout


def test_strict_fails_on_warning(runner, fake_cloud):
    fake_cloud.custom_roles = {"tagViewer"}
    assert runner.invoke(cli.app, [*BASE_ARGS, "--json"]).exit_code == 0
    strict = runner.invoke(cli.app, [*BASE_ARGS, "--json", "--strict"])
    assert strict.exit_code == 1


def test_env_vars_are_read(runner, fake_cloud, monkeypatch):
    monkeypatch.setenv("STELLAR_PREFIX", "envpfx")
    args = [arg for arg in BASE_ARGS if arg not in ("--prefix", "tst")]
    outcome = runner.invoke(cli.app, [*args, "--json"])
    assert json.loads(outcome.stdout)["inputs"]["prefix"] == "envpfx"


def test_group_overrides(runner, fake_cloud):
    outcome = runner.invoke(
        cli.app,
        [*BASE_ARGS, "--json", "--group", "gcp-devops=platform-ops"],
    )
    document = json.loads(outcome.stdout)
    assert document["inputs"]["groups"] == {"gcp-devops": "platform-ops"}
    ids = {check["check_id"] for check in document["checks"]}
    assert "groups.platform-ops@example.com" in ids


def test_bad_group_syntax(runner, fake_cloud):
    outcome = runner.invoke(cli.app, [*BASE_ARGS, "--group", "nonsense"])
    assert outcome.exit_code == 2
    assert "KEY=NAME" in outcome.output


@pytest.mark.parametrize(
    ("args", "message"),
    [
        (["--regime", "PCI"], "Unknown regime PCI"),
        (["--group", "gcp-nope=x"], "Unknown group keys gcp-nope"),
    ],
)
def test_values_unknown_to_stage0_exit_2(runner, fake_cloud, args, message):
    outcome = runner.invoke(cli.app, [*BASE_ARGS, *args])
    assert outcome.exit_code == 2
    assert message in outcome.output


def test_invalid_billing_format_exits_2(runner, fake_cloud):
    args = [*BASE_ARGS]
    args[args.index(conftest.BILLING)] = "not-a-billing-id"
    outcome = runner.invoke(cli.app, args)
    assert outcome.exit_code == 2
    assert "billing_account" in outcome.output


def test_config_env(runner, fake_cloud, tmp_path):
    config = tmp_path / "config.env"
    config.write_text("PREFIX=fromenv\nREGION=us-west1\n", encoding="utf-8")
    args = [
        "preflight",
        "--org",
        conftest.ORG_ID,
        "--config-env",
        str(config),
        "--repo",
        str(conftest.REPO_ROOT),
        "--json",
    ]
    document = json.loads(runner.invoke(cli.app, args).stdout)
    assert document["inputs"]["prefix"] == "fromenv"
    assert document["inputs"]["region"] == "us-west1"


def test_billing_no_iam(runner, fake_cloud):
    args = [*BASE_ARGS, "--json", "--billing-no-iam"]
    document = json.loads(runner.invoke(cli.app, args).stdout)
    checks_by_id = {c["check_id"]: c for c in document["checks"]}
    assert document["inputs"]["billing_no_iam"] is True
    assert checks_by_id["billing.link"]["status"] == "pass"
    assert "iam.roles/billing.admin" not in checks_by_id


def test_service_account_with_bootstrap_user(runner, fake_cloud):
    sa = "sa@example-project.iam.gserviceaccount.com"
    fake_cloud.principal = conftest.api.Principal(
        sa, conftest.api.PrincipalKind.SERVICE_ACCOUNT
    )
    args = [*BASE_ARGS, "--json", "--bootstrap-user", "admin@example.com"]
    document = json.loads(runner.invoke(cli.app, args).stdout)
    checks_by_id = {c["check_id"]: c for c in document["checks"]}
    assert checks_by_id["identity.bootstrap_user"]["status"] == "pass"
    assert document["inputs"]["bootstrap_user"] == "admin@example.com"
