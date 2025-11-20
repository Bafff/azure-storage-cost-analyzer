# Azure Storage Cost Analyzer - TODO

**Last Updated:** 2025-11-20
**Current Branch:** `feature/azure-storage-cost-analyzer-migration`

---

## 🎯 Current Status

### ✅ Production-Ready Features

- **Multi-subscription scanning** - Scans all Azure subscriptions in one execution
- **Zabbix 7.0.5 integration** - Sends metrics via zabbix_sender with LLD support
- **JSON/Text/Zabbix output formats** - Multiple output formats for automation
- **Batch API optimization** - 30-40x performance improvement
- **Azure DevOps pipeline ready** - Complete YAML and documentation
- **Config file support** - Centralized configuration via INI files

---

## 🚧 IN PROGRESS: Tag-Based Exclusion Feature

**Status:** 🟡 **70% Complete - Foundation Implemented, Integration Needed**

### Feature Overview

Allow marking resources as "approved exceptions" with a review date tag:
- **Tag:** `Resource-Next-Review-Date: 2025.12.30`
- **Behavior:** Exclude from alerts until review date passes
- **Invalid/Expired tags:** Always included in alerts + reported to Zabbix

### ✅ Completed Components (Lines 53-1000 in script)

1. **Config System**
   - Added `CONFIG_REVIEW_DATE_TAG_NAME`, `CONFIG_REVIEW_DATE_FORMAT`, `CONFIG_EXCLUDE_PENDING_REVIEW`
   - Config file parsing implemented
   - Example config updated

2. **Tag Validation Functions**
   - `validate_review_date_tag()` - Validates YYYY.MM.DD format strictly
   - `is_review_date_future()` - Compares with current date
   - `check_resource_tag_status()` - Returns JSON status object

3. **Filtering Engine**
   - `filter_resources_by_tags()` - Central filtering function
   - Processes resource arrays and applies filtering logic
   - Returns filtered resources + statistics

4. **Data Collection**
   - `list_unattached_disks()` - Now includes Tags field
   - `get_all_snapshots_with_details()` - Now includes Tags field

5. **CLI Flags**
   - `--skip-tagged` - Hide resources with valid future review dates
   - `--show-tagged-only` - Show only tagged resources

6. **Documentation**
   - `TAG-EXCLUSION-IMPLEMENTATION.md` - Complete implementation guide
   - `azure-storage-monitor.conf.example` - Updated with tag config

### 🔨 TODO: Integration Work (30% Remaining)

#### Priority 1: Core Integration (2-3 hours)

**File:** `azure-storage-cost-analyzer.sh`

##### 1. Modify `collect_subscription_metrics()` (Line ~1150)

**Current code collects raw data:**
```bash
unattached_disks_json=$(list_unattached_disks "$subscription_id" "$resource_group" "$include_attached" 2>/dev/null)
disk_count=$(echo "$unattached_disks_json" | jq '. | length')
```

**TODO: Apply tag filtering:**
```bash
# Get raw disks
unattached_disks_raw=$(list_unattached_disks "$subscription_id" "$resource_group" "$include_attached" 2>/dev/null)

# Apply tag filtering (if enabled in config)
local tag_name="${CONFIG_REVIEW_DATE_TAG_NAME:-}"
if [[ -n "$tag_name" ]]; then
    filtered_result=$(filter_resources_by_tags \
        "$unattached_disks_raw" \
        "$tag_name" \
        "${CONFIG_REVIEW_DATE_FORMAT:-YYYY.MM.DD}" \
        "${CONFIG_EXCLUDE_PENDING_REVIEW:-false}" \
        "false")

    unattached_disks_json=$(echo "$filtered_result" | jq -r '.resources')
    disk_count=$(echo "$filtered_result" | jq -r '.stats.included')
    invalid_tags_count=$(echo "$filtered_result" | jq -r '.stats.invalid_tags')
else
    # No tag filtering
    unattached_disks_json="$unattached_disks_raw"
    disk_count=$(echo "$unattached_disks_json" | jq '. | length')
    invalid_tags_count=0
fi
```

**Also update snapshots section similarly.**

##### 2. Pass `skip_tagged`/`show_tagged_only` Through Call Chain

**Functions to update:**

1. **`analyze_unattached_disks_only()`** (Line ~2360)
   - Add parameters: `skip_tagged="${7:-false}"` and `show_tagged_only="${8:-false}"`
   - Pass to filter_resources_by_tags()

2. **`generate_unused_resources_report()`** (Line ~2590)
   - Add same parameters
   - Apply filtering to both disks AND snapshots

3. **Main function calls** (Line ~3750+)
   - Pass `$skip_tagged` and `$show_tagged_only` to analysis functions

