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

"""Command line entry point for the `stellar` command."""

import os
import pathlib
from typing import Annotated

import pydantic
from rich import console as rich_console
import typer

import stellar_engine
from stellar_engine import repo as repo_lib
from stellar_engine import tools as tools_lib
from stellar_engine.gcp import live
from stellar_engine.preflight import checks
from stellar_engine.preflight import inputs as inputs_lib
from stellar_engine.preflight import report
from stellar_engine.preflight import runner

app = typer.Typer(
    help="Validate and guide Stellar Engine deployments.",
    no_args_is_help=True,
    pretty_exceptions_show_locals=False,
)

_EXIT_USAGE = 2


def _version_callback(value):
    if value:
        typer.echo(f"stellar {stellar_engine.__version__}")
        raise typer.Exit


@app.callback()
def main(
    _version: Annotated[
        bool,
        typer.Option(
            "--version",
            callback=_version_callback,
            is_eager=True,
            help="Show the version and exit.",
        ),
    ] = False,
):
    """Validate and guide Stellar Engine deployments."""


def _parse_groups(values):
    groups = {}
    for value in values or []:
        key, sep, name = value.partition("=")
        if not sep or not key or not name:
            raise typer.BadParameter(
                f"Expected KEY=NAME, got {value!r}.", param_hint="--group"
            )
        groups[key] = name
    return groups


@app.command()
def preflight(
    org: Annotated[
        str | None,
        typer.Option(envvar="STELLAR_ORG_ID", help="Organization ID."),
    ] = None,
    billing_account: Annotated[
        str | None,
        typer.Option(
            envvar="STELLAR_BILLING_ACCOUNT", help="Billing account ID."
        ),
    ] = None,
    billing_no_iam: Annotated[
        bool,
        typer.Option(
            "--billing-no-iam",
            envvar="STELLAR_BILLING_NO_IAM",
            help=(
                "Match a Stage 0 billing_account.no_iam of true: require "
                "only the permission to link projects to the billing account."
            ),
        ),
    ] = False,
    project: Annotated[
        str | None,
        typer.Option(
            envvar="STELLAR_BOOTSTRAP_PROJECT", help="Bootstrap project ID."
        ),
    ] = None,
    prefix: Annotated[
        str | None,
        typer.Option(envvar="STELLAR_PREFIX", help="Resource name prefix."),
    ] = None,
    regime: Annotated[
        str | None,
        typer.Option(
            envvar="STELLAR_REGIME",
            help="Compliance regime, for example IL5 or FEDRAMP_HIGH.",
        ),
    ] = None,
    region: Annotated[
        str | None,
        typer.Option(envvar="STELLAR_REGION", help="Primary region."),
    ] = None,
    domain: Annotated[
        str | None,
        typer.Option(envvar="STELLAR_DOMAIN", help="Organization domain."),
    ] = None,
    customer_id: Annotated[
        str | None,
        typer.Option(
            envvar="STELLAR_CUSTOMER_ID", help="Directory customer ID."
        ),
    ] = None,
    bootstrap_user: Annotated[
        str | None,
        typer.Option(
            envvar="STELLAR_BOOTSTRAP_USER",
            help=(
                "User account email for the first Stage 0 apply's "
                "bootstrap_user. Defaults to the signed-in user."
            ),
        ),
    ] = None,
    group: Annotated[
        list[str] | None,
        typer.Option(
            help=(
                "Override a Stage 0 group as KEY=NAME, for example "
                "gcp-devops=platform-devops. Repeatable."
            ),
        ),
    ] = None,
    config_env: Annotated[
        pathlib.Path | None,
        typer.Option(
            help="Read unset values from a scripts/config.env file.",
            exists=True,
            dir_okay=False,
        ),
    ] = None,
    redeploy: Annotated[
        bool,
        typer.Option(
            "--redeploy",
            help="Report resources that already use the prefix as WARN.",
        ),
    ] = False,
    output_json: Annotated[
        bool, typer.Option("--json", help="Print results as JSON.")
    ] = False,
    strict: Annotated[
        bool, typer.Option("--strict", help="Exit non-zero on warnings too.")
    ] = False,
    repo: Annotated[
        pathlib.Path | None,
        typer.Option(help="Stellar Engine checkout to read. Auto-detected."),
    ] = None,
):
    """Check the deployment prerequisites from docs/ddg.md.

    Preflight only reads. It validates local tools, the signed-in identity,
    organization roles, billing, the bootstrap project, administrative groups,
    the prefix and region, and risks in a shared organization.
    """
    flags = {
        "org_id": org,
        "billing_account": billing_account,
        "billing_no_iam": billing_no_iam,
        "bootstrap_project": project,
        "prefix": prefix,
        "regime": regime,
        "region": region,
        "domain": domain,
        "customer_id": customer_id,
        "groups": _parse_groups(group),
        "bootstrap_user": bootstrap_user,
        "redeploy": redeploy,
    }
    err_console = rich_console.Console(stderr=True)
    try:
        resolved = inputs_lib.resolve(flags, config_env)
        repository = repo_lib.Repo(repo_lib.find_root(repo))
        inputs_lib.validate_against_repo(resolved, repository)
    except (pydantic.ValidationError, repo_lib.RepoError, ValueError) as error:
        err_console.print(f"[bold red]Error:[/] {error}")
        raise typer.Exit(_EXIT_USAGE) from error
    ctx = checks.Context(
        inputs=resolved,
        cloud=live.LiveCloudApi(),
        tools=tools_lib.SystemTools(),
        repo=repository,
        environ=os.environ,
    )
    if output_json:
        results = runner.run(ctx)
        typer.echo(report.render_json(results, resolved))
    else:
        with err_console.status("Running preflight checks..."):
            results = runner.run(ctx)
        report.render_table(rich_console.Console(), results)
    raise typer.Exit(runner.exit_code(results, strict=strict))
