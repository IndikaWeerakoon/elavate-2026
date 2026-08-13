# engineering-incident-agent

OpenClaw gateway host: EC2 `t4g.medium` (ARM64, Ubuntu 22.04), provisioned with
Terraform, configured with Ansible. Read-only AWS investigation identity via
instance profile — same `incident-agent-poc-*` scope as `synthetic-sync-platform`.

## Infra lifecycle (Terraform, via GitHub Actions)

Same OIDC deploy role as `synthetic-sync-platform`, reuses the same Terraform
state backend (different state key). No push-trigger — EC2 is stateful, so
apply/destroy are manual only.

- **Create**: run the `openclaw-infra-apply` workflow, supplying your current
  public IP as `ssh_ingress_cidr` (e.g. `1.2.3.4/32`). SSH is the only open
  ingress port; the gateway port (18789) is never exposed publicly.
- **Destroy**: run `openclaw-infra-destroy`, typing `destroy` to confirm.

Locally (same AWS SSO profile used for `synthetic-sync-platform`):

```
cd infrastructure
terraform init
terraform plan -var="ssh_ingress_cidr=$(curl -s https://checkip.amazonaws.com)/32"
```

Note: applying IAM instance-profile changes may fail under a restrictive SSO
role (`iam:TagInstanceProfile` denied) — that's expected; the CI deploy role
has the permissions your interactive session doesn't. Run apply via the
workflow in that case.

## SSH key

A dedicated key pair `incident-agent-poc-openclaw` was created out-of-band
(not via Terraform, to keep the private key out of tfstate):

```
aws ec2 create-key-pair --key-name incident-agent-poc-openclaw --region us-east-1 \
  --query 'KeyMaterial' --output text > ~/.ssh/elavate-2026/incident-agent-poc-openclaw.pem
chmod 600 ~/.ssh/elavate-2026/incident-agent-poc-openclaw.pem
```

## Provisioning (Ansible)

Run from a machine with SSH access to the box (the private key above):

```
cd ansible
./generate-inventory.sh   # writes inventory.ini from terraform output
ansible-playbook playbook.yml
```

This installs Node.js (via OpenClaw's own installer), OpenClaw itself
(unattended: `--no-prompt --no-onboard`), ripgrep, jq, and AWS CLI v2. It also
clones this repo (for `synthetic-sync-platform`'s source) to
`~/repos/synthetic-sync-platform` and deploys `skills/incident-triage` to
`~/.agents/skills/incident-triage` — one of OpenClaw's skill discovery roots,
independent of whether `openclaw onboard` has run yet.

## The incident-triage skill

`skills/incident-triage/SKILL.md` instructs the agent through the
evidence-gathering procedure: source DynamoDB state → destination DynamoDB
state → CloudWatch logs filtered by correlation ID → map the failing event
to its source file via `config/services.json` → `rg` search the repo for the
exact log/error string → report with citations (log line, DynamoDB item,
file:line). All five tool scripts (`scripts/*.sh`) are read-only, wrapping
the AWS CLI and ripgrep already installed on the box — no extra runtime or
`npm install` needed for the skill itself.

Verify it's discovered (works even before Slack/model onboarding):

```
ssh -i ~/.ssh/elavate-2026/incident-agent-poc-openclaw.pem ubuntu@<public-ip>
openclaw skills list
```

Once onboarding is done and a model is connected, test end-to-end without
Slack:

```
openclaw agent --message "investigate why record-100 is SYNCED but missing from the destination table"
```

## Manual finishing step (not automated — needs a human)

Slack and Anthropic connection use OAuth/device-code flows that can't be
scripted blind. After the playbook finishes:

```
ssh -i ~/.ssh/elavate-2026/incident-agent-poc-openclaw.pem ubuntu@<public-ip>
openclaw onboard --install-daemon
```

Follow the prompts to connect the model, the private Slack workspace, and
install the gateway as a systemd daemon. To reach the Control UI/WebChat
(port 18789, not publicly exposed):

```
ssh -i ~/.ssh/elavate-2026/incident-agent-poc-openclaw.pem -L 18789:localhost:18789 ubuntu@<public-ip>
```

Then open http://localhost:18789 locally.

## IAM

The instance role (`incident-agent-poc-openclaw-ec2`) grants only:
CloudWatch Logs read/query, DynamoDB read on `incident-agent-poc-*` tables,
Lambda/SQS describe, CloudWatch metrics read. No write access to the
pipeline it investigates.
