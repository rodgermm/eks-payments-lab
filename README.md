# eks-payments-lab

A small payments platform on AWS EKS for interview prep. It covers:

1. **Infrastructure:** Terraform VPC + EKS, Karpenter (Spot/On-Demand), Pod Identity, Flux GitOps
2. **CI/CD:** GitHub Actions with OIDC (no AWS keys), Trivy scan, Cosign signing, SBOM, GitOps tag bump, Argo Rollouts canary with automatic rollback
3. **Scale:** KEDA scaling on requests per second, PodDisruptionBudgets, spreading pods across AZs, k6 load test, idempotent payments API

See `docs/architecture.png` for the architecture diagram.

## Prerequisites
`aws` CLI (logged in), `terraform >= 1.6`, `kubectl`, `flux`, `kubectl-argo-rollouts`, `docker`, and a GitHub token in `GITHUB_TOKEN`.

## Run it (about 45 minutes)

```bash
# 0. Push this folder to a new GitHub repo: your-user/eks-payments-lab
cp terraform/terraform.tfvars.example terraform/terraform.tfvars   # set github_repo

# 1. Infrastructure (about 20 min)
make init apply kubeconfig

# 2. Wire up CI
#    GitHub repo → Settings → Variables → AWS_ROLE_ARN = (terraform output github_ci_role_arn)
#    In apps/payments/rollout.yaml, replace ACCOUNT_ID with your AWS account ID
#    Push any change under app/ → CI builds, pushes and bumps the image tag

# 3. GitOps
make bootstrap GITHUB_USER=your-user
make status

# 4. Show scaling
make loadtest
kubectl get pods -n payments -w        # KEDA adds pods
kubectl get nodeclaims -w              # Karpenter adds nodes

# 5. Show an automatic rollback
#    In rollout.yaml set FAIL_RATE to "0.3", commit and push, then run load:
kubectl argo rollouts get rollout payments -n payments --watch
#    The analysis fails, so the canary is aborted and traffic returns to stable

# 6. Tear down (always do this: the NAT gateway and nodes cost money)
make destroy
```

Expect roughly $0.30–0.50 per hour while it's running (EKS control plane + 2× m6i.large + NAT).

## Talking points: what I would change for production

| Lab | Production |
|---|---|
| Single NAT gateway | One NAT per AZ, or centralised egress (CNAT) with CUR/Athena cost visibility |
| Public API endpoint | Private endpoint + VPN/SSM; multi-account setup (Control Tower), SCPs |
| In-memory idempotency store | DynamoDB conditional writes / Postgres UNIQUE constraint; outbox pattern to Kafka/SQS |
| Local state | S3 backend with locking; Atlantis or Spacelift for plan/apply on PRs |
| Action tags | Actions pinned to commit SHAs; Kyverno policy to only admit Cosign-signed images |
| Rollout by replica ratio | Traffic-weighted canary via ALB / Gateway API; analysis on p99 latency too |
| No backups | Velero / AWS Backup; database PITR; regular restore drills |
| Basic metrics | OpenTelemetry tracing, SLOs + burn-rate alerts on payment success rate |
| Manual chaos | AWS FIS experiments: AZ outage, Spot interruption, database failover |

## Layout
```
terraform/            VPC, EKS, Karpenter IAM/SQS/Helm, ECR, GitHub OIDC role
clusters/lab/         Flux entrypoints (infra → apps ordering via dependsOn)
infrastructure/       Karpenter NodePool/EC2NodeClass, Argo Rollouts, KEDA, Prometheus, metrics-server
apps/payments/        Rollout (canary), AnalysisTemplate, KEDA ScaledObject, PDB, ServiceMonitor
app/                  FastAPI payments service (idempotency, /metrics, failure injection)
loadtest/             k6 script + in-cluster Job
.github/workflows/    CI pipeline
docs/                 Architecture + prep-plan diagrams
```
