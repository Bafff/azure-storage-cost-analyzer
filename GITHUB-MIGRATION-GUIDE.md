# GitHub Migration Guide - Azure Storage Cost Analyzer

**Goal:** Push this script to GitHub for easier development, then sync changes back to ADO.

---

## 🎯 Strategy Overview

### Recommended: Separate GitHub Repo ⭐

**Best for:**
- Keeping other scripts private in ADO
- Clean separation of concerns
- Potential open-source contribution
- Easier collaboration

**Workflow:**
```
GitHub Repo (public/private)
    ↓ (develop here)
    ↓
Manual sync or git remote
    ↓
ADO Repo (private, full scripts collection)
```

---

## 📋 Option 1: Fresh GitHub Repo (RECOMMENDED)

### Pros
- ✅ Clean, standalone repository
- ✅ No risk of exposing other scripts
- ✅ Easy to make public or private
- ✅ Simple CI/CD setup
- ✅ Clear ownership and purpose

### Cons
- ❌ Loses detailed git history (but you have migration commit documented)
- ❌ Manual sync process back to ADO

### Implementation Steps

#### Step 1: Create New GitHub Repo

**Option A: Using GitHub CLI**
```bash
# Navigate to a clean directory
cd ~/Documents/Repos
mkdir azure-storage-cost-analyzer
cd azure-storage-cost-analyzer

# Initialize git
git init
git branch -M main

# Copy files
cp -r ~/Documents/Repos/Arkadium/IT/Scripts/Azure/storage-cost-analyzer/* .

# Create .gitignore
cat > .gitignore << 'EOF'
# Test outputs
*.json
*.txt
!*.example.*

# Temp files
*.tmp
*.log

# macOS
.DS_Store

# Editor
.vscode/
.idea/
*.swp
EOF

# Initial commit
git add .
git commit -m "Initial commit: Azure Storage Cost Analyzer

Migrated from internal Azure DevOps repository.

Features:
- Multi-subscription scanning across all Azure subscriptions
- Zabbix 7.0.5 integration with LLD support
- Batch API optimization (30-40x performance improvement)
- Tag-based exclusion for approved exceptions (70% complete)
- Azure DevOps pipeline integration
- JSON/Text/Zabbix output formats

See IMPLEMENTATION-STATUS.md for complete feature list.
See TODO.md for remaining work on tag exclusion feature."

# Create GitHub repo (choose public or private)
gh repo create azure-storage-cost-analyzer \
  --public \  # or --private
  --source=. \
  --remote=origin \
  --description "Azure Storage Cost Analyzer - Monitor unattached disks and snapshots with Zabbix integration"

# Push to GitHub
git push -u origin main
```

**Option B: Using GitHub Web Interface**
1. Go to https://github.com/new
2. Repository name: `azure-storage-cost-analyzer`
3. Description: "Azure Storage Cost Analyzer - Monitor unattached disks and snapshots with Zabbix integration"
4. Choose Public or Private
5. **Don't** initialize with README (you already have one)
6. Create repository

Then:
```bash
# In your local directory
git remote add origin git@github.com:yourusername/azure-storage-cost-analyzer.git
git push -u origin main
```

#### Step 2: Add ADO as Remote (for syncing back)

```bash
# Add ADO repo as additional remote
git remote add ado https://dev.azure.com/arkadium/IT/_git/Scripts

# Fetch ADO branches
git fetch ado

# Create branch for syncing back to ADO
git checkout -b ado-sync
git checkout main
```

#### Step 3: Development Workflow

**Daily work (in GitHub repo):**
```bash
cd ~/Documents/Repos/azure-storage-cost-analyzer

# Create feature branch
git checkout -b feature/tag-exclusion-integration

# Make changes
# ... edit files ...

# Commit and push to GitHub
git add .
git commit -m "Implement tag filtering in collect_subscription_metrics()"
git push origin feature/tag-exclusion-integration

# Create PR on GitHub, review, merge to main
```

