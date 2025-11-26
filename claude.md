# Claude Agent Guide

This document provides guidance for AI agents (Claude) working on the Azure Storage Cost Analyzer project.

## Project Overview

This is a Bash-based Azure storage cost analysis tool that:
- Scans Azure subscriptions for unattached disks and snapshots
- Calculates costs using Azure Cost Management API
- Integrates with Zabbix for monitoring and alerting
- Supports multi-subscription scanning with tag-based exclusions
- Runs in Azure DevOps pipelines for automated monitoring

## Key Technologies

- **Language**: Bash scripting
- **Cloud**: Azure (Azure CLI, Azure Cost Management API)
- **Monitoring**: Zabbix (metrics, LLD, templates)
- **CI/CD**: Azure Pipelines, GitHub Actions
- **Validation**: Python (for Zabbix template validation)
- **Linting**: shellcheck, yamllint

## Project Structure

```
.
├── azure-storage-cost-analyzer.sh       # Main analyzer script
├── azure-storage-cost-analyzer.conf.example   # Configuration template
├── .pipelines/                          # CI/CD pipelines
│   └── azure-pipelines-storage-cost-analyzer.yml
├── templates/                           # Zabbix templates and validation
│   ├── zabbix-template-*.yaml
│   └── validate-zabbix-template.py
├── tests/                               # Test scripts
│   └── test-*.sh
├── docs/                                # Documentation
│   ├── QuickStartGuide.md              # Getting started
│   ├── ZabbixIntegrationGuide.md       # Zabbix setup
│   ├── ZabbixTemplateAuthoring.md      # Template authoring guide
│   ├── ServicePrincipalSetup.md        # Azure auth setup
│   ├── UnusedResourcesGuide.md         # Core feature guide
│   ├── TagExclusionImplementation.md   # Tag feature guide
│   ├── ImplementationStatus.md         # Feature tracking
│   └── ...
└── .github/workflows/                   # GitHub Actions
```

## Available Slash Commands

### `/doc-update` - Documentation Update Analysis

Analyzes recent code changes (last 10 commits) and identifies which documentation files need updates. This command:

1. Groups changed files by type (config, scripts, templates, tests, docs)
2. Maps changes to required documentation updates
3. Provides a prioritized list of documentation tasks
4. Suggests specific changes for each document

**Usage:**
```
/doc-update
```

The command will analyze recent changes and present a checklist of documentation updates. Review the analysis and confirm before making changes.

## Documentation Standards

### File Naming Convention

All documentation files use PascalCase naming:
- `QuickStartGuide.md` (not `QUICK-START-GUIDE.md`)
- `ZabbixIntegrationGuide.md` (not `ZABBIX-INTEGRATION-GUIDE.md`)
- `ServicePrincipalSetup.md` (not `SERVICE-PRINCIPAL-SETUP.md`)

### Documentation Organization

1. **README.md**: High-level overview, quick usage, prerequisites
2. **docs/QuickStartGuide.md**: Detailed getting started instructions
3. **docs/ZabbixIntegrationGuide.md**: Comprehensive Zabbix setup
4. **docs/ImplementationStatus.md**: Feature tracking and status

### When to Update Documentation

Update docs when:
- Adding/modifying command-line flags
- Changing configuration options
- Adding/updating Zabbix metrics or triggers
- Modifying test scripts or adding test coverage
- Changing Azure permissions requirements
- Adding new features or changing behavior

## Development Workflow

1. **Before Making Changes**:
   - Read relevant documentation to understand current behavior
   - Check `docs/ImplementationStatus.md` for feature status
   - Review recent commits: `git log --oneline -10`

2. **During Development**:
   - Update inline documentation/comments in scripts
   - Run linters: `shellcheck`, `yamllint`
   - Run relevant test scripts

3. **After Making Changes**:
   - Use `/doc-update` to identify documentation updates
   - Update `docs/ImplementationStatus.md` if feature status changed
   - Review all changes before committing

## Common Tasks

### Adding a New Zabbix Metric

1. Update `azure-storage-cost-analyzer.sh` (zabbix sender logic)
2. Update `templates/zabbix-template-azure-storage-cost-analyzer-7.0.yaml`
3. Run `./templates/validate-zabbix-template.py templates/zabbix-template-azure-storage-cost-analyzer-7.0.yaml`
4. Update `docs/ZabbixIntegrationGuide.md` (document new metric)
5. Update `docs/ZabbixTemplateAuthoring.md` if adding a pattern

### Adding a New Command-Line Flag

1. Update `azure-storage-cost-analyzer.sh` (argument parsing)
2. Update `README.md` (Quick Usage examples)
3. Update `docs/QuickStartGuide.md` (detailed usage)
4. Update `azure-storage-cost-analyzer.conf.example` if config option exists

### Modifying Tag Exclusion Logic

1. Update `azure-storage-cost-analyzer.sh`
2. Update `docs/TagExclusionImplementation.md`
3. Update `README.md` (Key Features section)
4. Update relevant test scripts

## Testing

- **Static tests**: `tests/test-*.sh` scripts (run in CI)
- **Linting**: `.github/workflows/lint.yml`
- **Manual testing**: Requires Azure subscription and credentials

## Important Notes

- **Bash compatibility**: Use portable Bash (avoid bashisms when possible)
- **Error handling**: Always check command exit codes
- **Zabbix macros**: Use template-level macros, document in authoring guide
- **Cost API**: Batch queries for efficiency (documented in implementation status)
- **Tag format**: `Resource-Next-Review-Date` must be ISO 8601 (YYYY-MM-DD)

## Questions?

- Check `docs/ImplementationStatus.md` for feature details
- Review `docs/QuickStartGuide.md` for usage patterns
- See `docs/ZabbixIntegrationGuide.md` for Zabbix specifics
- Use `/doc-update` to keep documentation in sync with code changes
