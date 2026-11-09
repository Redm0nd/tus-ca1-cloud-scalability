.PHONY: help preflight build deploy seed smoke up down stop start \
        metric-none metric-cpu metric-request evidence destroy nuke lint \
        loadgen-up loadgen-run loadgen-shell loadgen-results loadgen-down load-local summary dashboard

SH := bash

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

preflight: ## Check aws profile + required tooling
	@$(SH) scripts/preflight.sh

lint: ## cfn-lint all templates (eu-west-1)
	cfn-lint infra/*.yaml --regions eu-west-1

build: ## Build both JARs and upload artifacts + seed SQL to S3
	@$(SH) scripts/build-and-upload.sh

deploy: ## Package + deploy the root stack (uses config.env / inline overrides)
	@$(SH) scripts/deploy.sh

seed: ## Seed SEED_ROWS product rows into RDS via SSM
	@$(SH) scripts/seed.sh

smoke: ## End-to-end smoke test through the ALB
	@$(SH) scripts/smoke-test.sh

up: build deploy seed smoke ## Full bring-up: build -> deploy -> seed -> smoke

metric-none:    ## Fixed capacity (baseline / scaling runs)
	@$(SH) scripts/set-scaling-metric.sh None
metric-cpu:     ## Elasticity on CPU target-tracking
	@$(SH) scripts/set-scaling-metric.sh CPU
metric-request: ## Elasticity on ALBRequestCountPerTarget
	@$(SH) scripts/set-scaling-metric.sh RequestCount

stop: ## Manually stop everything (save credit)
	@$(SH) scripts/power.sh stop
start: ## Manually start everything
	@$(SH) scripts/power.sh start

evidence: ## Collect evidence window: make evidence LABEL=baseline MINS=30
	@$(SH) scripts/fetch-evidence.sh $(LABEL) $(MINS)

loadgen-up: ## Create the in-region k6 load generator (separate stack)
	@$(SH) scripts/loadgen.sh up
loadgen-run: ## k6 on the load-gen: make loadgen-run LABEL=baseline SCRIPT=read-heavy.js ARGS="-e VUS_PEAK=20"
	@$(SH) scripts/loadgen.sh run $(LABEL) $(SCRIPT) $(ARGS)
loadgen-shell: ## SSM shell on the load generator
	@$(SH) scripts/loadgen.sh shell
loadgen-results: ## Pull load-gen k6 results into evidence/raw/loadgen/
	@$(SH) scripts/loadgen.sh results
loadgen-down: ## Delete the load generator (after every test window)
	@$(SH) scripts/loadgen.sh down

load-local: ## k6 from this machine: make load-local LABEL=A-local SCRIPT=read-heavy.js ARGS="-e VUS_PEAK=20"
	@mkdir -p evidence/raw/local/$(LABEL)
	@date -u +%Y-%m-%dT%H:%M:%SZ > evidence/raw/local/$(LABEL)/start-utc.txt
	-k6 run -e BASE_URL=$$(bash -c 'source scripts/lib.sh; stack_output AlbUrl') $(ARGS) \
	  --summary-export evidence/raw/local/$(LABEL)/summary.json experiments/load/$(SCRIPT) \
	  2>&1 | tee evidence/raw/local/$(LABEL)/console.log
	@date -u +%Y-%m-%dT%H:%M:%SZ > evidence/raw/local/$(LABEL)/end-utc.txt

summary: ## Summarise a run over its steady state: make summary LABEL=A-baseline-lg [FROM=3 TO=12]
	@$(SH) scripts/summarise-run.sh $(LABEL) $(or $(FROM),3) $(or $(TO),12)

dashboard: ## CloudWatch dashboard CA1-evidence + per-experiment links
	@$(SH) scripts/dashboard.sh

destroy: ## Delete the whole solution (keeps deploy bucket)
	@$(SH) scripts/destroy.sh

nuke: ## Delete everything including the deploy bucket
	@$(SH) scripts/destroy.sh --purge-deploy-bucket
