# Add Comprehensive Linting Infrastructure with Zabbix 7.0 Template Validation

## Summary

Introduces comprehensive linting infrastructure for the Azure Storage Cost Analyzer project, including bash script validation, XML/YAML linting, and specialized Zabbix 7.0 template validation.

## Changes Overview

### 🔧 Linting Infrastructure (6 CI Jobs)

1. **ShellCheck** - Static analysis for bash scripts
   - Validates all 6 bash scripts (5,274 lines total)
   - Configuration: `.shellcheckrc`

2. **xmllint** - XML syntax validation
   - Validates Zabbix template XML structure

3. **yamllint** - YAML validation
   - Validates Azure Pipelines and workflow files
   - Configuration: `.yamllint`

4. **bash-syntax** - Native bash syntax checking
   - Quick validation with `bash -n`

5. **zabbix-template-validation** - Comprehensive Zabbix checks ⭐ NEW
   - Validates Zabbix 7.0 template structure and best practices
   - Uses standalone Python validator

6. **summary** - Consolidated results display

### 📋 New Files

- ✅ `.github/workflows/lint.yml` - GitHub Actions CI workflow
- ✅ `.shellcheckrc` - ShellCheck configuration
- ✅ `.yamllint` - YAML linting rules
- ✅ `validate-zabbix-template.py` - **Standalone Zabbix validator** ⭐
- ✅ `LINTING.md` - Complete linting guide
- ✅ `ZABBIX-VALIDATION-TOOLS.md` - Tool comparison guide ⭐

### 🎯 Zabbix 7.0 Template Validator

**Comprehensive standalone Python script** that validates:

#### Structure Validation
- ✅ XML syntax and well-formedness
- ✅ Root element (`<zabbix_export>`)
- ✅ Zabbix version compatibility (7.0+)
- ✅ Template structure and metadata

#### Component Validation
- ✅ **Items**: Keys, value types, duplicates
- ✅ **Triggers**: Expressions, priorities, syntax
- ✅ **Discovery Rules**: LLD validation, item prototypes
- ✅ **Macros**: Naming conventions (`{$UPPERCASE}`), duplicates
- ✅ **UUIDs**: Format validation (dashed/non-dashed)

#### Zabbix 7.0 Features
- ✅ String constants: `FLOAT`, `UNSIGNED`, `WARNING`, `HIGH`
- ✅ Numeric constants: `0-5` (priorities), `0-16` (value types)
- ✅ Both UUID formats supported
- ✅ Trigger expression syntax validation

#### Usage
```bash
# Validate specific template
python3 validate-zabbix-template.py zabbix-template-azure-storage-monitor-7.0.xml

# Validate all templates
python3 validate-zabbix-template.py --all
```

### 📊 Tool Comparison (ZABBIX-VALIDATION-TOOLS.md)

Comprehensive guide comparing 4 validation approaches:

| Tool | Best For | Zabbix 7.0 |
|------|----------|-----------|
| **Custom Validator** ⭐ | CI/CD, Development | ✅ Full Support |
| **PyZabbix** | Production Validation | ✅ Full Support |
| **Zabbix CLI** | Manual Operations | ✅ Supported (v2.3.0+) |
| **xmllint** | Quick Syntax Check | ✅ Yes |

**Recommendation**: Custom validator is ideal for CI/CD (fast, offline, no auth required)

### 🚀 CI/CD Integration

**Workflow triggers:**
- Every push to `main`, `master`, `develop`, or `claude/**` branches
- Every pull request targeting `main`, `master`, or `develop`

**All jobs must pass for CI to succeed** ✅

### 📝 Documentation

- **LINTING.md**: Complete guide for running linters locally
  - Installation instructions (apt/brew)
  - Usage examples for each linter
  - Configuration file documentation
  - Pre-commit hook setup
  - IDE integration (VS Code, Vim)
  - Troubleshooting guide

- **ZABBIX-VALIDATION-TOOLS.md**: Tool comparison and recommendations
  - Feature comparison matrix
  - Zabbix 7.0 support status
  - Use case recommendations
  - Workflow guidance

### 🔍 Validation Results

Successfully validates the existing Zabbix template:
- ✅ `zabbix-template-azure-storage-monitor-7.0.xml`
- ✅ All structure checks pass
- ✅ No errors or warnings

### 💡 Key Benefits

1. **Automated Quality Checks**: Catch issues before they reach production
2. **Zabbix 7.0 Optimized**: Full support for latest format
3. **Fast Feedback**: Validation runs in seconds
4. **No External Dependencies**: Works offline, no Zabbix server needed
5. **Comprehensive Coverage**: 6 different linting jobs
6. **Developer Friendly**: Clear error messages and documentation

### 🎯 Testing

All linters tested and validated:
- ✅ ShellCheck runs successfully on all bash scripts
- ✅ XML validation passes for Zabbix template
- ✅ YAML validation passes for workflows
- ✅ Zabbix validator successfully validates template
- ✅ Workflow YAML syntax verified

### 📚 Commits Included

1. **Add comprehensive linting infrastructure for bash, XML, and YAML files**
   - GitHub Actions workflow with 5 initial jobs
   - ShellCheck, xmllint, yamllint, bash-syntax validation
   - Configuration files (.shellcheckrc, .yamllint)
   - LINTING.md documentation

2. **Add Zabbix-specific template validation to CI workflow**
   - Inline Python validation for Zabbix templates
   - Structure validation and component checking
   - Enhanced LINTING.md with Zabbix section

3. **Add comprehensive standalone Zabbix template validator with tool comparison**
   - Standalone `validate-zabbix-template.py` script
   - Zabbix 7.0 string/numeric constant support
   - UUID format validation (dashed/non-dashed)
   - Trigger, macro, and item validation
   - Tool comparison guide (ZABBIX-VALIDATION-TOOLS.md)
   - Simplified CI workflow using standalone script

## How to Review

1. **Check the workflow**: `.github/workflows/lint.yml`
2. **Try the validator locally**:
   ```bash
   python3 validate-zabbix-template.py --all
   ```
3. **Review documentation**: `LINTING.md` and `ZABBIX-VALIDATION-TOOLS.md`
4. **Verify CI passes**: Check GitHub Actions workflow results

## Next Steps

After merge:
- Linters will run automatically on every push
- Developers can run validation locally
- Template changes will be validated before deployment

---

**All tools support Zabbix 7.0!** ✅
