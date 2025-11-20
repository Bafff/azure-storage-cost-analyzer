# Service Principal Setup for Azure Storage Cost Analyzer

This guide explains the credentials and permissions needed to run the Azure Storage Cost Analyzer using a Service Principal.

## Required Permissions

The script performs the following Azure operations:

### 1. **Reader Access** (Minimum Required)
- Read disk information (Microsoft.Compute/disks)
- Read snapshot information (Microsoft.Compute/snapshots)
- Read subscription information
- Read resource group information

### 2. **Cost Management Reader**
- Query cost data via Cost Management API
- Required for retrieving actual costs of resources

### 3. **Resource Graph Queries**
- Uses Azure Resource Graph API for fast subscription-wide queries
- Included in Reader role

## Setup Instructions

### Option 1: Using Azure Portal

#### Step 1: Create Service Principal

```bash
# Create service principal with Reader role
az ad sp create-for-rbac \
  --name "azure-storage-cost-analyzer" \
  --role "Reader" \
  --scopes /subscriptions/{subscription-id}

# Save the output - you'll need these values:
# {
#   "appId": "xxxx-xxxx-xxxx-xxxx",           # CLIENT_ID
#   "displayName": "azure-storage-cost-analyzer",
#   "password": "xxxx-xxxx-xxxx-xxxx",        # CLIENT_SECRET
#   "tenant": "xxxx-xxxx-xxxx-xxxx"           # TENANT_ID
# }
```

#### Step 2: Add Cost Management Reader Role

```bash
# Add Cost Management Reader role
az role assignment create \
  --assignee {appId-from-step-1} \
  --role "Cost Management Reader" \
  --scope /subscriptions/{subscription-id}
```

#### Step 3: For Multiple Subscriptions

```bash
# Loop through subscriptions
for sub_id in $(az account list --query '[].id' -o tsv); do
  echo "Assigning roles to subscription: $sub_id"

  # Reader role
  az role assignment create \
    --assignee {appId} \
    --role "Reader" \
    --scope /subscriptions/$sub_id

  # Cost Management Reader role
  az role assignment create \
    --assignee {appId} \
    --role "Cost Management Reader" \
    --scope /subscriptions/$sub_id
done
```

### Option 2: Using Azure Portal (GUI)

1. **Navigate to Azure Active Directory**
   - Go to "App registrations" → "New registration"
   - Name: "azure-storage-cost-analyzer"
   - Click "Register"

2. **Create Client Secret**
   - In your app registration, go to "Certificates & secrets"
   - Click "New client secret"
   - Add description: "Cost Analyzer Script"
   - Set expiration (recommend: 24 months)
   - **IMPORTANT**: Copy the secret value immediately (shown only once)

3. **Assign Reader Role**
   - Navigate to Subscriptions → Select subscription
   - Click "Access control (IAM)" → "Add role assignment"
   - Role: "Reader"
   - Assign access to: "User, group, or service principal"
   - Select your app: "azure-storage-cost-analyzer"
   - Click "Save"

4. **Assign Cost Management Reader Role**
   - In the same subscription, click "Add role assignment" again
   - Role: "Cost Management Reader"
   - Select your app: "azure-storage-cost-analyzer"
   - Click "Save"

## Authentication Methods

### Method 1: Using Environment Variables (Recommended)

```bash
# Set environment variables
export AZURE_CLIENT_ID="your-app-id"
export AZURE_CLIENT_SECRET="your-client-secret"
export AZURE_TENANT_ID="your-tenant-id"

# Login with service principal
az login --service-principal \
  -u $AZURE_CLIENT_ID \
  -p $AZURE_CLIENT_SECRET \
  --tenant $AZURE_TENANT_ID

# Run the script
./azure-storage-cost-analyzer.sh unused-report \
  --subscriptions all \
  --days 30
```

### Method 2: Direct Login Command

```bash
az login --service-principal \
  -u <app-id> \
  -p <client-secret> \
  --tenant <tenant-id>

./azure-storage-cost-analyzer.sh unused-report --subscriptions all --days 30
```

### Method 3: Azure DevOps / CI/CD Pipeline

