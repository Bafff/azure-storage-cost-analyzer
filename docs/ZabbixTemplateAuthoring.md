# Zabbix Template Authoring (7.0) – Quick Rules

Use this checklist to build or modify Zabbix 7.0 templates without getting blocked on import errors.

## Best approach: export first, modify second

**The fastest way to create a valid template is to export an existing one from Zabbix as YAML and use it as a skeleton.** This guarantees the structure, field names, and UUID format are correct.

```bash
# Export a template from Zabbix via API (replace URL, token, and template ID)
curl -s -X POST 'https://zbx.hostname.com/api_jsonrpc.php' \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer YOUR_TOKEN' \
  -d '{
    "jsonrpc": "2.0",
    "method": "configuration.export",
    "params": {"format": "yaml", "options": {"templates": ["TEMPLATE_ID"]}},
    "id": 1
  }' | python3 -c "import sys,json; print(json.load(sys.stdin)['result'])" > skeleton.yaml
```

Then modify `skeleton.yaml`: change names, add items, add triggers, and regenerate UUIDs.

If no existing template is close enough, use the YAML structure reference below to write from scratch.

## Workflow (do this order)
1) **Start from a skeleton:** Export an existing template as YAML (see above), or use the YAML structure reference below.
2) **Generate UUIDs:** Always use `python3 -c "import uuid; print(uuid.uuid4().hex)"` to generate each UUID. Hand-written hex strings will fail — Zabbix validates the v4 version bits at position 13 (`4`) and variant bits at position 17 (`8/9/a/b`). Every UUID in the file must be unique.
3) **Choose item type:** For push data via `zabbix_sender`, set `type: TRAP` (ZABBIX_TRAPPER). Do not leave as active/passive agent unless the agent will collect it.
4) **Name keys correctly:** Pattern `namespace.metric[param]` – parameters always inside `[]`, no dots after the closing bracket. Example: `azure.storage.subscription.waste_monthly[{#SUBSCRIPTION_ID}]`.
5) **Discovery first:** Define discovery rule, then item_prototypes/trigger_prototypes referencing its LLD macros.
6) **Validate locally:** Run `python3 templates/validate-zabbix-template.py <file>` (fast structural check) then import into a local Zabbix 7.0 UI if possible.
7) **Commit & push:** Keep template + doc in the same change; include rationale in commit message.

## YAML Structure Reference (CRITICAL)

The Zabbix YAML import format has a specific structure that differs from the JSON API output. Getting this wrong causes cryptic import errors.

### Field name differences: YAML import vs JSON API

| YAML import field | JSON API field | Notes |
|---|---|---|
| `key` | `key_` | **Most common mistake.** YAML uses `key`, API returns `key_` |
| `type: TRAP` | `"type": "2"` | YAML uses enum names, API uses numeric codes |
| `type: DEPENDENT` | `"type": "18"` | Same — use the name, not the number |
| `type: CALCULATED` | `"type": "15"` | Same |
| `value_type: FLOAT` | `"value_type": "0"` | YAML uses names, API uses numbers |
| `value_type: TEXT` | `"value_type": "4"` | Same |
| `priority: HIGH` | `"priority": "4"` | Same |

### Where triggers go (two locations!)

**Single-item triggers** (expression references only one item) go **inside the item definition**:

```yaml
items:
  - uuid: aaa...
    name: My-Item
    type: DEPENDENT
    key: my.item
    master_item:
      key: master.traper
    preprocessing:
      - type: JSONPATH
        parameters:
          - $.my_field
    triggers:                          # ← nested inside the item
      - uuid: bbb...
        expression: 'last(/Template-Name/my.item)>100'
        name: 'My item is too high'
        priority: HIGH
```

**Multi-item triggers** (expression references 2+ items) go at the **top level**, outside the template:

```yaml
zabbix_export:
  version: '7.0'
  template_groups:
    - uuid: ...
      name: Templates/MyGroup
  templates:
    - uuid: ...
      template: My-Template
      items:
        - ...
      macros:
        - ...
  triggers:                            # ← top level, sibling of templates
    - uuid: ccc...
      expression: 'nodata(/My-Template/item.a,4h)=1 or nodata(/My-Template/item.b,4h)=1'
      name: 'No data from either item'
      priority: WARNING
```

**If you put triggers as a direct child of the template, the import will fail with: `unexpected tag "triggers"`.**

### Minimal valid YAML template skeleton

