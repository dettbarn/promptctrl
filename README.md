# promptctrl

Control your local system prompts, skills, etc. for different agents in one place, while maintaining version history and backups automatically.

## Setup

1. Create "dev" versions of your system prompts, e.g.:

```bash
cd promptctrl
touch opencode-agents-dev.md
touch copilot-global-dev.md
```

2. Create configuration JSON and link your "prod" versions there, e.g.:

```bash
touch promptctrl.json
```

```json
{
  "opencode": {
    "dev": "./opencode-agents-dev.md",
    "prod": "path/to/your/opencode/config/AGENTS.md"
  },
  "copilot": {
    "dev": "./copilot-global-dev.md",
    "prod": "path/to/your/github-copilot/config/global-copilot-instructions.md"
  }
}
```

3. Now you're set up. ✅ From now on, all you have to do is `make deploy` to update all your "prod" system prompts. Backups will be created in the backup subfolder.
