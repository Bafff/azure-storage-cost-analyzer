#!/bin/bash
# Sanitize repository for public release
# Run this script before making the repository public

set -euo pipefail

echo "🔍 Sanitizing repository for public release..."

# 1. Replace real subscription IDs with example values
echo "📝 Replacing subscription IDs..."
sed -i 's/03d76f78-4676-4116-b53a-162546996207/00000000-0000-0000-0000-000000000000/g' azure-storage-cost-analyzer.sh
sed -i 's/2f929c0a-d1f4-480c-a610-f75d1862fd53/11111111-1111-1111-1111-111111111111/g' azure-storage-cost-analyzer.sh
sed -i 's/03d76f78-4676-4116-b53a-162546996207/00000000-0000-0000-0000-000000000000/g' azure-storage-monitor.conf.example
sed -i 's/2f929c0a-d1f4-480c-a610-f75d1862fd53/11111111-1111-1111-1111-111111111111/g' azure-storage-monitor.conf.example
sed -i 's/03d76f78-4676-4116-b53a-162546996207/00000000-0000-0000-0000-000000000000/g' docs/PrdZabbixImplementation.md
sed -i 's/2f929c0a-d1f4-480c-a610-f75d1862fd53/11111111-1111-1111-1111-111111111111/g' docs/PrdZabbixImplementation.md

# 2. Replace internal resource group names
echo "📝 Replacing resource group names..."
sed -i 's/MC_internal-aks-dev-rg_internal-aks-dev_centralus/example-resource-group/g' azure-storage-cost-analyzer.sh

# 3. Replace company email addresses
echo "📝 Replacing email addresses..."
sed -i 's/john\.doe@company\.com/user1@example.com/g' docs/PrdZabbixImplementation.md
sed -i 's/jane\.smith@company\.com/user2@example.com/g' docs/PrdZabbixImplementation.md
sed -i 's/devops-oncall@company\.com/devops-oncall@example.com/g' docs/PrdZabbixImplementation.md
sed -i 's/platform-lead@company\.com/platform-lead@example.com/g' docs/PrdZabbixImplementation.md
sed -i 's/platform-oncall@company\.com/platform-oncall@example.com/g' docs/PrdZabbixImplementation.md
sed -i 's/zabbix-alerts@company\.com/alerts@example.com/g' docs/PrdZabbixImplementation.md
sed -i 's/devops-team@company\.com/devops@example.com/g' .pipelines/azure-pipelines-storage-monitor.yml

# 4. Verify no secrets remain
echo "🔍 Checking for remaining sensitive patterns..."
FOUND=0

# Check for potential real subscription IDs (not the example ones we just added)
if git grep -E "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}" | grep -v "00000000-0000-0000-0000-000000000000" | grep -v "11111111-1111-1111-1111-111111111111" | grep -v "SUBSCRIPTION_ID" | grep -v "subscription-id" | grep -v "your-subscription-id" | grep -v ".git"; then
    echo "⚠️  WARNING: Found potential real subscription IDs"
    FOUND=1
fi

# Check for @company.com emails
if git grep "@company\.com" | grep -v ".git"; then
    echo "⚠️  WARNING: Found @company.com email addresses"
    FOUND=1
fi

# Check for internal naming patterns
if git grep "internal-aks" | grep -v ".git"; then
    echo "⚠️  WARNING: Found internal naming patterns"
    FOUND=1
fi

if [ $FOUND -eq 0 ]; then
    echo "✅ No sensitive patterns found!"
else
    echo "❌ Please review and fix the warnings above"
    exit 1
fi

echo ""
echo "✅ Repository sanitized successfully!"
echo ""
echo "📋 Next steps:"
echo "1. Review the changes: git diff"
echo "2. Test the script still works with example values"
echo "3. Commit the sanitized version: git add -A && git commit -m 'Sanitize for public release'"
echo "4. Create a new public repository (don't push to existing repo to avoid exposing history)"
echo "5. Push sanitized version to new public repo"