```yaml
zabbix_export:
  version: '7.0'
  template_groups:
    - uuid: <generate with uuid4().hex>
      name: Templates/MyGroup
  templates:
    - uuid: <generate with uuid4().hex>
      template: My-Template-Name
      name: My-Template-Name
      description: 'What this template monitors'
      groups:
        - name: Templates/MyGroup
      items:
        # Master trapper item (receives data from zabbix_sender)
        - uuid: <generate>
          name: Raw-Data
          type: TRAP
          key: raw.data
          history: 90d
          value_type: TEXT

        # Dependent item (extracts from master via JSONPath)
        - uuid: <generate>
          name: Metric-A
          type: DEPENDENT
          key: metric.a
          history: 90d
          preprocessing:
            - type: JSONPATH
              parameters:
                - $.metric_a
          master_item:
            key: raw.data
          triggers:
            - uuid: <generate>
              expression: 'last(/My-Template-Name/metric.a)>100'
              name: 'Metric A is too high'
              priority: HIGH
              manual_close: 'YES'

        # Calculated item (formula referencing other items)
        - uuid: <generate>
          name: Error-Rate
          type: CALCULATED
          key: error.rate
          value_type: FLOAT
          units: '%'
          history: 90d
          params: '100*last(//metric.err)/(last(//metric.ok)+last(//metric.err)+0.001)'
          delay: 30m

      macros:
        - macro: '{$MY_THRESHOLD}'
          value: '100'
          description: 'Threshold for alerting'

  # Multi-item triggers go here (outside templates)
  triggers:
    - uuid: <generate>
      expression: 'nodata(/My-Template-Name/metric.a,4h)=1 or nodata(/My-Template-Name/metric.b,4h)=1'
      name: 'No data received'
      priority: WARNING
      manual_close: 'YES'
```

### Trigger dependencies in YAML

Dependencies reference the parent trigger by name + expression (not by UUID):

```yaml
triggers:
  - uuid: <generate>
    expression: 'min(/Template/rate,#2)>{$WARN_THRESHOLD}'
    name: 'Rate warning'
    priority: WARNING
    dependencies:
      - name: 'Rate critical'
        expression: 'min(/Template/rate,#3)>{$CRIT_THRESHOLD}'
  - uuid: <generate>
    expression: 'min(/Template/rate,#3)>{$CRIT_THRESHOLD}'
    name: 'Rate critical'
    priority: HIGH
```

## Macro Usage Rules (CRITICAL)

