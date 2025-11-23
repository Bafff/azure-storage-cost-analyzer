# Preparing Repository for Public Release

This guide helps you safely make this repository public without exposing sensitive information.

## 🔍 Security Audit Summary

| Category | Status | Action Required |
|----------|--------|-----------------|
| Hardcoded Secrets | ✅ CLEAN | None - No API keys/tokens found |
| Subscription IDs | ⚠️ MODERATE | Replace with example values |
| Resource Group Names | ⚠️ LOW | Replace internal names |
| Email Addresses | ⚠️ LOW | Replace with examples |
| Passwords (test/docs) | ✅ SAFE | Example values only |
| IP Addresses | ✅ CLEAN | None found |
| Git History | ⚠️ REVIEW | Contains subscription IDs since initial commit |

## 📝 Sensitive Information Found

### 1. Azure Subscription IDs
**Files:**
- `azure-storage-cost-analyzer.sh` (line 24)
- `azure-storage-monitor.conf.example` (line 13)
- `docs/PrdZabbixImplementation.md` (line 434)

**Current values:**
- `03d76f78-4676-4116-b53a-162546996207`
- `2f929c0a-d1f4-480c-a610-f75d1862fd53`

**Risk:** MODERATE - Reveals Azure subscription structure but doesn't grant access

### 2. Internal Resource Group Names
**File:** `azure-storage-cost-analyzer.sh` (line 25)

**Current value:**
- `MC_internal-aks-dev-rg_internal-aks-dev_centralus`

**Risk:** LOW - Reveals internal naming conventions

### 3. Company Email Addresses
**File:** `docs/PrdZabbixImplementation.md`

**Current values:**
- `john.doe@company.com`
- `jane.smith@company.com`
- `devops-oncall@company.com`
- `platform-lead@company.com`
- `zabbix-alerts@company.com`

**Risk:** LOW - Reveals organizational structure

## 🛠️ Cleanup Process

### Option 1: Automated Sanitization (Recommended)

Use the provided sanitization script:

```bash
# 1. Make the script executable
chmod +x sanitize-for-public.sh

# 2. Run the sanitization script
./sanitize-for-public.sh

# 3. Review the changes
git diff

# 4. Test the script still works
./azure-storage-cost-analyzer.sh --help

# 5. Commit sanitized version
git add -A
git commit -m "Sanitize repository for public release"
```

### Option 2: Manual Sanitization

**Step 1: Replace Subscription IDs**
```bash
# In azure-storage-cost-analyzer.sh, line 24:
DEFAULT_SUBSCRIPTION_ID="00000000-0000-0000-0000-000000000000"

# In azure-storage-monitor.conf.example, line 13:
# subscriptions = 00000000-0000-0000-0000-000000000000, 11111111-1111-1111-1111-111111111111

# In docs/PrdZabbixImplementation.md, line 434:
# subscriptions = 00000000-0000-0000-0000-000000000000, 11111111-1111-1111-1111-111111111111
```

**Step 2: Replace Resource Group Names**
```bash
# In azure-storage-cost-analyzer.sh, line 25:
DEFAULT_RESOURCE_GROUP="example-resource-group"
```

**Step 3: Replace Email Addresses**
```bash
# In docs/PrdZabbixImplementation.md:
# Replace all @company.com with @example.com
```

## 🔒 Git History Considerations

### ⚠️ Important: History Contains Subscription IDs

The subscription IDs have been in the repository since the **initial commit** (commit `1ae6953`). This means:

1. **Current approach (push sanitized code):**
   - ❌ History still contains subscription IDs
   - ❌ Anyone can view old commits

2. **Recommended approach (create new public repo):**
   - ✅ Clean history without sensitive data
   - ✅ Full control over what's public

### Two Strategies:

#### Strategy A: Keep History (Quick but Less Secure)

If subscription IDs are not highly sensitive:

```bash
# 1. Sanitize current code
./sanitize-for-public.sh

# 2. Commit sanitized version
git add -A
git commit -m "Sanitize for public release"

# 3. Push to GitHub
git push origin main

# 4. Make repository public in GitHub settings
```

**Pros:**
- Quick and simple
- Preserves all commit history
- Shows project evolution

**Cons:**
- ⚠️ Subscription IDs visible in git history
- Anyone can run: `git log -S "03d76f78"`

#### Strategy B: Fresh Public Repository (Recommended)

Create a clean public repository without sensitive history:

