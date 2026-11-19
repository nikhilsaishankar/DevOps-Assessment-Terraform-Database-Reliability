# Convenience wrapper. Every target maps to a command in the README, so the
# README stays the source of truth and nothing here is required to review the
# repository.

SHELL := /bin/bash
.DEFAULT_GOAL := help

ENV ?= dev
TF  := terraform -chdir=infra/envs/$(ENV)

.PHONY: help
help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
	  | awk 'BEGIN {FS = ":.*?## "} {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

# --- database ---------------------------------------------------------------

.PHONY: up
up: ## Start the local PostgreSQL (runs migrations + seed on first boot)
	docker compose up -d
	@echo "waiting for initialisation..."
	@until docker compose exec -T db pg_isready -U $${POSTGRES_USER:-hotels_admin} -d $${POSTGRES_DB:-hotels} -q; do sleep 2; done
	@echo "ready. seed summary:"
	@docker compose logs db | grep -A12 'seed complete' || true

.PHONY: down
down: ## Stop the database, keep the data volume
	docker compose down

.PHONY: clean
clean: ## Stop the database and delete the data volume (forces re-seed next up)
	docker compose down -v

.PHONY: psql
psql: ## Open an interactive psql session
	docker compose exec db psql -U $${POSTGRES_USER:-hotels_admin} -d $${POSTGRES_DB:-hotels}

.PHONY: profile
profile: ## Show what the seed produced
	docker compose exec -T db psql -U $${POSTGRES_USER:-hotels_admin} -d $${POSTGRES_DB:-hotels} -f /queries/04_data_profile.sql

.PHONY: explain
explain: ## Compare the target query's plan with and without the covering index
	./scripts/explain.sh

.PHONY: backup
backup: ## Create a timestamped dump in backups/
	./scripts/backup.sh

.PHONY: restore
restore: ## Restore the latest dump into a fresh database and verify it
	./scripts/restore.sh --force

.PHONY: drill
drill: ## Full backup/restore drill: backup, restore, verify
	./scripts/backup.sh --label drill
	./scripts/restore.sh --force

# --- terraform --------------------------------------------------------------

.PHONY: fmt
fmt: ## Format all Terraform files
	terraform fmt -recursive infra/

.PHONY: fmt-check
fmt-check: ## Check Terraform formatting without writing
	terraform fmt -check -recursive -diff infra/

.PHONY: init
init: ## terraform init for ENV (default dev)
	$(TF) init

.PHONY: validate
validate: ## terraform validate for ENV
	$(TF) validate

.PHONY: plan
plan: ## terraform plan for ENV, no AWS account needed
	$(TF) plan -refresh=false -lock=false -var plan_only=true

.PHONY: tf-check
tf-check: fmt-check ## Run the full Terraform review loop for both environments
	@for e in dev prod; do \
	  echo "=== $$e ==="; \
	  terraform -chdir=infra/envs/$$e init -backend=false -no-color >/dev/null; \
	  terraform -chdir=infra/envs/$$e validate -no-color; \
	  terraform -chdir=infra/envs/$$e plan -refresh=false -lock=false -var plan_only=true -no-color | grep -E '^(Plan:|No changes)'; \
	done

.PHONY: check
check: tf-check ## Everything a reviewer runs: Terraform checks, then the database drill
	$(MAKE) up
	$(MAKE) explain
	$(MAKE) drill