**Read first:** [Macros supported by location - Zabbix 7.0 Documentation](https://www.zabbix.com/documentation/7.0/en/manual/appendix/macros/supported_by_location)

### Supported Macros by Location

| Location | User Macros<br/>`{$MACRO}` | LLD Macros<br/>`{#MACRO}` | Built-in<br/>`{ITEM.LASTVALUE}` |
|----------|:---:|:---:|:---:|
| **Trigger names** | ❌ NO | ✅ YES | ✅ YES |
| **Trigger descriptions** | ✅ YES | ✅ YES | ✅ YES |
| **Item prototype names** | ❌ NO | ✅ YES | ❌ NO |
| **Item descriptions** | ✅ YES | ✅ YES | ❌ NO |
| **Trigger expressions** | ✅ YES | ✅ YES | N/A |

### Key Macro Guidelines

1. **ALWAYS use context with user macros in LLD triggers**
   ```yaml
   # ✅ CORRECT - Can be overridden per subscription
   expression: last(...)>{$THRESHOLD:"{#SUBSCRIPTION_ID}"}

   # ❌ WRONG - Cannot be overridden per discovered entity
   expression: last(...)>{$THRESHOLD}
   ```

2. **User macros in trigger names will NOT resolve**
   ```yaml
   # ❌ WRONG - {$THRESHOLD} won't be replaced
   name: 'Alert when value exceeds {$THRESHOLD}'

   # ✅ CORRECT - Use in description instead
   name: 'High value detected'
   description: 'Value exceeds threshold {$THRESHOLD:"{#SUBSCRIPTION_ID}"}'
   ```

3. **LLD macros work in trigger names and item names**
   ```yaml
   # ✅ CORRECT
   name: 'High waste in {#SUBSCRIPTION_NAME}: {ITEM.LASTVALUE}'
   ```

### Per-Entity Override Pattern (LLD + User Macros)

For triggers that need per-entity thresholds:

```yaml
# 1. Define trigger with contextual user macro
trigger_prototypes:
  - expression: last(/Template/item[{#ENTITY_ID}])>{$THRESHOLD:"{#ENTITY_ID}"}
    name: 'Alert for {#ENTITY_NAME}'
    description: 'Value exceeds {$THRESHOLD:"{#ENTITY_ID}"}'

# 2. Define default macro at template level
macros:
  - macro: '{$THRESHOLD}'
    value: '100'
    description: 'Default threshold (override per entity with {$THRESHOLD:"entity-id"})'
```

**Why context matters:**
- `{$THRESHOLD:"{#SUBSCRIPTION_ID}"}` → Can set different values per subscription
- Without context: All subscriptions share the same threshold value

**Official Documentation:**
- [User macros with context](https://www.zabbix.com/documentation/7.0/en/manual/config/macros/user_macros#user-macro-context)
- [User macros supported locations](https://www.zabbix.com/documentation/7.0/en/manual/appendix/macros/supported_by_location_user)

## DOs
- DO keep all UUIDs unique and v4 (32 hex chars for YAML, dashed v4 for XML).
- DO set trapper items when using `zabbix_sender`.
- DO keep macro names in uppercase with braces (`{$MACRO}`) and use LLD macros `{#LLD}` inside keys/expressions.
- DO keep `delay` numeric strings (`'0'`, `1h`, etc.) and history/trends with duration suffix.
- DO mirror per‑subscription keys in the sender script to the template keys exactly.
- DO include valuemaps when items expose coded numeric status.
- **DO ALWAYS add context to user macros in LLD triggers** for per-entity overrides: `{$MACRO:"{#LLD_MACRO}"}`.
- DO verify macro usage against [supported locations table](https://www.zabbix.com/documentation/7.0/en/manual/appendix/macros/supported_by_location).

## DON'Ts
- DON'T mix dashed and non‑dashed UUIDs in the same YAML template.
- DON'T hand-write UUIDs as arbitrary hex strings — always use `uuid.uuid4().hex` in Python. Zabbix validates the v4 version/variant bits.
- DON'T use `key_` in YAML templates — the field is called `key` (no underscore). The API returns `key_` but the import format uses `key`.
- DON'T put triggers as a direct child of the template — single-item triggers go inside the item; multi-item triggers go at the `zabbix_export.triggers` level.
- DON'T use dots after parameter lists (e.g., `key[param].suffix` → invalid).
- DON'T leave item type as `ZABBIX_ACTIVE` when metrics are pushed; imports will pass but data won't arrive.
- DON'T reuse UUIDs between items, prototypes, triggers, or valuemaps.
- DON'T omit template group; the UI import may fail or place the template oddly.
- DON'T rely only on `xmllint`; always run the custom validator or a test import.
- DON'T write YAML from scratch if you can help it — export an existing template and modify it.
- **DON'T use user macros in trigger names** (they won't resolve; use description instead).
- **DON'T use user macros without context in LLD triggers** (prevents per-entity overrides).

## Example key patterns (LLD safe)
- `azure.storage.subscription.waste_monthly[{#SUBSCRIPTION_ID}]`
- `azure.storage.subscription.disk_count[{#SUBSCRIPTION_ID}]`
- `azure.storage.subscription.snapshot_count[{#SUBSCRIPTION_ID}]`
- `azure.storage.subscription.invalid_tags[{#SUBSCRIPTION_ID}]`
- `azure.storage.subscription.excluded_pending_review[{#SUBSCRIPTION_ID}]`

## Example per‑LLD overrideable macro pattern
- Trigger expression: `last(/Azure Storage Cost Monitor/azure.storage.subscription.disk_count[{#SUBSCRIPTION_ID}])>{$UNATTACHED_DISK_THRESHOLD:"{#SUBSCRIPTION_ID}"}`
- Default macro: `{$UNATTACHED_DISK_THRESHOLD}=0` (alert on any), override specific subscriptions with `{$UNATTACHED_DISK_THRESHOLD:"<SUBSCRIPTION_ID>"}=20`, etc.

## One‑liner to regen UUIDs (YAML)
```bash
python - <<'PY'
import uuid, yaml, pathlib
p = pathlib.Path("templates/zabbix-template-azure-storage-cost-analyzer-7.0.yaml")
d = yaml.safe_load(p.read_text())
def walk(o):
    if isinstance(o, dict):
        for k,v in o.items():
            if k=="uuid": o[k]=uuid.uuid4().hex
            else: walk(v)
    elif isinstance(o, list):
        for i in o: walk(i)
walk(d); p.write_text(yaml.safe_dump(d, sort_keys=False))
PY
```

## Final pre‑import checklist
- [ ] UUIDs unique v4, correct dash style.  
- [ ] Keys match sender code; no stray dots after `]`.  
- [ ] Item types correct (TRAP for push).  
- [ ] Discovery macros `{#...}` used consistently in prototypes and triggers.  
- [ ] Validated with `validate-zabbix-template.py`.  
- [ ] Test import on Zabbix 7.0 UI (localhost:8080).  