**Sync back to ADO (weekly or after major milestones):**
```bash
# Pull latest from GitHub main
git checkout main
git pull origin main

# Checkout ADO sync branch
git checkout ado-sync
git pull ado master  # or feature/azure-storage-cost-analyzer-migration

# Copy changes from main
git checkout main -- .

# Review changes
git status
git diff

# Commit for ADO
git add .
git commit -m "Sync from GitHub: Tag exclusion integration complete

Changes:
- Implemented tag-based exclusion feature
- Updated Zabbix template with invalid_tags metrics
- Added comprehensive testing documentation

Synced from GitHub repo: https://github.com/yourusername/azure-storage-cost-analyzer"

# Push to ADO
git push ado ado-sync:feature/azure-storage-cost-analyzer-migration

# Go back to main development
git checkout main
```

---

## 📋 Option 2: Git Subtree (Preserve History)

### Pros
- ✅ Preserves full git history
- ✅ Can sync in both directions
- ✅ Git-native solution

### Cons
- ❌ More complex setup
- ❌ Can accidentally expose other files if misconfigured
- ❌ Harder to understand for team members

### Implementation

**In your ADO repo:**
```bash
cd ~/Documents/Repos/Arkadium/IT/Scripts/Azure

# Create subtree split (extracts history for just this directory)
git subtree split --prefix=storage-cost-analyzer -b github-storage-analyzer

# Create new repo directory
cd ~/Documents/Repos
mkdir azure-storage-cost-analyzer
cd azure-storage-cost-analyzer

# Initialize and pull the subtree
git init
git pull ~/Documents/Repos/Arkadium github-storage-analyzer

# Add GitHub remote
git remote add origin git@github.com:yourusername/azure-storage-cost-analyzer.git
git push -u origin main

# Add ADO remote for syncing
git remote add ado https://dev.azure.com/arkadium/IT/_git/Scripts
```

**To sync back to ADO:**
```bash
# In GitHub repo
git push origin main

# In ADO repo
cd ~/Documents/Repos/Arkadium/IT/Scripts/Azure
git subtree pull --prefix=storage-cost-analyzer \
  https://github.com/yourusername/azure-storage-cost-analyzer main
```

---

## 📋 Option 3: Keep in ADO, Use GitHub Mirror

### Pros
- ✅ Single source of truth (ADO)
- ✅ Automated mirroring
- ✅ No manual sync needed

### Cons
- ❌ Requires ADO pipeline setup
- ❌ Can't easily make just this script public
- ❌ GitHub repo is read-only (no PRs)

**Not recommended for your use case.**

---

## 🔄 Recommended Workflow

### Setup (One-time)

```bash
# 1. Create GitHub repo (fresh)
cd ~/Documents/Repos
mkdir azure-storage-cost-analyzer
cd azure-storage-cost-analyzer
git init

# 2. Copy current state
cp -r ~/Documents/Repos/Arkadium/IT/Scripts/Azure/storage-cost-analyzer/* .
git add .
git commit -m "Initial commit from ADO migration"

# 3. Push to GitHub
gh repo create azure-storage-cost-analyzer --public --source=.
git push -u origin main

# 4. Add ADO remote
git remote add ado https://dev.azure.com/arkadium/IT/_git/Scripts
```

### Daily Development

**Work in GitHub repo:**
```bash
cd ~/Documents/Repos/azure-storage-cost-analyzer

# Create feature branch
git checkout -b feature/tag-exclusion

# Make changes
vim azure-storage-cost-analysis-enhanced.sh

# Commit
git add .
git commit -m "Add tag filtering to collect_subscription_metrics"

# Push to GitHub
git push origin feature/tag-exclusion

# Create PR, review, merge
```

### Weekly/Milestone Sync to ADO

**Option A: Manual Sync (Recommended)**
```bash
# In ADO repo
cd ~/Documents/Repos/Arkadium/IT/Scripts/Azure/storage-cost-analyzer

# Copy files from GitHub repo
rsync -av --delete \
  ~/Documents/Repos/azure-storage-cost-analyzer/ \
  . \
  --exclude='.git'

# Review changes
git status
git diff

# Commit to ADO
git add .
git commit -m "Sync from GitHub: [describe changes]

Synced from: https://github.com/yourusername/azure-storage-cost-analyzer
Commit: [github-commit-hash]"

# Push to ADO
git push origin feature/azure-storage-cost-analyzer-migration
```