```yaml
# azure-pipelines.yml
- task: AzureCLI@2
  inputs:
    azureSubscription: 'Your-Service-Connection-Name'  # Pre-configured in Azure DevOps
    scriptType: 'bash'
    scriptPath: 'azure-storage-cost-analyzer.sh'
    arguments: |
      unused-report \
      --subscriptions all \
      --days 30 \
      --output-format json \
      --zabbix-send
```

## Required Credentials Summary

| Credential | Where to Find | Example |
|------------|---------------|---------|
| **Application (Client) ID** | App Registration → Overview → Application (client) ID | `12345678-1234-1234-1234-123456789012` |
| **Directory (Tenant) ID** | App Registration → Overview → Directory (tenant) ID | `87654321-4321-4321-4321-210987654321` |
| **Client Secret Value** | App Registration → Certificates & secrets → Client secrets | `AbC.123~xYz_456-DeF` |

## Verify Permissions

```bash
# Login with service principal
az login --service-principal \
  -u $AZURE_CLIENT_ID \
  -p $AZURE_CLIENT_SECRET \
  --tenant $AZURE_TENANT_ID

# Test 1: List subscriptions
az account list --query '[].{Name:name, ID:id}' -o table

# Test 2: Query Resource Graph (test disk access)
az graph query -q "Resources | where type == 'microsoft.compute/disks' | count"

# Test 3: Test Cost Management API
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
az rest --method POST \
  --url "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/providers/Microsoft.CostManagement/query?api-version=2023-03-01" \
  --body '{
    "type": "ActualCost",
    "timeframe": "MonthToDate",
    "dataset": {
      "granularity": "None",
      "aggregation": {
        "totalCost": {
          "name": "Cost",
          "function": "Sum"
        }
      }
    }
  }'
```

## Troubleshooting

### Error: "Insufficient privileges to complete the operation"

**Solution**: Ensure the service principal has both:
- Reader role
- Cost Management Reader role

```bash
# Check current role assignments
az role assignment list \
  --assignee {app-id} \
  --query '[].{Role:roleDefinitionName, Scope:scope}' \
  -o table
```

### Error: "Resource Graph query failed"

**Solution**: Reader role includes Resource Graph access. Verify role assignment:

```bash
# Re-assign Reader role
az role assignment create \
  --assignee {app-id} \
  --role "Reader" \
  --scope /subscriptions/{subscription-id}
```

### Error: "Authentication failed"

**Solution**: Verify credentials and re-login:

```bash
# Clear cached credentials
az logout

# Re-login with correct credentials
az login --service-principal \
  -u $AZURE_CLIENT_ID \
  -p $AZURE_CLIENT_SECRET \
  --tenant $AZURE_TENANT_ID
```

## Security Best Practices

1. **Least Privilege**: Only assign Reader and Cost Management Reader roles
2. **Scope Limitation**: Assign roles at subscription level, not management group
3. **Secret Rotation**: Rotate client secrets every 6-12 months
4. **Secret Storage**:
   - Use Azure Key Vault for production
   - Use environment variables (never commit to git)
   - Use Azure DevOps variable groups with secret protection
5. **Audit**: Enable logging for service principal activity
6. **Expiration**: Set client secret expiration dates

## Minimum Role Definitions

If you need to create a custom role with minimal permissions:

```json
{
  "Name": "Storage Cost Analyzer Reader",
  "Description": "Read-only access for Azure Storage Cost Analyzer",
  "Actions": [
    "Microsoft.Compute/disks/read",
    "Microsoft.Compute/snapshots/read",
    "Microsoft.Resources/subscriptions/read",
    "Microsoft.Resources/subscriptions/resourceGroups/read",
    "Microsoft.CostManagement/query/action",
    "Microsoft.ResourceGraph/resources/read"
  ],
  "NotActions": [],
  "AssignableScopes": [
    "/subscriptions/{subscription-id}"
  ]
}
```

## Additional Resources

- [Azure Service Principal Documentation](https://docs.microsoft.com/azure/active-directory/develop/app-objects-and-service-principals)
- [Azure RBAC Built-in Roles](https://docs.microsoft.com/azure/role-based-access-control/built-in-roles)
- [Cost Management API](https://docs.microsoft.com/rest/api/cost-management/)