```bash
# 1. Sanitize current code
./sanitize-for-public.sh

# 2. Create a new orphan branch (no history)
git checkout --orphan public-main

# 3. Add all files
git add -A

# 4. Create initial commit
git commit -m "Initial public release: Azure Storage Cost Analyzer

CLI tooling to discover and quantify wasted Azure storage spend
(unattached disks and snapshots) with Zabbix integration."

# 5. Create new public repository on GitHub
# (Do this manually in GitHub UI: https://github.com/new)

# 6. Push to new public repository
git remote add public https://github.com/yourusername/azure-storage-cost-analyzer.git
git push public public-main:main

# 7. Keep private repo for development
# Continue using original repo for private development
```

**Pros:**
- ✅ Clean history with no sensitive data
- ✅ Full control over public content
- ✅ Can still use private repo for development

**Cons:**
- Loses commit history (can preserve in private repo)
- Requires maintaining two remotes

## 📋 Pre-Release Checklist

Before making the repository public:

### Code Cleanup
- [ ] Run `./sanitize-for-public.sh`
- [ ] Review changes with `git diff`
- [ ] Search for subscription IDs: `git grep -E "[0-9a-f]{8}-[0-9a-f]{4}"`
- [ ] Search for company emails: `git grep "@company\.com"`
- [ ] Search for internal references: `git grep "internal-"`
- [ ] Test script with example values: `./azure-storage-cost-analyzer.sh --help`

### Documentation Review
- [ ] Update README.md with installation instructions
- [ ] Ensure all documentation uses example values
- [ ] Add LICENSE file (if not present)
- [ ] Add CONTRIBUTING.md guidelines
- [ ] Add CODE_OF_CONDUCT.md
- [ ] Review all docs for internal references

### Repository Settings
- [ ] Add repository description
- [ ] Add topics/tags (azure, cost-optimization, monitoring, zabbix)
- [ ] Enable GitHub Issues
- [ ] Enable GitHub Discussions (optional)
- [ ] Configure GitHub Actions permissions
- [ ] Set up branch protection rules (optional)

### Legal/Licensing
- [ ] Confirm you have rights to open-source this code
- [ ] Add appropriate LICENSE file (MIT, Apache 2.0, etc.)
- [ ] Review any third-party dependencies and their licenses
- [ ] Ensure no proprietary code or libraries are included

## 🎯 Recommended Approach

**For Maximum Security:**

1. ✅ Use **Strategy B** (Fresh Public Repository)
2. ✅ Run sanitization script
3. ✅ Create new public repo with clean history
4. ✅ Keep original private repo for development
5. ✅ Sync public repo periodically with sanitized code

**If Speed is Priority:**

1. ⚠️ Use **Strategy A** (Keep History)
2. ✅ Run sanitization script
3. ⚠️ Accept that subscription IDs will be in git history
4. ✅ Make current repository public

## 🔐 Additional Security Recommendations

### 1. Add .gitignore for Secrets
```bash
# Add to .gitignore
*.env
*.env.local
*.secret
credentials.json
service-principal.json
.azure/
```

### 2. Add GitHub Secret Scanning
Once public, GitHub will automatically:
- Scan for leaked secrets
- Alert you if secrets are detected
- Block pushes containing known secret patterns

### 3. Document Security Practices
Add to README.md:
```markdown
## Security

- Never commit credentials or secrets
- Use Azure Managed Identity when possible
- Store secrets in Azure Key Vault or GitHub Secrets
- Use Service Principal with minimal required permissions
```

## ✅ Post-Release Actions

After making the repository public:

1. **Monitor Security Alerts**
   - Check GitHub Security tab regularly
   - Enable Dependabot alerts
   - Review secret scanning alerts

2. **Engage Community**
   - Respond to issues promptly
   - Review pull requests
   - Update documentation based on feedback

3. **Maintain Documentation**
   - Keep README.md up to date
   - Add examples and use cases
   - Document common issues/FAQ

## 📞 Need Help?

If you're unsure about any step:
- Review GitHub's guide: https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/managing-repository-settings/setting-repository-visibility
- Consult your organization's security team
- Start with a private repository and invite trusted reviewers

## 🎉 Ready to Go Public?

Once you've completed the checklist:

```bash
# For new public repo (Recommended):
./sanitize-for-public.sh
git checkout --orphan public-main
git add -A
git commit -m "Initial public release"
git remote add public https://github.com/yourusername/azure-storage-cost-analyzer.git
git push public public-main:main
```

Then go to GitHub repository settings and set visibility to "Public"!
