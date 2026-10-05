.PHONY: deploy test

# Runs deploy.sh copies in throwaway temp sandboxes; never touches dev files, backups or prod paths.
test:
	@bash tests/run.sh

# Usage: make deploy [DRY_RUN=1]
deploy:
	@./deploy.sh $(if $(DRY_RUN),--dry-run)
