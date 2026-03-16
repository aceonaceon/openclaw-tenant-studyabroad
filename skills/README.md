# Shared Skills

Place your shared skills here. Each skill should be in its own directory.

These skills are baked into the Docker image and loaded via `skills.load.extraDirs` in openclaw.json. All tenants share the same skills from the image.

## Adding a new skill

1. Create a directory: `skills/my-skill-name/`
2. Add the skill files per OpenClaw skill format
3. Rebuild the Docker image: `docker build -f docker/Dockerfile -t lobster-base .`
4. Run `scripts/update-all.sh` to roll out to all tenants

## Skill priority

OpenClaw loads skills in this order (highest priority first):
1. Workspace skills (tenant-specific, not used in this setup)
2. Managed/local skills
3. Bundled skills
4. extraDirs skills (this folder — lowest priority)