**Example:**
```bash
# In main() when calling analyze_unattached_disks_only:
analyze_unattached_disks_only "$subscription_id" "$start_date" "$end_date" \
    "$resource_group" "$include_attached" "$sort_by" \
    "$skip_tagged" "$show_tagged_only"  # ADD THESE
```

##### 3. Update Display Functions to Show Tag Annotations

**In table printing sections, add tag status column:**

```bash
# Extract tag status info
local tag_status=$(echo "$disk" | jq -r '.TagStatusDetail.tag_status // "none"')
local review_date=$(echo "$disk" | jq -r '.TagStatusDetail.review_date // ""')

# Build annotation
local annotation=""
case "$tag_status" in
    "pending")
        annotation="ℹ️  Review: $review_date"
        ;;
    "expired")
        annotation="⚠️  Overdue: $review_date"
        ;;
    "invalid")
        local tag_value=$(echo "$disk" | jq -r '.TagStatusDetail.review_date')
        annotation="❌ Invalid: $tag_value"
        ;;
esac

# Print with annotation
printf "%-40s | %-8s | \$%-11.2f | %-30s\n" \
    "$disk_name" "$disk_size" "$cost" "$annotation"
```

**Locations to update:**
- `analyze_unattached_disks_only()` - Disk table printing
- `generate_unused_resources_report()` - Both disk and snapshot tables
- `collect_subscription_metrics()` - If displaying results

##### 4. Add Summary Lines for Excluded Resources

**After table, show exclusion summary:**

```bash
if [[ -n "${CONFIG_REVIEW_DATE_TAG_NAME:-}" ]]; then
    local excluded_count=$(echo "$filtered_result" | jq -r '.stats.excluded_pending')
    local invalid_count=$(echo "$filtered_result" | jq -r '.stats.invalid_tags')

    if [[ $excluded_count -gt 0 ]]; then
        echo ""
        echo "ℹ️  Excluded $excluded_count resource(s) with pending review (future dates)"
    fi

    if [[ $invalid_count -gt 0 ]]; then
        echo "⚠️  Warning: $invalid_count resource(s) have invalid review date tags"
    fi
fi
```

#### Priority 2: Zabbix Metrics (1 hour)

##### 5. Add `invalid_tags` Count to Zabbix Output

**File:** `azure-storage-cost-analyzer.sh`
**Function:** `process_multi_subscription()` (Line ~1297)

**In Zabbix output section, add:**

```bash
# Track invalid tags across all subscriptions
local total_invalid_tags=0

# In subscription loop, accumulate:
total_invalid_tags=$((total_invalid_tags + sub_invalid_tags))

# In Zabbix output section:
echo "$zabbix_host azure.storage.all.invalid_tags $timestamp $total_invalid_tags"
echo "$zabbix_host azure.storage.all.excluded_pending_review $timestamp $total_excluded_pending"

# Per-subscription:
echo "$zabbix_host azure.storage.subscription[$sub_id].invalid_tags $timestamp $sub_invalid_tags"
```

**Also update JSON output** to include these fields in aggregated_metrics.

#### Priority 3: Zabbix Template (30 minutes)

##### 6. Update Zabbix Template with Invalid Tags Metrics

**File:** `zabbix-template-azure-storage-monitor-7.0.xml`

**Add new items:**

```xml
<item>
    <uuid>NEW_UUID_1</uuid>
    <name>Total Invalid Review Tags</name>
    <type>ZABBIX_ACTIVE</type>
    <key>azure.storage.all.invalid_tags</key>
    <delay>0</delay>
    <history>90d</history>
    <value_type>UNSIGNED</value_type>
    <units>tags</units>
    <description>Number of resources with malformed review date tags</description>
</item>

<item>
    <uuid>NEW_UUID_2</uuid>
    <name>Resources Excluded (Pending Review)</name>
    <type>ZABBIX_ACTIVE</type>
    <key>azure.storage.all.excluded_pending_review</key>
    <delay>0</delay>
    <history>90d</history>
    <value_type>UNSIGNED</value_type>
    <units>resources</units>
    <description>Resources excluded due to valid future review dates</description>
</item>
```

**Add trigger for invalid tags:**

```xml
<trigger>
    <uuid>NEW_UUID_3</uuid>
    <expression>last(/Azure Storage Cost Monitor/azure.storage.all.invalid_tags)&gt;0</expression>
    <name>Invalid review date tags detected: {ITEM.LASTVALUE}</name>
    <priority>WARNING</priority>
    <description>Resources have malformed review date tags - check and correct tag format</description>
</trigger>
```

**Add per-subscription item prototype:**

