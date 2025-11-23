# Linting Guide for Azure Storage Cost Analyzer

This project uses automated linting to ensure code quality and consistency across all bash scripts, XML templates, and YAML configuration files.

## Overview

The following linters are configured:

1. **ShellCheck** - Static analysis for bash scripts
2. **xmllint** - XML validation for Zabbix templates
3. **yamllint** - YAML syntax and style validation
4. **Bash Syntax Check** - Native bash syntax validation
5. **Zabbix Template Validator** - Zabbix-specific template structure validation

## GitHub Actions CI

All linting checks run automatically on:
- Every push to `main`, `master`, `develop`, or `claude/**` branches
- Every pull request targeting `main`, `master`, or `develop` branches

View the workflow: `.github/workflows/lint.yml`

## Running Linters Locally

### Prerequisites

Install the required tools:

```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install -y shellcheck libxml2-utils python3-pip
pip3 install yamllint

# macOS
brew install shellcheck libxml2 yamllint
```

### ShellCheck (Bash Linting)

Lint all bash scripts:

```bash
# Lint a specific file
shellcheck azure-storage-cost-analysis-enhanced.sh

# Lint all .sh files
find . -name "*.sh" -type f -exec shellcheck {} \;

# Lint with specific severity (error, warning, info, style)
shellcheck --severity=warning *.sh
```

Configuration file: `.shellcheckrc`

Common ShellCheck codes:
- `SC2086`: Quote variables to prevent word splitting
- `SC2154`: Variable is referenced but not assigned
- `SC2034`: Variable appears unused
- `SC1090`: Can't follow non-constant source

### XML Validation (Zabbix Templates)

Validate Zabbix template XML:

```bash
# Validate XML syntax
xmllint --noout zabbix-template-*.xml

# Check and format XML
xmllint --format zabbix-template-*.xml

# Validate all XML files
find . -name "*.xml" -type f -exec xmllint --noout {} \;
```

### YAML Validation

Lint YAML files:

```bash
# Lint specific file
yamllint azure-pipelines-storage-monitor.yml

# Lint all YAML files
find . -name "*.yml" -o -name "*.yaml" -type f -exec yamllint {} \;

# Use project configuration
yamllint -c .yamllint *.yml
```

Configuration file: `.yamllint`

### Bash Syntax Check

Quick syntax validation:

```bash
# Check syntax without executing
bash -n azure-storage-cost-analysis-enhanced.sh

# Check all scripts
find . -name "*.sh" -type f -exec bash -n {} \; && echo "All scripts have valid syntax"
```

### Zabbix Template Validation

Comprehensive Zabbix-specific template validation using the standalone validator:

```bash
# Validate a specific template
python3 validate-zabbix-template.py zabbix-template-azure-storage-monitor-7.0.yaml

# Validate all templates in current directory
python3 validate-zabbix-template.py --all

# The script is executable, so you can also run:
./validate-zabbix-template.py zabbix-template-azure-storage-monitor-7.0.yaml
```

**The validator (`validate-zabbix-template.py`) is a comprehensive standalone script that checks:**
- Template structure and XML syntax
- Zabbix version compatibility (optimized for 7.0+)
- UUID format (both dashed and non-dashed formats)
- Item validation (keys, value types, duplicate detection)
- Discovery rules and item prototypes
- Trigger expressions and priority levels
- Macro naming conventions
- Template groups and metadata

**Supports both Zabbix 7.0 formats:**
- Numeric constants: `<value_type>0</value_type>` (FLOAT)
- String constants: `<value_type>FLOAT</value_type>` ✅ Recommended

**What the Zabbix validator checks:**
- Root element is `<zabbix_export>`
- Version element is present
- Templates section exists
- Each template has a name
- UUIDs are present (recommended for Zabbix 7.0+)
- Item keys don't contain spaces
- Value types are properly formatted
- Trigger expressions are valid
- No duplicate UUIDs

**Common Zabbix template issues:**
- Missing or malformed UUIDs
- Item keys with spaces (should use dots/underscores)
- Invalid trigger expressions
- Incorrect value type codes
- Missing mandatory elements (name, key, etc.)

