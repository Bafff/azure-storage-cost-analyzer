---
description: Analyze recent code changes and update documentation accordingly
---

Analyze recent code changes and update documentation accordingly.

## Step 1: Analyze Changes

Run `git diff --name-only HEAD~10..HEAD` to see recently changed files.

Group changes by type:

- Configuration: `*.conf`, `*.conf.example`, `.env*` files
- Core scripts: `azure-storage-cost-analyzer.sh`
- Test scripts: `tests/test-*.sh`
- Templates: `templates/zabbix-template-*.yaml`, `templates/zabbix-template-*.xml`
- Validation: `templates/validate-zabbix-template.py`
- Pipeline: `.pipelines/*.yml`, `.github/workflows/*.yml`
- Docs: `docs/*.md`, `README.md`

## Step 2: Identify Required Updates

For each changed file, determine what docs need updating:

**If configuration files changed (`*.conf.example`, `.env*`):**

- Must update: `README.md` (Configuration section)
- May update: `docs/QuickStartGuide.md` (setup instructions)
- May update: `docs/ServicePrincipalSetup.md` (if auth-related)

**If main script changed (`azure-storage-cost-analyzer.sh`):**

- Must update: `README.md` (Quick Usage section)
- May update: `docs/QuickStartGuide.md`
- Consider: `docs/UnusedResourcesGuide.md` if core logic changed

**If Zabbix templates changed (`templates/zabbix-template-*.yaml`):**

- Must update: `docs/ZabbixIntegrationGuide.md`
- May update: `docs/ZabbixTemplateAuthoring.md`
- May update: `docs/ZabbixSetup.md`

**If validation script changed (`templates/validate-zabbix-template.py`):**

- Must update: `docs/ZabbixValidationTools.md`
- May update: `docs/ZabbixTemplateAuthoring.md`

**If test scripts changed (`tests/test-*.sh`):**

- May update: `docs/TestResults.md`
- Consider: `README.md` (Tests section)

**If pipeline changed (`.pipelines/*.yml`, `.github/workflows/*.yml`):**

- May update: `README.md` (Pipeline section)
- May update: `docs/GithubMigrationGuide.md`
- Consider: `docs/Linting.md` if CI/CD linting changed

**If tag exclusion logic changed:**

- Must update: `docs/TagExclusionImplementation.md`
- May update: `README.md` (Key Features)

## Step 3: Check Current Doc Status

For configuration changes:

- Read variables from `azure-storage-monitor.conf.example`
- Check if `README.md` mentions these variables in Configuration section
- Check if `docs/QuickStartGuide.md` has correct setup instructions

For script changes:

- Check command-line flags in `azure-storage-cost-analyzer.sh`
- Compare with "Quick Usage" examples in `README.md`
- Ensure all flags are documented

For Zabbix changes:

- Check template items/triggers in `templates/zabbix-template-azure-storage-monitor-7.0.yaml`
- Verify `docs/ZabbixIntegrationGuide.md` documents all metrics
- Check `docs/ZabbixTemplateAuthoring.md` for authoring guidance

## Step 4: Present Analysis

Show me:

```markdown
## 📋 Documentation Update Analysis

### Files Changed (last 10 commits)

- `azure-storage-cost-analyzer.sh` - 3 commits
- `templates/zabbix-template-azure-storage-monitor-7.0.yaml` - 2 commits
- `docs/ZabbixTemplateAuthoring.md` - 1 commit

### Required Updates

**Priority 1 (Critical)**:

- [ ] Update `README.md` - new command-line flag added
- [ ] Update `docs/ZabbixIntegrationGuide.md` - new metric added

**Priority 2 (Important)**:

- [ ] Update `docs/QuickStartGuide.md` - usage example outdated
- [ ] Update `docs/ImplementationStatus.md` - feature status changed

**Priority 3 (Nice to have)**:

- [ ] Update `docs/TestResults.md` - test coverage expanded

### Proposed Changes

**README.md**:
Add `--new-flag` to Quick Usage section

**docs/ZabbixIntegrationGuide.md**:
Document new `azure.storage.new.metric` item

**docs/QuickStartGuide.md**:
Update example command with new flag

Do you want me to make these updates?
```

## Step 5: Make Updates

After showing analysis and getting confirmation, make the necessary documentation updates.

## Step 6: Summary

Report what was updated:

```
✅ Updated README.md
✅ Updated docs/ZabbixIntegrationGuide.md
✅ Updated docs/QuickStartGuide.md
✅ Consider running `/doc-verify` to confirm all updates
```

This command systematically analyzes recent git changes and identifies which documentation files need updates based on code changes. It looks at the last 10 commits and provides a prioritized list of documentation updates.
