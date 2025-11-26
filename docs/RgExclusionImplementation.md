# Resource Group Exclusion Feature - Implementation Documentation

**Feature:** Resource Group exclusion with age-based anomaly detection
**Purpose:** Exclude ephemeral resources (e.g., Databricks) while catching orphaned old resources
**Status:** ✅ **COMPLETE - Fully Integrated and Functional**

---

## Overview

This feature allows excluding specific Resource Groups from cost analysis and alerting, with an intelligent age-based exception to catch resources that are unexpectedly old (potential orphaned/stuck resources).

### Use Case: Databricks

Databricks creates and deletes managed disks regularly as part of normal cluster operations. These ephemeral resources:
- Are created/deleted frequently (hours/days)
- Don't need alerts for recent resources (<60 days)
- **BUT** if a Databricks disk is >60 days old, it's likely orphaned and needs investigation

## Configuration

### Config File: `azure-storage-cost-analyzer.conf`

```ini
[exclusions]
# Comma-separated list of resource groups to exclude
exclude_resource_groups = databricks-rg,temp-rg

# Age threshold in days - resources older than this will be included
# even if they're in an excluded RG (anomaly detection)
exclude_rg_age_threshold_days = 30
```

### CLI Flags

```bash
./azure-storage-cost-analyzer.sh unused-report \
  --subscriptions <sub-id> \
  --days 30 \
  --exclude-resource-groups databricks-rg,temp-rg \
  --exclude-rg-age-threshold-days 30
```

## Implementation Details

### 1. Configuration Variables

**File:** `azure-storage-cost-analyzer.sh` (Lines 49-50)

```bash
CONFIG_EXCLUDE_RESOURCE_GROUPS=""        # Comma-separated RG names
CONFIG_EXCLUDE_RG_AGE_THRESHOLD_DAYS=""  # Age threshold in days
```

### 2. Core Functions

#### `calculate_resource_age_days(time_created)` (Lines 962-1002)

Calculates resource age in days from Azure's `timeCreated` timestamp.

**Input:** ISO 8601 timestamp (e.g., `2024-10-15T10:30:45.1234567Z`)
**Output:** Age in days (integer) or -1 if parsing fails
**Features:**
- Handles Azure's ISO 8601 format with fractional seconds
- Fallback parsing if fractional seconds cause issues
- Returns -1 on error (safe default)

#### `check_rg_exclusion(resource_group, time_created, exclude_rgs, age_threshold_days)` (Lines 1004-1057)

Determines if a resource should be excluded based on RG exclusion rules.

**Logic Flow:**
```
1. If no exclusion list → Include resource
2. If RG NOT in exclusion list → Include resource
3. If RG IS in exclusion list:
   a. Calculate resource age
   b. If age >= threshold → Include (anomaly)
   c. If age < threshold → Exclude (normal ephemeral)
```

**Return Value:** JSON object
```json
{
  "should_exclude": true|false,
  "reason": "no_exclusion_list"|"not_in_exclusion_list"|"age_exceeds_threshold"|"excluded_rg_recent"|"age_calculation_failed",
  "age_days": 45,
  "threshold": 30
}
```

### 3. Integration with Filtering Pipeline

#### Updated `filter_resources_by_tags()` Function (Lines 1059-1248)

**New Parameters:**
```bash
filter_resources_by_tags(
    resources_json,
    tag_name,
    tag_format,
    skip_tagged,
    show_tagged_only,
    exclude_rgs,           # NEW
    age_threshold_days     # NEW
)
```

**Filtering Order:**
1. **RG Exclusion** (highest priority)
2. Tag-based filtering (if not already excluded by RG)
3. Other filtering modes

**Statistics Tracking:**
```json
{
  "stats": {
    "total": 100,
    "included": 70,
    "excluded_pending": 10,
    "excluded_expired": 5,
    "invalid_tags": 5,
    "excluded_rg": 10        // NEW
  }
}
```

### 4. Resource Annotation

Each resource is annotated with RG exclusion details:

```json
{
  "Id": "/subscriptions/.../disks/my-disk",
  "Name": "my-disk",
  "ResourceGroup": "databricks-rg",
  "Created": "2024-11-01T10:30:45Z",
  "RgExclusionDetail": {
    "should_exclude": true,
    "reason": "excluded_rg_recent",
    "age_days": 5,
    "threshold": 30
  }
}
```

### 5. Conflict Detection

**File:** `azure-storage-cost-analyzer.sh` (Lines 4234-4246)

Validates that a resource group doesn't appear in both include and exclude lists.

```bash
if [[ -n "$resource_group" && -n "${CONFIG_EXCLUDE_RESOURCE_GROUPS}" ]]; then
    # Check for conflicts (case-insensitive)
    # Exit with error if same RG in both lists
fi
```

**Error Message:**
```
Error: Resource group 'databricks-rg' appears in both include (--resource-group)
and exclude (--exclude-resource-groups) lists
This configuration conflict is not allowed. Please specify the resource group
in only one list.
```

## Behavior Examples

### Example 1: Normal Databricks Resources (Excluded)

