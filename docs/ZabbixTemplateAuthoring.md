# Zabbix Template Authoring (7.0) – Quick Rules

Use this checklist to build or modify Zabbix 7.0 templates without getting blocked on import errors.

## Workflow (do this order)
1) **Pick format first:** Prefer YAML for readability; XML only if required.  
2) **Generate UUIDs:** Use RFC4122 v4 **32‑char hex without dashes** for YAML; with dashes for XML if you stick to XML. Every UUID in the file must be unique.  
3) **Choose item type:** For push data via `zabbix_sender`, set `type: TRAP` (ZABBIX_TRAPPER). Do not leave as active/passive agent unless the agent will collect it.  
4) **Name keys correctly:** Pattern `namespace.metric[param]` – parameters always inside `[]`, no dots after the closing bracket. Example: `azure.storage.subscription.waste_monthly[{#SUBSCRIPTION_ID}]`.  
5) **Discovery first:** Define discovery rule, then item_prototypes/trigger_prototypes referencing its LLD macros.  
6) **Validate locally:** Run `python3 templates/validate-zabbix-template.py <file>` (fast structural check) then import into a local Zabbix 7.0 UI if possible.  
7) **Commit & push:** Keep template + doc in the same change; include rationale in commit message.

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
- DON'T use dots after parameter lists (e.g., `key[param].suffix` → invalid).
- DON'T leave item type as `ZABBIX_ACTIVE` when metrics are pushed; imports will pass but data won't arrive.
- DON'T reuse UUIDs between items, prototypes, triggers, or valuemaps.
- DON'T omit template group; the UI import may fail or place the template oddly.
- DON'T rely only on `xmllint`; always run the custom validator or a test import.
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
p = pathlib.Path("templates/zabbix-template-azure-storage-monitor-7.0.yaml")
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
