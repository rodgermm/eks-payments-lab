CLUSTER     ?= eks-payments-lab
REGION      ?= eu-west-1
GITHUB_USER ?= rodgermm
REPO        ?= eks-payments-lab
TF          := terraform -chdir=terraform

.PHONY: init plan apply kubeconfig bootstrap status loadtest canary-fail destroy local

init:        ## terraform init
	$(TF) init

plan:        ## terraform plan
	$(TF) plan

apply:       ## create VPC, EKS, Karpenter, ECR, OIDC role (~15-20 min)
	$(TF) apply

kubeconfig:  ## point kubectl at the cluster
	aws eks update-kubeconfig --region $(REGION) --name $(CLUSTER)

bootstrap:   ## install Flux and connect it to this repo (needs GITHUB_TOKEN)
	flux bootstrap github --owner=$(GITHUB_USER) --repository=$(REPO) \
	  --branch=main --path=clusters/lab --personal

status:      ## quick health view
	flux get kustomizations
	flux get helmreleases -A
	kubectl get nodepools,nodeclaims
	kubectl argo rollouts get rollout payments -n payments || true

loadtest:    ## run k6 in-cluster, then watch scaling
	kubectl -n payments create configmap k6-script --from-file=loadtest/k6.js \
	  --dry-run=client -o yaml | kubectl apply -f -
	kubectl delete job k6-loadtest -n payments --ignore-not-found
	kubectl apply -f loadtest/k6-job.yaml
	@echo "Watch: kubectl get pods -n payments -w | kubectl get nodeclaims -w"
	@echo "Logs:  kubectl logs -n payments job/k6-loadtest -f"

local:       ## run the API locally on :8080
	cd app && pip install -r requirements.txt && uvicorn main:app --port 8080 --reload

destroy:     ## remove Karpenter nodes FIRST, then infra (avoids orphaned EC2)
	-flux suspend kustomization --all
	-kubectl delete nodepools --all
	-kubectl wait --for=delete nodeclaims --all --timeout=5m
	$(TF) destroy