## Configuration Files

### `.shellcheckrc`
- Configures ShellCheck behavior
- Enables/disables specific checks
- Sets shell dialect and severity level

### `.yamllint`
- Configures YAML linting rules
- Sets line length, indentation, and style preferences
- Extends the "relaxed" preset

## Fixing Common Issues

### ShellCheck Warnings

**Quote variables:**
```bash
# Bad
echo $VAR

# Good
echo "$VAR"
```

**Check variable assignment:**
```bash
# Bad
if [ $? -eq 0 ]; then

# Good
if [ "$?" -eq 0 ]; then
# Or better: check exit status directly
if command; then
```

### XML Formatting

Format XML files:
```bash
xmllint --format zabbix-template-*.xml > temp.xml
mv temp.xml zabbix-template-*.xml
```

### YAML Formatting

Common YAML issues:
- Use 2 spaces for indentation (not tabs)
- Keep line length under 150 characters
- Add space after comment hash (#)
- Remove trailing whitespace

## Pre-commit Hook (Optional)

Create a pre-commit hook to run linters automatically:

```bash
# Create hook file
cat > .git/hooks/pre-commit << 'EOF'
#!/bin/bash
set -e

echo "Running pre-commit linters..."

# ShellCheck
find . -name "*.sh" -type f -exec shellcheck {} \;

# XML validation
find . -name "*.xml" -type f -exec xmllint --noout {} \;

# YAML validation
find . -name "*.yml" -o -name "*.yaml" -type f -exec yamllint {} \;

echo "✓ All linters passed!"
EOF

# Make executable
chmod +x .git/hooks/pre-commit
```

## Integration with IDEs

### VS Code

Install extensions:
- [ShellCheck](https://marketplace.visualstudio.com/items?itemName=timonwong.shellcheck)
- [XML Tools](https://marketplace.visualstudio.com/items?itemName=DotJoshJohnson.xml)
- [YAML](https://marketplace.visualstudio.com/items?itemName=redhat.vscode-yaml)

### Vim/Neovim

Use ALE or similar linting plugins:
```vim
let g:ale_linters = {
\   'sh': ['shellcheck'],
\   'xml': ['xmllint'],
\   'yaml': ['yamllint'],
\}
```

## CI/CD Workflow Jobs

The lint workflow includes the following jobs:

1. **shellcheck** - Scans all bash scripts with ShellCheck
2. **xmllint** - Validates XML syntax and formatting
3. **yamllint** - Validates YAML syntax and style
4. **bash-syntax** - Performs bash syntax check (-n flag)
5. **zabbix-template-validation** - Zabbix-specific template structure validation
   - Validates Zabbix XML structure (root, version, templates)
   - Checks for proper UUIDs, item keys, and trigger expressions
   - Ensures template naming and grouping conventions
   - Detects duplicate UUIDs and malformed elements
6. **summary** - Provides consolidated results from all jobs

All jobs must pass for the workflow to succeed.

## Troubleshooting

### Workflow Fails on Push

1. Run linters locally to identify issues
2. Fix reported problems
3. Commit and push again

### False Positives

If ShellCheck reports false positives:

1. Add inline directive:
```bash
# shellcheck disable=SC2086
echo $VARIABLE
```

2. Or update `.shellcheckrc`:
```
disable=SC2086
```

### XML Validation Fails

Ensure XML is well-formed:
- All tags are properly closed
- Attributes are quoted
- No special characters without escaping
- Valid UTF-8 encoding

## Resources

- [ShellCheck Wiki](https://www.shellcheck.net/wiki/)
- [xmllint Documentation](http://xmlsoft.org/xmllint.html)
- [yamllint Documentation](https://yamllint.readthedocs.io/)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)

## Questions or Issues?

If you encounter linting issues or have questions:

1. Check the specific linter documentation
2. Review configuration files (`.shellcheckrc`, `.yamllint`)
3. Run linters locally with verbose output
4. Open an issue in the repository

---

**Last Updated:** 2025-11-20
