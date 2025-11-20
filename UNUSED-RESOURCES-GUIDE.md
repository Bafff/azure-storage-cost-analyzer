# Azure Unused Resources Cost Analysis Guide

## Overview

The enhanced `azure-storage-cost-analysis-enhanced.sh` script now includes functionality to identify and report on unused Azure storage resources (unattached disks and snapshots) with their associated costs.

## Key Features

### 1. Identify Unattached Disks
- Automatically finds all managed disks with `diskState='Unattached'`
- These disks are **not attached to any VM** and are safe candidates for deletion
- Provides cost analysis for each unattached disk

### 2. Snapshot Analysis
- Lists all snapshots in the subscription with cost data
- **Important**: Snapshots don't have an "attached" state - manual review required
- Provides guidance on what to check before deletion

### 3. Comprehensive Reporting
- Generates detailed reports with cost breakdown
- Calculates potential monthly and annual savings
- Provides actionable commands for resource deletion
- Saves report to timestamped file for record-keeping

## Usage

### Generate Unused Resources Report

```bash
./azure-storage-cost-analysis-enhanced.sh unused-report "" "2025-09-01T00:00:00+00:00" "2025-09-30T23:59:59+00:00"
```

**Parameters:**
- `unused-report` - Command to generate the report
- `""` - Empty string uses default subscription (Arena Dev/Test)
- Start date - Beginning of analysis period (ISO 8601 format)
- End date - End of analysis period (ISO 8601 format)

### Example for Current Month

```bash
# For September 2025
./azure-storage-cost-analysis-enhanced.sh unused-report "" "2025-09-01T00:00:00+00:00" "2025-09-30T23:59:59+00:00"

# For October 2025
./azure-storage-cost-analysis-enhanced.sh unused-report "" "2025-10-01T00:00:00+00:00" "2025-10-31T23:59:59+00:00"
```

### Alternative: Specific Subscription

```bash
./azure-storage-cost-analysis-enhanced.sh unused-report "YOUR-SUBSCRIPTION-ID" "2025-09-01T00:00:00+00:00" "2025-09-30T23:59:59+00:00"
```

## Report Sections

The generated report contains three main sections:

### Section 1: Unattached Disks
```
SECTION 1: UNATTACHED DISKS (Not in use - can be deleted)

Disk Name                                          | Size (GB)       | SKU                  | Created              | Monthly Cost
---------------------------------------------------|-----------------|---------------------|---------------------|----------------
disk-name-1                                        | 512             | Premium_LRS         | 2025-03-15          | $42.50
disk-name-2                                        | 1024            | StandardSSD_LRS     | 2025-01-20          | $78.25
---------------------------------------------------|-----------------|---------------------|---------------------|----------------
TOTAL UNATTACHED DISKS                             | 1536 GB         |                     |                     | $120.75
```

**Key Information:**
- Disk name (truncated to 50 chars)
- Size in GB
- SKU/Tier (Premium_LRS, StandardSSD_LRS, etc.)
- Creation date
- Monthly cost for the analysis period

### Section 2: All Snapshots
```
SECTION 2: ALL SNAPSHOTS (Manual review needed)

NOTE: Snapshots don't have 'attached' state. Review each snapshot to determine if:
  - It's needed for backup/disaster recovery
  - It's part of automated backup policy
  - It can be safely deleted

Snapshot Name                                      | Size (GB)       | SKU                  | Created              | Monthly Cost
---------------------------------------------------|-----------------|---------------------|---------------------|----------------
snapshot-backup-20250901                           | 512             | Standard_LRS        | 2025-09-01          | $2.40
snapshot-migration-test                            | 1024            | Standard_LRS        | 2025-08-15          | $4.80
---------------------------------------------------|-----------------|---------------------|---------------------|----------------
TOTAL SNAPSHOTS                                    | 1536 GB         |                     |                     | $7.20
```

