# Stellar Engine CLI

The `stellar` command verifies that your workstation, identity, and Google
Cloud organization meet the prerequisites in the
[Detailed Deployment Guide](../docs/ddg.md) before you deploy Stage 0.

## 1 Install the CLI

The `cli/` project uses [uv](https://docs.astral.sh/uv/) to install the
Python version and the dependencies that `cli/pyproject.toml` declares, so you
do not install Python yourself.

- Install uv by following the
  [uv installation guide](https://docs.astral.sh/uv/getting-started/installation/).
- Run the command from the repository root with
  `uv run --project cli stellar --help`.
- Install the command on your `PATH` with `uv tool install ./cli` if you
  prefer to run `stellar` directly.

## 2 Run preflight

Preflight only reads from Google Cloud and never changes a resource, so you
can run it as often as you like.

```bash
gcloud auth login
gcloud auth application-default login
uv run --project cli stellar preflight \
  --org 123456789012 \
  --billing-account 000000-AAAAAA-BBBBBB \
  --project my-bootstrap-project \
  --prefix abc \
  --regime IL5 \
  --region us-east4
```

- Each flag also reads an environment variable, such as `STELLAR_ORG_ID` for
  the `--org` flag.
- The `--config-env scripts/config.env` flag reads values from an existing
  `scripts/deploy.sh` configuration file, and explicit flags override it.
- The `--group gcp-devops=platform-ops` flag checks a renamed Stage 0 group
  and accepts repeats.
- A check whose inputs you omit reports `skip` and names the flag that
  enables it.
- The `--json` flag prints machine-readable results for automation.
- The command exits with status 1 when a check fails, and the `--strict` flag
  also fails the run on warnings.

## 3 Read the results

Each check reports one status, and every failure or warning includes a fix
and a link to the matching documentation.

| Status | Meaning |
| --- | --- |
| `pass` | Preflight verified the prerequisite. |
| `warn` | Review a risk that does not block Stage 0. |
| `fail` | Fix a missing prerequisite that blocks Stage 0. |
| `manual` | Confirm the prerequisite yourself. |
| `skip` | Pass the inputs that the check needs. |

## 4 Checks performed

Preflight follows the order of the DDG prerequisites section.

- Terraform meets the highest `required_version` floor that the modules under
  `modules/` declare, and the Google Cloud SDK and jq are installed.
- The active gcloud account matches the Application Default Credentials
  identity that Terraform uses.
- A user account is available for the `bootstrap_user` variable, because
  Stage 0 grants it as a `user:` principal. The signed-in user serves by
  default, and the `--bootstrap-user` flag names another user when
  Terraform runs as a service account.
- The active gcloud project is the bootstrap project.
- The organization exists, and its domain and directory customer ID match the
  values you pass.
- The deploying identity holds every role that
  `fast/stages-aw/0-bootstrap/setIAM.yaml.sample` grants. The check tests
  effective permissions with `testIamPermissions`, so it accepts direct,
  group, and inherited grants alike.
- The billing account is open, the deploying identity holds Billing Account
  Administrator on it, and the bootstrap project bills to it.
- The `--billing-no-iam` flag matches a Stage 0 `billing_account` input with
  `no_iam = true`, so Stage 0 never manages billing IAM. Preflight then skips
  the Billing Account Administrator check and tests only the
  `billing.resourceAssociations.create` permission that links new projects
  to the billing account.
- The bootstrap project is active and has every API that
  `fast/stages-aw/0-bootstrap/enableServices.sh` enables, plus the Cloud
  Monitoring API that the DDG requires.
- The Stage 0 administrative groups exist in Cloud Identity, resolved from
  the `groups` variable the same way Stage 0 resolves them.
- The region supports the compliance regime according to the
  [Assured Workloads locations](https://cloud.google.com/assured-workloads/docs/locations)
  page, and the regime appears in the Stage 0 `regime_mapping` variable.
- The prefix is valid, and no project, state bucket, or Assured Workloads
  folder that Stage 0 creates already exists with that prefix.
- No soft-deleted project still holds a project ID that Stage 0 creates,
  because a deleted project keeps its ID for 30 days.
- Organization-wide custom roles, custom constraints, and log sinks that
  Stage 0 creates do not exist yet.
- The organization IAM policy lists every existing grant that the first
  Stage 0 apply removes. For each role that `organization-iam.tf` manages
  authoritatively, preflight compares the current members with the members
  that Stage 0 keeps on that role.
- Super Admin status, Access Transparency, and project quota appear as manual
  confirmations because no API exposes them to the deploying identity.

## 5 Required access

Preflight needs read access to the resources it checks, which the DDG roles
already include.

- Your Application Default Credentials need a quota project with the Cloud
  Resource Manager, IAM, Cloud Billing, Service Usage, Cloud Identity, Cloud
  Logging, and Organization Policy APIs enabled.
- A disabled API reports the exact `gcloud services enable` command to run.
- Terraform can run as a service account, because Stage 0 only needs a user
  account for the `bootstrap_user` variable. Pass that user's email with the
  `--bootstrap-user` flag, and use the same value for
  `-var bootstrap_user` on the first Stage 0 apply.
- The `--redeploy` flag downgrades existing prefix resources to warnings when
  you rerun preflight against your own earlier deployment.

## 6 Develop the CLI

The `cli/` project follows the
[Google Python Style Guide](https://google.github.io/styleguide/pyguide.html)
with the ruff settings in `cli/pyproject.toml`.

- Install the development environment with `uv sync` in the `cli/`
  directory.
- Run the tests with `uv run pytest`.
- Format and lint the code with `uv run ruff format` and `uv run ruff check`.
- Check types with `uv run pyright`.
- Unit tests replace Google Cloud with in-memory fakes, so they never touch
  the network.
- Sync tests in `cli/tests/test_repo.py` read the repository and the DDG, so
  they fail when the documentation and the code drift apart.
