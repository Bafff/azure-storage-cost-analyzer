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

## ✅ COMPLETED: Tag-Based Exclusion Feature

**Status:** ✅ **100% Complete - Fully Integrated and Functional (as of 2025-11-20)**

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

### ✅ Integration Work Complete

**All integration tasks have been completed:**
1. ✅ Variable name bug fixed in `analyze_unattached_disks_only()`
2. ✅ CLI flags wired to function calls
3. ✅ All functions properly integrated

**The feature is now ready for production use.**

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

Tag exclusion feature is **COMPLETE** ✅ All requirements met:

- [x] `collect_subscription_metrics()` applies tag filtering
- [x] `analyze_unattached_disks_only()` supports --skip-tagged and --show-tagged-only
- [x] `generate_unused_resources_report()` supports tag filtering for disks AND snapshots
- [x] Display functions show tag status annotations ([Review], [OVERDUE], [INVALID TAG])
- [x] Summary shows excluded/invalid counts
- [x] Zabbix receives `invalid_tags` and `excluded_pending_review` metrics
- [x] Zabbix template has items for new metrics (ready to add triggers as needed)
- [x] Documentation updated (TAG-EXCLUSION-IMPLEMENTATION.md, TODO.md)
- [x] Script works with tag feature disabled (backward compatible)

**Note:** Zabbix template triggers can be added when needed. Core metrics are being sent.

---

## 📝 Notes

- **Backward Compatibility:** If `CONFIG_REVIEW_DATE_TAG_NAME` is empty, tag filtering is disabled (no behavior change)
- **Default Behavior:** Show all resources with tag annotations (transparent by default)
- **Zabbix Impact:** Metrics reflect *actionable* resources only (excludes pending reviews)
- **Invalid Tags:** Always trigger alerts + visible in Zabbix as separate metric

---

**✅ Completion Date:** 2025-11-20
**Actual Time:** ~30 minutes (2 bug fixes)
**Complexity:** Low (only 2 small bugs needed fixing)
**Risk:** Very Low (all components were already implemented)