**Important**: Snapshots require manual review because:
- They may be part of backup/DR policies
- They may be needed for rollback capabilities
- They may be referenced by automation

### Section 3: Summary & Recommendations
```
SECTION 3: SUMMARY & RECOMMENDATIONS

IMMEDIATE ACTION ITEMS:

1. UNATTACHED DISKS - Safe to delete (after verification)
   - Count: 2 disk(s)
   - Potential monthly savings: $120.75
   - Annual savings potential: $1449.00

   ACTION: Review each disk in Azure Portal, verify not needed, then delete
   COMMAND: az disk delete --name <disk-name> --resource-group <rg-name>

2. SNAPSHOTS - Manual review required
   - Count: 2 snapshot(s)
   - Current monthly cost: $7.20

   REVIEW CRITERIA:
   - Is this snapshot older than your retention policy?
   - Is the source disk still in use?
   - Is this needed for disaster recovery?
   - Is this part of an automated backup?

   COMMAND: az snapshot delete --name <snapshot-name> --resource-group <rg-name>
```

## Safety Guidelines

### ⚠️ CRITICAL: DO NOT Delete Resources Without Verification

Before deleting any resource, you MUST:

1. **Verify in Azure Portal**
   - Navigate to the resource
   - Check resource tags for ownership/purpose
   - Review any associated metadata

2. **Check with Team**
   - Confirm resource is not part of active project
   - Verify not needed for backup/recovery
   - Ensure not referenced by automation

3. **Document Decision**
   - Note why resource is being deleted
   - Record cost savings
   - Keep audit trail

### Recommended Deletion Process

#### For Unattached Disks:

```bash
# Step 1: Get detailed info about the disk
az disk show --name <disk-name> --resource-group <rg-name>

# Step 2: Check tags and metadata
az disk show --name <disk-name> --resource-group <rg-name> --query '{name:name, tags:tags, createTime:timeCreated}'

# Step 3: If confirmed safe to delete
az disk delete --name <disk-name> --resource-group <rg-name> --yes

# Step 4: Verify deletion
az disk show --name <disk-name> --resource-group <rg-name>  # Should error
```

#### For Snapshots:

```bash
# Step 1: Get detailed info
az snapshot show --name <snapshot-name> --resource-group <rg-name>

# Step 2: Check source disk
az snapshot show --name <snapshot-name> --resource-group <rg-name> --query '{name:name, sourceDisk:creationData.sourceResourceId, created:timeCreated}'

# Step 3: Verify source disk still exists and is needed
# (Check if source disk ID is still in use)

# Step 4: If confirmed safe to delete
az snapshot delete --name <snapshot-name> --resource-group <rg-name> --yes

# Step 5: Verify deletion
az snapshot show --name <snapshot-name> --resource-group <rg-name>  # Should error
```

## Common Scenarios

### Scenario 1: Development/Test Disk Cleanup
**Situation**: Dev/test environment was decommissioned but disks remain

**Action**:
1. Generate unused resources report
2. Identify disks in dev/test resource groups
3. Verify with dev team that environment is no longer needed
4. Delete unattached disks
5. Review snapshots - likely safe to delete if environment is gone

### Scenario 2: Migration Leftovers
**Situation**: VM migration completed but old disks/snapshots remain

**Action**:
1. Generate report for migration period
2. Identify disks created during migration
3. Verify new VMs are running successfully
4. Check snapshots are not part of rollback plan
5. Delete if migration is complete and stable

### Scenario 3: Cost Optimization Review
**Situation**: Monthly cost review identifies storage costs

**Action**:
1. Generate monthly report
2. Present findings to team leads
3. Get approval for deletions
4. Execute cleanup in stages
5. Monitor savings in next billing cycle

## Report Output

Reports are automatically saved with timestamp:
```
unused-resources-report-20251013-143052.txt
```

**Location**: Same directory as script execution

**Format**: Plain text with formatted tables (pipe-separated)

