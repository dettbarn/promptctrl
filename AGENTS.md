# promptctrl

Shell tool to organize and deploy AI prompts

## Stack

**Languages:**
- Bash (100%)

## Commands

```bash
make test  # test
make deploy  # deploy
```

## Conventions

- **Naming**: mixed
- **File organization**: flat

## Architecture

**Key directories:**
- `backup/`
- `tests/` - Test files

## Boundaries

**Always:**
- Run `make test` before committing changes

**Ask first:**
- Adding new dependencies
- Changing project configuration files

**Never:**
- Commit secrets, API keys, or .env files
- Delete or overwrite test files without understanding them
- Force push to main/master branch

<!-- agentseed:meta {"sha":"33db0c353f743fe59eea83df577a5c91861efef9","timestamp":"2026-11-23T15:26:08.255Z","format":"agentseed-v1"} -->
