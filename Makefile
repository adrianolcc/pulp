# PULP developer commands. Run `make help` for the list.

PY_PACKAGES := common testkit sim edge historian mes_lite analytics integration \
               robot_lite onboarding ai
COMPOSE_FILE := deploy/compose.yaml
COMPOSE := docker compose -f $(COMPOSE_FILE) --env-file .env
# Compose profiles to start: core, enterprise, robot, robot-lite, ai (comma-separated).
PROFILES ?= core

.DEFAULT_GOAL := help
.PHONY: help setup sync lint fmt typecheck test up down logs

help: ## Show this help
	@grep -hE '^[a-zA-Z%_-]+:.*## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*## "}; {printf "  %-14s %s\n", $$1, $$2}'

setup: sync ## First-time setup: install packages and the git pre-commit hook
	uv run pre-commit install

sync: ## Install every workspace package and the dev tools into .venv
	uv sync --all-packages

lint: ## Ruff lint, ruff format check and mypy (what CI runs)
	uv run ruff check .
	uv run ruff format --check .
	@$(MAKE) --no-print-directory typecheck

# mypy runs once per package: each package's tests/ folder is a set of loose
# modules, and two packages with the same test file name would collide in a
# single mypy run.
typecheck: ## mypy in strict mode, one package at a time
	@set -e; for p in $(PY_PACKAGES); do echo "mypy $$p"; uv run mypy $$p; done

fmt: ## Apply ruff fixes and formatting
	uv run ruff check --fix .
	uv run ruff format .

test: ## Unit and contract tests (fast; excludes layer and storyline tests)
	uv run pytest -m "not layer and not storyline"

up: _require-compose ## Start the stack: make up PROFILES=core,enterprise
	COMPOSE_PROFILES=$(PROFILES) $(COMPOSE) up -d --wait

down: _require-compose ## Stop the stack (all profiles)
	COMPOSE_PROFILES='*' $(COMPOSE) down

logs: _require-compose ## Follow logs: make logs [SERVICE=name]
	COMPOSE_PROFILES='*' $(COMPOSE) logs -f $(SERVICE)

storyline-%: ## Run one storyline headless: make storyline-a (A to F)
	@case "$*" in a|b|c|d|e|f) ;; *) echo "Unknown storyline '$*'; use a to f." >&2; exit 2;; esac
	@echo "Storyline $* has no test yet; storyline tests arrive with the packages that make them pass." >&2
	@exit 1

.PHONY: _require-compose
_require-compose:
	@test -f $(COMPOSE_FILE) || { echo "$(COMPOSE_FILE) does not exist yet (WP-02)." >&2; exit 1; }
	@test -f .env || { echo "No .env file: run 'cp .env.example .env' and edit it." >&2; exit 1; }
