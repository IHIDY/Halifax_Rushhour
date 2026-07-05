# ──────────────────────────────────────────────────────────────────────────────
# Halifax Transit Pipeline — One-command deploy / destroy
# Usage:
#   make deploy    →  package lambdas + terraform apply
#   make destroy   →  terraform destroy + clean build artifacts
#   make clean     →  remove local build artifacts only (no AWS changes)
#   make plan      →  package lambdas + terraform plan (dry-run)
# ──────────────────────────────────────────────────────────────────────────────

TERRAFORM_DIR := terraform
INGESTOR_DIR  := lambdas/ingestor
API_DIR       := lambdas/api
BUILD_DIR     := terraform/build

.PHONY: deploy destroy clean plan _package _tf_init

# ── Main targets ──────────────────────────────────────────────────────────────

deploy: _package _tf_init
	@echo "\n>>> Deploying to AWS (ca-central-1)..."
	cd $(TERRAFORM_DIR) && terraform apply -auto-approve
	@echo "\n✓ Deploy complete."
	@cd $(TERRAFORM_DIR) && terraform output api_endpoint

destroy:
	@echo "\n>>> Destroying all AWS resources..."
	cd $(TERRAFORM_DIR) && terraform destroy -auto-approve
	@$(MAKE) clean
	@echo "\n✓ Destroy complete. No AWS resources remain."

plan: _package _tf_init
	@echo "\n>>> Dry-run (no changes applied)..."
	cd $(TERRAFORM_DIR) && terraform plan

clean:
	@echo ">>> Cleaning build artifacts..."
	rm -rf $(BUILD_DIR)
	# Remove pip-installed packages from lambda dirs (keep *.py and requirements.txt)
	find $(INGESTOR_DIR) -mindepth 1 \
	    ! -name "*.py" ! -name "requirements.txt" \
	    -exec rm -rf {} + 2>/dev/null || true
	find $(API_DIR) -mindepth 1 \
	    ! -name "*.py" ! -name "requirements.txt" \
	    -exec rm -rf {} + 2>/dev/null || true
	@echo "✓ Clean done."

# ── Internal steps ────────────────────────────────────────────────────────────

_package:
	@echo "\n>>> Packaging Lambda dependencies..."
	mkdir -p $(BUILD_DIR)

	@echo "  [1/2] Ingestor Lambda — installing gtfs-realtime-bindings + protobuf"
	pip install \
	    --quiet \
	    -r $(INGESTOR_DIR)/requirements.txt \
	    -t $(INGESTOR_DIR)

	@echo "  [2/2] API Lambda — no extra deps (boto3 built into Lambda runtime)"
	@echo "✓ Packaging done."

_tf_init:
	@echo "\n>>> Initializing Terraform..."
	cd $(TERRAFORM_DIR) && terraform init -upgrade -input=false
	@echo "✓ Terraform ready."