**Retention**: Keep reports for audit trail and cost tracking

## Troubleshooting

### Issue: "No unattached disks found"
**Meaning**: All disks are currently attached to VMs - this is good!
**Action**: No cleanup needed

### Issue: API Rate Limiting (429 errors)
**Cause**: Too many API calls in short time
**Solution**: Script includes automatic retry with exponential backoff (3-second delays)
**Action**: If still occurs, run report during off-peak hours

### Issue: "No cost data found"
**Possible Causes**:
- Resource was created after the analysis period
- Cost data not yet available (can take 24-48 hours)
- Resource was free tier or zero-cost

**Action**: Try extending the date range or wait for cost data to populate

### Issue: Date validation errors
**Cause**: Invalid date format or range exceeds 1 year
**Solution**: Use ISO 8601 format: `YYYY-MM-DDTHH:MM:SS+00:00`
**Action**: Check dates and ensure range is ≤365 days

## Cost Estimation Examples

### Unattached Premium SSD Costs:
- **P10 (128 GB)**: ~$19.71/month → $236.52/year
- **P20 (512 GB)**: ~$73.22/month → $878.64/year
- **P30 (1024 GB)**: ~$135.17/month → $1,622.04/year

### Snapshot Costs (Standard):
- **128 GB**: ~$0.60/month → $7.20/year
- **512 GB**: ~$2.40/month → $28.80/year
- **1024 GB**: ~$4.80/month → $57.60/year

**Note**: Actual costs depend on region, tier, and usage patterns

## Best Practices

1. **Run Monthly Reports**
   - Schedule regular cost reviews
   - Track month-over-month changes
   - Identify cost trends

2. **Automate Where Possible**
   - Consider automation for old snapshot deletion
   - Implement retention policies
   - Use Azure Policies for governance

3. **Tag Resources**
   - Always tag disks with owner, project, environment
   - Makes identification easier
   - Enables automated cleanup rules

4. **Document Deletions**
   - Keep audit trail of what was deleted
   - Note savings achieved
   - Track recurrence of unused resources

5. **Coordinate with Teams**
   - Don't delete without confirmation
   - Establish clear ownership policies
   - Create approval workflow for deletions

## Integration with CI/CD

Consider adding this to your cost optimization pipeline:

```bash
#!/bin/bash
# Monthly cost optimization check

CURRENT_MONTH_START="$(date -u +%Y-%m-01T00:00:00+00:00)"
CURRENT_MONTH_END="$(date -u +%Y-%m-%dT23:59:59+00:00)"

./azure-storage-cost-analysis-enhanced.sh unused-report "" "$CURRENT_MONTH_START" "$CURRENT_MONTH_END"

# Send report to team via email or Slack
# Trigger approval workflow if savings > $X threshold
```

## Questions or Issues?

- Check Azure Cost Management for detailed billing
- Review Azure Advisor recommendations
- Consult Azure documentation for disk/snapshot pricing
- Contact IT team for enterprise-specific policies

## Related Commands

### Other Useful Script Commands

```bash
# List all disks (no cost analysis)
./azure-storage-cost-analysis-enhanced.sh list-disks

# List all snapshots (no cost analysis)
./azure-storage-cost-analysis-enhanced.sh list-snapshots

# Analyze specific disk costs
./azure-storage-cost-analysis-enhanced.sh pvc-596782ff-6859-4334-992c-fa519fa2f501 "" "2025-09-01T00:00:00+00:00" "2025-09-30T23:59:59+00:00"

# Analyze all disks with costs
./azure-storage-cost-analysis-enhanced.sh all-disks "" "2025-09-01T00:00:00+00:00" "2025-09-30T23:59:59+00:00"

# Historical 6-month analysis of PostgreSQL disk
./azure-storage-cost-analysis-enhanced.sh historical
```

---

**Last Updated**: October 2025
**Script Version**: Enhanced with unused resources reporting