**Option B: Git Remote Sync**
```bash
# In GitHub repo
cd ~/Documents/Repos/azure-storage-cost-analyzer

# Create ADO sync branch
git checkout -b ado-sync
git checkout main

# Periodically sync
git checkout ado-sync
git merge main
git push ado ado-sync:refs/heads/feature/azure-storage-cost-analyzer-migration
```

---

## 📁 Recommended GitHub Repo Structure

```
azure-storage-cost-analyzer/
├── .github/
│   └── workflows/
│       └── test.yml                    # CI/CD testing
├── .gitignore
├── README.md                           # Main documentation
├── IMPLEMENTATION-STATUS.md            # Current features status
├── TODO.md                             # Remaining work
├── TAG-EXCLUSION-IMPLEMENTATION.md     # Tag feature guide
├── ZABBIX-INTEGRATION-GUIDE.md         # Zabbix setup guide
├── QUICK-START-GUIDE.md               # Quick start
├── PRD_Zabbix_Implementation.md       # Original requirements
├── azure-storage-cost-analysis-enhanced.sh  # Main script
├── azure-storage-monitor.conf.example  # Config template
├── azure-pipelines-storage-monitor.yml # ADO pipeline
├── zabbix-template-azure-storage-monitor-7.0.xml  # Zabbix template
├── test-*.sh                          # Test scripts
└── LICENSE                            # MIT or Apache 2.0
```

---

## 🔒 Security Considerations

### Before Making Public

**Check for sensitive info:**
```bash
# Search for potential secrets
grep -r "password\|secret\|key\|token" .
grep -r "dev\.azure\.com" .  # ADO URLs
grep -r "arkadium" .          # Company-specific info

# Check git history
git log --all --full-history --source -- '*password*' '*secret*'
```

**Clean up if found:**
```bash
# Remove sensitive commits from history
git filter-branch --force --index-filter \
  "git rm --cached --ignore-unmatch path/to/file" \
  --prune-empty --tag-name-filter cat -- --all
```

**Add to .gitignore:**
```bash
# Sensitive files
*.env
*credentials*
*secrets*
config.conf  # If it contains actual credentials
```

### If Keeping Private

**Private GitHub repo benefits:**
- Free for personal accounts
- GitHub Actions CI/CD
- Better collaboration tools than ADO
- Easier to share with external contractors

---

## ✅ Recommended Action Plan

### For Your Use Case

**I recommend Option 1 (Fresh GitHub Repo)** because:
1. You want to keep other scripts private ✅
2. You want easier development (GitHub has better UX) ✅
3. You might open-source this later ✅
4. Clean separation is better for maintenance ✅

### Steps to Execute

```bash
# 1. Create GitHub repo (5 minutes)
cd ~/Documents/Repos
mkdir azure-storage-cost-analyzer
cd azure-storage-cost-analyzer
git init
cp -r ~/Documents/Repos/Arkadium/IT/Scripts/Azure/storage-cost-analyzer/* .

# Clean up any sensitive files
rm -f *.log *.json  # test outputs
# Review files for company-specific info

git add .
git commit -m "Initial commit: Azure Storage Cost Analyzer"

# 2. Push to GitHub (2 minutes)
gh repo create azure-storage-cost-analyzer --private --source=.
git push -u origin main

# 3. Add ADO remote for sync (1 minute)
git remote add ado https://dev.azure.com/arkadium/IT/_git/Scripts

# 4. Continue development in GitHub repo
cd ~/Documents/Repos/azure-storage-cost-analyzer
git checkout -b feature/tag-exclusion-integration
# ... work here ...

# 5. Sync back to ADO when ready (weekly)
# Use rsync or git merge (see above)
```

---

## 🤔 Questions to Answer

Before proceeding, decide:

1. **Public or Private GitHub repo?**
   - Public: Potential open-source, community contributions
   - Private: Free for you, easier than ADO, can make public later

2. **Sync frequency?**
   - After each feature (recommended)
   - Weekly
   - At milestones only

3. **Source of truth?**
   - GitHub (develop there, sync to ADO for internal use)
   - ADO (use GitHub as mirror only)

4. **Team access?**
   - Solo development (easy)
   - Team collaboration (need to decide on workflow)

---

**My Recommendation:**

Create a **private** GitHub repo initially. Develop the tag exclusion feature there. Once stable and tested, sync back to ADO. Then decide if you want to make it public.

**Want me to help you execute this migration now?**
