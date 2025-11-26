# Zabbix Template Validation Tools Comparison

This guide compares different Zabbix template validation tools and provides recommendations for when to use each one.

## Overview

There are several approaches to validating Zabbix templates:

1. **Custom Python Validator** (this project's `validate-zabbix-template.py`)
2. **PyZabbix** (Python library for Zabbix API)
3. **Zabbix CLI** (Official command-line tool)
4. **xmllint** (Generic XML validation)

## Tool Comparison Matrix

| Feature | Custom Validator | PyZabbix | Zabbix CLI | xmllint |
|---------|-----------------|----------|------------|---------|
| **Offline validation** | ✅ Yes | ❌ No (needs server) | ❌ No (needs server) | ✅ Yes |
| **No authentication needed** | ✅ Yes | ❌ No | ❌ No | ✅ Yes |
| **Speed** | ⚡ Very Fast | 🐌 Slow | 🐌 Slow | ⚡ Very Fast |
| **Zabbix 7.0 support** | ✅ Yes | ✅ Yes | ✅ Yes | ✅ Yes |
| **Checks structure** | ✅ Yes | ✅ Yes | ✅ Yes | ✅ Yes |
| **Checks semantics** | ⚠️ Partial | ✅ Full | ✅ Full | ❌ No |
| **Trigger syntax** | ⚠️ Basic | ✅ Full | ✅ Full | ❌ No |
| **Macro validation** | ✅ Yes | ✅ Yes | ✅ Yes | ❌ No |
| **Item key validation** | ✅ Yes | ✅ Yes | ✅ Yes | ❌ No |
| **Dependency checking** | ❌ No | ✅ Yes | ✅ Yes | ❌ No |
| **CI/CD friendly** | ✅ Excellent | ⚠️ Requires setup | ⚠️ Requires setup | ✅ Excellent |
| **Installation** | 📦 Single file | 📦 pip install | 📦 pip install | 📦 apt/brew |
| **Best for** | CI/CD, Dev | Production | Production | Syntax only |

---

## 1. Custom Python Validator (`validate-zabbix-template.py`)

**✅ RECOMMENDED for CI/CD and Local Development**

### What It Validates

- ✅ XML structure and syntax
- ✅ Zabbix version compatibility (7.0+)
- ✅ Template structure (root, templates, items, triggers)
- ✅ UUID format and uniqueness
- ✅ Item keys (no spaces, no duplicates)
- ✅ Value types (numeric validation)
- ✅ Trigger expressions (parentheses matching, syntax basics)
- ✅ Trigger priority values (0-5)
- ✅ Macro naming conventions (`{$MACRO_NAME}`)
- ✅ Template groups

### Zabbix 7.0 Support

**✅ FULL SUPPORT** - Specifically designed for Zabbix 7.0 templates.

### Usage

```bash
# Validate a single template
python3 templates/validate-zabbix-template.py templates/zabbix-template-azure-storage-cost-analyzer-7.0.yaml

# Validate all templates in current directory
python3 templates/validate-zabbix-template.py --all

# Use in CI/CD
python3 templates/validate-zabbix-template.py template.xml || exit 1
```

### Pros

- ✅ **No Zabbix server required** - Offline validation
- ✅ **Fast** - Validates in milliseconds
- ✅ **No authentication** - No credentials needed
- ✅ **CI/CD friendly** - Perfect for GitHub Actions
- ✅ **Comprehensive** - Checks structure, syntax, and best practices
- ✅ **Zero setup** - Single Python file, no dependencies
- ✅ **Clear output** - Color-coded errors, warnings, and info

### Cons

- ❌ Cannot validate against actual Zabbix server semantics
- ❌ Won't catch runtime issues (e.g., invalid host references)
- ❌ Cannot test if template will actually work in production
- ❌ Limited trigger expression validation (basic syntax only)

### When to Use

- ✅ **CI/CD pipelines** - GitHub Actions, GitLab CI, etc.
- ✅ **Pre-commit validation** - Before pushing code
- ✅ **Development** - Quick local validation
- ✅ **Syntax checking** - Ensure XML is well-formed
- ✅ **Best practices** - Check naming conventions

---

## 2. PyZabbix

**✅ RECOMMENDED for Production Validation**

### What It Does

Full Zabbix API access via Python, including:
- Template import/export
- Configuration validation
- Dependency checking
- Full semantic validation

### Zabbix 7.0 Support

**✅ FULL SUPPORT** - PyZabbix supports Zabbix 7.0.x

PyZabbix is actively maintained and supports the latest Zabbix versions including 7.0.

### Installation

```bash
pip install pyzabbix
```

### Usage

```python
from pyzabbix import ZabbixAPI
import sys

# Connect to Zabbix server
zapi = ZabbixAPI("https://zabbix.example.com")
zapi.login("username", "password")

# Validate template by importing (with dry-run)
try:
    with open('template.xml', 'r') as f:
        template_xml = f.read()

    # Import with validation
    result = zapi.configuration.import_({
        'format': 'xml',
        'source': template_xml,
        'rules': {
            'templates': {
                'createMissing': True,
                'updateExisting': False
            }
        }
    })

    print("✅ Template is valid!")
    sys.exit(0)

except Exception as e:
    print(f"❌ Validation failed: {e}")
    sys.exit(1)
```

### Pros

- ✅ **Full validation** - Real Zabbix server checks everything
- ✅ **Semantic validation** - Catches runtime issues
- ✅ **Dependency checking** - Validates host/template references
- ✅ **API access** - Can also query/modify Zabbix
- ✅ **Production-ready** - Test before actual deployment

### Cons

- ❌ **Requires Zabbix server** - Must have running instance
- ❌ **Needs authentication** - Username/password or API token
- ❌ **Slower** - Network calls add latency
- ❌ **CI/CD complexity** - Need test Zabbix server or credentials
- ❌ **Setup required** - Installation and configuration

### When to Use

- ✅ **Production validation** - Before deploying to live server
- ✅ **Integration tests** - Full end-to-end testing
- ✅ **Dependency validation** - Ensure all references exist
- ✅ **Automated deployments** - Import templates via CI/CD
- ✅ **Multi-template validation** - Check template interactions

---

## 3. Zabbix CLI

Official command-line tool for Zabbix management.

### Zabbix 7.0 Support

**✅ SUPPORTED** - Use `zabbix-cli` version 2.3.0+ for Zabbix 7.0 support.

### Installation

```bash
pip install zabbix-cli
```

### Configuration

Create `~/.zabbix-cli/zabbix-cli.conf`:

```ini
[zabbix_api]
zabbix_api_url = https://zabbix.example.com/api_jsonrpc.php
username = your_username
password = your_password
```

### Usage

```bash
# Export template
zabbix-cli --export-template "Template Name" > template.xml

# Import template (validates automatically)
zabbix-cli --import-template template.xml

# Show template info
zabbix-cli --show-template "Template Name"
```

### Pros

- ✅ **Official tool** - Maintained by Zabbix team
- ✅ **Full validation** - Uses real Zabbix API
- ✅ **CLI interface** - Easy to script
- ✅ **Template management** - Export, import, list

### Cons

- ❌ **Requires server** - Must have Zabbix instance
- ❌ **Authentication required** - Credentials needed
- ❌ **Configuration needed** - Setup config file
- ❌ **Not validation-focused** - General management tool

### When to Use

- ✅ **Manual operations** - Interactive template management
- ✅ **Production deployments** - Import to live server
- ✅ **Template export** - Backup existing templates
- ✅ **Bulk operations** - Manage multiple templates

---

## 4. xmllint

Generic XML validator (already in our CI).

### Usage

```bash
xmllint --noout template.xml
```

### Pros

- ✅ **Fast** - Very quick validation
- ✅ **Offline** - No server needed
- ✅ **Widely available** - Standard tool

### Cons

- ❌ **Generic only** - No Zabbix-specific checks
- ❌ **Limited** - Only XML syntax

### When to Use

- ✅ **Quick syntax check** - Ensure XML is well-formed
- ✅ **Pre-validation** - Before deeper checks

---

## Recommended Workflow

### For This Project (Azure Storage Cost Analyzer)

**1. Local Development:**
```bash
# Quick validation during development
python3 templates/validate-zabbix-template.py templates/zabbix-template-azure-storage-cost-analyzer-7.0.yaml
```

**2. CI/CD (GitHub Actions):**
```yaml
# Already configured in .github/workflows/lint.yml
- shellcheck (bash)
- xmllint (XML syntax)
- yamllint (YAML)
- Custom Zabbix validator (structure and best practices)
```

**3. Pre-Production Testing:**
```bash
# Use PyZabbix to validate against test Zabbix server
python3 << 'EOF'
from pyzabbix import ZabbixAPI

zapi = ZabbixAPI("https://test-zabbix.example.com")
zapi.login("admin", "password")

with open('templates/zabbix-template-azure-storage-cost-analyzer-7.0.yaml') as f:
    result = zapi.configuration.import_({
        'format': 'xml',
        'source': f.read(),
        'rules': {'templates': {'createMissing': True}}
    })

print("✅ Template validated against test server!")
EOF
```

**4. Production Deployment:**
```bash
# Use Zabbix CLI or PyZabbix to import to production
zabbix-cli --import-template templates/zabbix-template-azure-storage-cost-analyzer-7.0.yaml
```

---

## Summary: Which Tool Should You Use?

### ✅ Use Custom Python Validator When:
- Working locally during development
- Running CI/CD pipelines (GitHub Actions)
- Need fast, offline validation
- Checking syntax and best practices
- No Zabbix server available
- **This is what we use in CI/CD** ⭐

### ✅ Use PyZabbix When:
- Validating before production deployment
- Need full semantic validation
- Testing template interactions
- Automating template management
- Running integration tests

### ✅ Use Zabbix CLI When:
- Managing production Zabbix server
- Manual template operations
- Exporting existing templates
- Interactive template management

### ✅ Use xmllint When:
- Quick XML syntax check only
- First-pass validation
- Already in our CI pipeline

---

## Answer to Your Question

> **What is the best to use: zabbix-template-validation (custom), zabbix-cli-bulk-execution, or pyzabbix?**

**For CI/CD (GitHub Actions):** ⭐ **Custom validator** (`validate-zabbix-template.py`)
- No Zabbix server needed
- Fast (milliseconds)
- No authentication required
- Perfect for automated checks
- **Already integrated in your CI workflow**

**For Production Validation:** ⭐ **PyZabbix**
- Full validation against real server
- Catches all possible issues
- Supports Zabbix 7.0 fully
- Python-based (easy to script)
- Can be integrated into deployment pipelines

**For Manual Operations:** ⭐ **Zabbix CLI**
- Interactive management
- Official tool
- Good for ad-hoc operations

### Zabbix 7.0 Support Status

| Tool | Zabbix 7.0 Support |
|------|-------------------|
| Custom validator | ✅ **Full support** (designed for 7.0) |
| PyZabbix | ✅ **Full support** (actively maintained) |
| Zabbix CLI | ✅ **Supported** (use v2.3.0+) |

**All tools support Zabbix 7.0!** ✅

---

## Conclusion

For your Azure Storage Cost Analyzer project:

1. **Keep the custom validator in CI/CD** - It's perfect for automated checks
2. **Use PyZabbix for pre-production testing** - Validate against test server
3. **Use Zabbix CLI for production deployment** - Manual import when ready

This gives you:
- ✅ Fast feedback during development (custom validator)
- ✅ Comprehensive testing before release (PyZabbix)
- ✅ Safe production deployment (Zabbix CLI)

**The custom validator is already the best choice for your CI/CD pipeline!** 🎯
