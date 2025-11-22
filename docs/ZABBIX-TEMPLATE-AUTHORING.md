# Zabbix Template Authoring (7.0) – Quick Rules

Use this checklist to build or modify Zabbix 7.0 templates without getting blocked on import errors.

## Workflow (do this order)
1) **Pick format first:** Prefer YAML for readability; XML only if required.  
2) **Generate UUIDs:** Use RFC4122 v4 **32‑char hex without dashes** for YAML; with dashes for XML if you stick to XML. Every UUID in the file must be unique.  
3) **Choose item type:** For push data via `zabbix_sender`, set `type: TRAP` (ZABBIX_TRAPPER). Do not leave as active/passive agent unless the agent will collect it.  
4) **Name keys correctly:** Pattern `namespace.metric[param]` – parameters always inside `[]`, no dots after the closing bracket. Example: `azure.storage.subscription.waste_monthly[{#SUBSCRIPTION_ID}]`.  
5) **Discovery first:** Define discovery rule, then item_prototypes/trigger_prototypes referencing its LLD macros.  
6) **Validate locally:** Run `python3 validate-zabbix-template.py <file>` (fast structural check) then import into a local Zabbix 7.0 UI if possible.  
7) **Commit & push:** Keep template + doc in the same change; include rationale in commit message.

## DOs
- DO keep all UUIDs unique and v4 (32 hex chars for YAML, dashed v4 for XML).  
- DO set trapper items when using `zabbix_sender`.  
- DO keep macro names in uppercase with braces (`{$MACRO}`) and use LLD macros `{#LLD}` inside keys/expressions.  
- DO keep `delay` numeric strings (`'0'`, `1h`, etc.) and history/trends with duration suffix.  
- DO mirror per‑subscription keys in the sender script to the template keys exactly.  
- DO include valuemaps when items expose coded numeric status.

## DON’Ts
- DON’T mix dashed and non‑dashed UUIDs in the same YAML template.  
- DON’T use dots after parameter lists (e.g., `key[param].suffix` → invalid).  
- DON’T leave item type as `ZABBIX_ACTIVE` when metrics are pushed; imports will pass but data won’t arrive.  
- DON’T reuse UUIDs between items, prototypes, triggers, or valuemaps.  
- DON’T omit template group; the UI import may fail or place the template oddly.  
- DON’T rely only on `xmllint`; always run the custom validator or a test import.

## Example key patterns (LLD safe)
- `azure.storage.subscription.waste_monthly[{#SUBSCRIPTION_ID}]`
- `azure.storage.subscription.disk_count[{#SUBSCRIPTION_ID}]`
- `azure.storage.subscription.snapshot_count[{#SUBSCRIPTION_ID}]`
- `azure.storage.subscription.invalid_tags[{#SUBSCRIPTION_ID}]`
- `azure.storage.subscription.excluded_pending_review[{#SUBSCRIPTION_ID}]`

## One‑liner to regen UUIDs (YAML)
```bash
python - <<'PY'
import uuid, yaml, pathlib
p = pathlib.Path("zabbix-template-azure-storage-monitor-7.0.yaml")
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