**Configuration:**
```ini
exclude_resource_groups = databricks-rg
exclude_rg_age_threshold_days = 30
```

**Resources:**
| Name | RG | Age (days) | Action | Reason |
|------|-----|-----------|--------|--------|
| databricks-disk-1 | databricks-rg | 2 | ❌ EXCLUDED | Recent ephemeral resource |
| databricks-disk-2 | databricks-rg | 15 | ❌ EXCLUDED | Recent ephemeral resource |
| prod-disk-1 | prod-rg | 5 | ✅ INCLUDED | Not in exclusion list |

### Example 2: Old Databricks Resource (Anomaly Detected)

**Configuration:**
```ini
exclude_resource_groups = databricks-rg
exclude_rg_age_threshold_days = 30
```

**Resources:**
| Name | RG | Age (days) | Action | Reason |
|------|-----|-----------|--------|--------|
| databricks-disk-1 | databricks-rg | 2 | ❌ EXCLUDED | Recent ephemeral resource |
| databricks-disk-stuck | databricks-rg | 45 | ✅ INCLUDED | **Anomaly: Too old for ephemeral** |
| prod-disk-1 | prod-rg | 5 | ✅ INCLUDED | Not in exclusion list |

### Example 3: Multiple Excluded RGs

**Configuration:**
```ini
exclude_resource_groups = databricks-rg,temp-rg,ephemeral-rg
exclude_rg_age_threshold_days = 60
```

All resources in `databricks-rg`, `temp-rg`, and `ephemeral-rg` are excluded if <60 days old, included if >=60 days old.

## Integration Points

### Function Call Updates

All calls to `filter_resources_by_tags()` have been updated:

**Before:**
```bash
filtered_result=$(filter_resources_by_tags \
    "$resources_json" \
    "$tag_name" \
    "${CONFIG_REVIEW_DATE_FORMAT:-YYYY.MM.DD}" \
    "${CONFIG_EXCLUDE_PENDING_REVIEW:-false}" \
    "false")
```

**After:**
```bash
filtered_result=$(filter_resources_by_tags \
    "$resources_json" \
    "$tag_name" \
    "${CONFIG_REVIEW_DATE_FORMAT:-YYYY.MM.DD}" \
    "${CONFIG_EXCLUDE_PENDING_REVIEW:-false}" \
    "false" \
    "${CONFIG_EXCLUDE_RESOURCE_GROUPS:-}" \
    "${CONFIG_EXCLUDE_RG_AGE_THRESHOLD_DAYS:-60}")
```

**Updated Locations:**
- Line 1590: `collect_subscription_metrics()` - unattached disks
- Line 1668: `collect_subscription_metrics()` - snapshots
- Line 2901: `analyze_unattached_disks_only()` - disks
- Line 3199: `analyze_unattached_disks_only()` - disks (second call)
- Line 3434: `generate_unused_resources_report()` - snapshots

## Testing Scenarios

### Test 1: No Exclusion List
```bash
./azure-storage-cost-analyzer.sh unused-report --days 30
```
**Expected:** All resources included (no filtering)

### Test 2: Basic Exclusion
```bash
./azure-storage-cost-analyzer.sh unused-report \
  --days 30 \
  --exclude-resource-groups databricks-rg
```
**Expected:** Databricks resources <60 days excluded

### Test 3: Custom Threshold
```bash
./azure-storage-cost-analyzer.sh unused-report \
  --days 30 \
  --exclude-resource-groups temp-rg \
  --exclude-rg-age-threshold-days 7
```
**Expected:** temp-rg resources <7 days excluded, >=7 days included

### Test 4: Conflict Detection
```bash
./azure-storage-cost-analyzer.sh unused-report \
  --resource-group databricks-rg \
  --exclude-resource-groups databricks-rg
```
**Expected:** Error message about conflict

## Performance Considerations

- **Age Calculation:** O(1) per resource (simple date arithmetic)
- **RG Matching:** O(n) where n = number of excluded RGs (typically small)
- **Case-Insensitive:** Uses bash `${var,,}` for lowercase comparison
- **Filtering Order:** RG check happens BEFORE tag validation (efficiency)

## Future Enhancements

Potential future improvements (not currently implemented):

1. **Per-RG Thresholds:**
   ```ini
   exclude_resource_groups = {"databricks-rg": 30, "temp-rg": 7}
   ```

2. **Wildcard Matching:**
   ```ini
   exclude_resource_groups = databricks-*,temp-*
   ```

3. **Separate Metrics:**
   ```
   azure.storage.disks.excluded_rg.old.count
   azure.storage.disks.excluded_rg.old.cost
   ```

## Related Documentation

- [Tag Exclusion Implementation](./TagExclusionImplementation.md) - Tag-based filtering
- [Configuration Example](../azure-storage-cost-analyzer.conf.example) - Full config reference
- [Quick Start Guide](./QuickStartGuide.md) - Getting started

## GitHub Issue

Feature request and implementation tracked in: [Issue #9](https://github.com/Bafff/azure-storage-cost-analyzer/issues/9)
