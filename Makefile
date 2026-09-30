.PHONY: deploy

# Usage: make deploy [DRY_RUN=1]
deploy:
	@./deploy.sh $(if $(DRY_RUN),--dry-run)
