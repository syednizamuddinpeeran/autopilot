# AWS (`--cloud aws`)

For projects that deploy to AWS. The rule is simple: **agents never hold AWS credentials and never change AWS**. They write and test infrastructure code (`cdk synth`, `terraform plan` without credentials, unit tests); a human merges; CI deploys with short-lived credentials.

```bash
./install.sh ~/code/my-repo --repo github --cloud aws      # combine with --os / --assistant as usual
```

## What `--cloud aws` adds

| Layer | What | Where |
|---|---|---|
| Guard: commands | Credential handling (`aws configure`, `aws sso login`, `sts assume-role`, `secretsmanager get-secret-value`, `ssm … --with-decryption`, `kms decrypt`, `ecr get-login-password`, `aws-vault`), IAM changes, mutating AWS CLI verbs (`run-`, `start-`, `invoke`, `put-`, … on top of core's `create-`/`delete-`/…), `aws s3 cp/mv/rm/sync`, `cloudformation deploy`, and the deploy tools: CDK, SAM, Serverless, Amplify, Elastic Beanstalk, AWS Copilot, Terraform/OpenTofu/Terragrunt, Chalice, Zappa | `deny-commands.txt` (appended) |
| Guard: paths | `~/.aws/credentials`, `~/.aws/config`, SSO and CLI caches, `.boto`, `.s3cfg`, `.awsvault/` (read and write) | `deny-paths.txt` (appended) |
| Local runs | `run-issue` / `run-task` refuse to start while `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`, `AWS_PROFILE` and related variables are set, and warn when `~/.aws/credentials` exists | `FORBIDDEN_ENV` in `commands.env`, checked by `agent-cli` |
| Deploy (GitHub repos) | `deploy-aws.yml`: on push to `main`, `production` environment, OIDC role, verify then deploy | `.github/workflows/` |
| Tests | Allowed: `cdk synth`, `cdk diff`, `terraform plan`, `aws … describe-*`. Denied: each rule above | `hook-cases.txt` (appended) |

Read-only AWS CLI calls (`describe-*`, `list-*`, `get-*` apart from secrets) are not blocked, but without credentials they fail anyway — which is the point.

## Set up deploys (GitHub repos)

Follow GitHub's guide, [Configuring OpenID Connect in Amazon Web Services](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws):

1. **AWS:** add the GitHub OIDC identity provider (`token.actions.githubusercontent.com`, audience `sts.amazonaws.com`).
2. **AWS:** create a deploy role. Trust policy condition (`StringEquals`):
   ```json
   "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
   "token.actions.githubusercontent.com:sub": "repo:<OWNER>/<REPO>:environment:production"
   ```
   Binding the role to the `production` *environment* (not to any branch or `repo:<OWNER>/<REPO>:*`) means only jobs that pass that environment's protection rules can assume it. Give the role only what the deploy needs (for CDK, the bootstrap roles it assumes).
3. **GitHub:** create the `production` environment: required reviewers, deployment branches = `main` only, no self-review. Add environment variables `AWS_ROLE_ARN` and `AWS_REGION` (they are not secrets).
4. Fill in the deploy step in `.github/workflows/deploy-aws.yml` (`npx cdk deploy --all --require-approval never`, `sam deploy …`, `terraform apply -auto-approve`).
5. Add `deploy-aws.yml` to `CODEOWNERS`. Agents already cannot edit workflows (guard), and `guardrails-unchanged` fails agent PRs that touch them.

Never:
- add AWS keys as **Agents** secrets/variables (Copilot cloud agent), to the Claude action's workflow, or to `copilot-setup-steps.yml`;
- use long-lived access keys for CI — OIDC replaces them;
- trust `repo:<OWNER>/<REPO>:*` or `pull_request` in the role: agent branches would then be able to deploy.

## Local repos (`--repo local`)

There is no CI. Keep the same split: agents work without credentials; you deploy from your own shell after `accept.sh`, with credentials the agent's environment never had. Use the CLI sandbox to deny `~/.aws` ([sandboxing.md](sandboxing.md)).

## Plans and diffs

`cdk synth` needs no credentials. `cdk diff` and `terraform plan` against real accounts do; run them yourself, or in a separate CI job with a **read-only** role bound to its own environment — never in jobs that agent branches trigger without approval.

## Limits

- Pattern lists are a speed bump: a script the agent writes can still call the AWS SDK. Without credentials in the environment, that call fails — keeping credentials out is the real control.
- Copilot cloud agent and the Claude action run on GitHub's runners, which may have an instance identity on self-hosted runners in AWS. Use GitHub-hosted runners for agents, or runners with no instance role.