```xml
<item_prototype>
    <uuid>NEW_UUID_4</uuid>
    <name>Subscription [{#SUBSCRIPTION_NAME}]: Invalid Tags</name>
    <type>ZABBIX_ACTIVE</type>
    <key>azure.storage.subscription[{#SUBSCRIPTION_ID}].invalid_tags</key>
    <delay>0</delay>
    <value_type>UNSIGNED</value_type>
</item_prototype>
```

#### Priority 4: Documentation Updates (30 minutes)

##### 7. Update Documentation

**Files to update:**

1. **ZABBIX-INTEGRATION-GUIDE.md**
   - Add invalid_tags metric to metrics reference table
   - Add example of tag usage
   - Update troubleshooting section

2. **IMPLEMENTATION-STATUS.md**
   - Add tag exclusion feature to feature list
   - Update metrics table

3. **README.md** (if exists)
   - Add tag exclusion to feature list
   - Add usage examples

#### Priority 5: Testing (1-2 hours)

##### 8. End-to-End Testing

**Test Scenarios:**

1. **Valid Future Tag**
   ```bash
   # Tag a test disk
   az disk update --name test-disk \
     --resource-group test-rg \
     --set tags.Resource-Next-Review-Date="2026.01.15"

   # Run script
   ./azure-storage-cost-analyzer.sh unused-report \
     --subscriptions test-sub-id --days 30

   # Verify:
   # - Disk shown with "ℹ️  Review: 2026-01-15" annotation
   # - NOT counted in Zabbix metrics (if exclude_pending_review=true)
   ```

2. **Expired Tag**
   ```bash
   # Tag with past date
   az disk update --name test-disk-2 \
     --set tags.Resource-Next-Review-Date="2024.10.01"

   # Verify:
   # - Disk shown with "⚠️  Overdue: 2024-10-01" annotation
   # - COUNTED in Zabbix metrics
   ```

3. **Invalid Tag**
   ```bash
   # Malformed tag
   az disk update --name test-disk-3 \
     --set tags.Resource-Next-Review-Date="approved"

   # Verify:
   # - Disk shown with "❌ Invalid: approved" annotation
   # - COUNTED in Zabbix metrics
   # - invalid_tags metric incremented
   ```

4. **`--skip-tagged` Flag**
   ```bash
   ./azure-storage-cost-analyzer.sh unused-report \
     --skip-tagged --days 30

   # Verify:
   # - Resources with valid future tags hidden
   # - Summary shows "Excluded N resources"
   ```

5. **Zabbix Metrics Validation**
   ```bash
   # Check Zabbix received metrics
   # Monitoring → Latest data → azure-storage-monitor

   # Verify items:
   # - azure.storage.all.invalid_tags = correct count
   # - azure.storage.all.excluded_pending_review = correct count
   # - azure.storage.all.total_disks = excludes pending review resources
   ```

---

## 📚 Implementation Reference

**Detailed Guide:** See `TAG-EXCLUSION-IMPLEMENTATION.md` for:
- Complete code examples for each integration point
- Function signatures and parameters
- Expected behavior and edge cases
- Zabbix template XML snippets
- Testing scenarios with expected results

**Config Example:** See `azure-storage-monitor.conf.example` for:
- Tag configuration syntax
- Example tag values and behavior
- All available settings

---

## 🎯 Definition of Done

Tag exclusion feature is **complete** when:

- [ ] `collect_subscription_metrics()` applies tag filtering
- [ ] `analyze_unattached_disks_only()` supports --skip-tagged and --show-tagged-only
- [ ] `generate_unused_resources_report()` supports tag filtering for disks AND snapshots
- [ ] Display functions show tag status annotations (ℹ️ Review, ⚠️ Overdue, ❌ Invalid)
- [ ] Summary shows excluded/invalid counts
- [ ] Zabbix receives `invalid_tags` and `excluded_pending_review` metrics
- [ ] Zabbix template updated with new items and triggers
- [ ] Documentation updated (ZABBIX-INTEGRATION-GUIDE.md, IMPLEMENTATION-STATUS.md)
- [ ] All 5 test scenarios pass
- [ ] Script works with tag feature disabled (backward compatible)

---

## 📝 Notes

- **Backward Compatibility:** If `CONFIG_REVIEW_DATE_TAG_NAME` is empty, tag filtering is disabled (no behavior change)
- **Default Behavior:** Show all resources with tag annotations (transparent by default)
- **Zabbix Impact:** Metrics reflect *actionable* resources only (excludes pending reviews)
- **Invalid Tags:** Always trigger alerts + visible in Zabbix as separate metric

---

**Estimated Completion Time:** 4-6 hours total
**Complexity:** Medium (mostly wiring existing functions)
**Risk:** Low (foundation tested, integration is straightforward)
