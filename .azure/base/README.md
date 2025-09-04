# Base Infrastructure for GitHub Actions

This directory contains the base infrastructure templates for creating a User Managed Identity with administrative permissions for GitHub Actions OIDC authentication.

## Overview

The base infrastructure creates:

1. **Resource Group** - A dedicated resource group for identity resources
2. **User Managed Identity** - Azure identity for GitHub Actions authentication
3. **Federated Identity Credential** - OIDC configuration for GitHub repository
4. **Contributor Role Assignment** - Subscription-level contributor permissions
5. **Minimal Role Assignment Permission** - Custom role with only Microsoft.Authorization/roleAssignments/write

## Role Assignment Permission Fix

This setup includes a fix for the error:
```
The client does not have permission to perform action 'Microsoft.Authorization/roleAssignments/write'
```

Instead of granting broad admin roles, we create a **custom role** with only the specific permission mentioned in the error.

### Custom Role Permissions

The custom role `{namePrefix}-minimal-role-assigner-{environment}` grants only:
- `Microsoft.Authorization/roleAssignments/write` - Create role assignments
- `Microsoft.Authorization/roleAssignments/read` - Read role assignments  
- `Microsoft.Authorization/roleDefinitions/read` - Read role definitions

### Result

The GitHub Actions managed identity will have:
- **Contributor** role (resource management)
- **Custom minimal role** (only the specific permission from the error)

## Prerequisites

- Azure CLI installed and authenticated (`az login`)
- Owner or User Access Administrator role on the target Azure subscription
- GitHub repository configured for the deployment

## Files

- `admin-identity.bicep` - Main Bicep template (subscription scope)
- `identity.bicep` - Identity module (resource group scope)  
- `minimal-role-assignment-permission.bicep` - Custom role with minimal permissions
- `admin-identity.parameters.json` - Template parameters
- `minimal-role-assignment-permission.parameters.json` - Custom role parameters
- `deploy.sh` - Deployment script with validation and preview
- `README.md` - This documentation

## Quick Start

1. **Edit parameters** in `admin-identity.parameters.json`:
   ```json
   {
     "namePrefix": {"value": "your-project"},
     "githubOwner": {"value": "YourGitHubUsername"},
     "githubRepo": {"value": "YourRepoName"},
     "location": {"value": "West Europe"}
   }
   ```

2. **Deploy everything with the script**:
   ```bash
   ./deploy.sh --subscription-id YOUR_SUBSCRIPTION_ID
   ```
   
   This script will:
   - Deploy the custom role with minimal permissions
   - Wait for role propagation
   - Deploy the admin identity with both Contributor and custom role

3. **Add GitHub Secrets** (values will be displayed after deployment):
   - `AZURE_CLIENT_ID` - User Managed Identity client ID
   - `AZURE_TENANT_ID` - Azure AD tenant ID  
   - `AZURE_SUBSCRIPTION_ID` - Azure subscription ID

## Manual Deployment

If you prefer to deploy manually:

```bash
# Validate template
az deployment sub validate \\
  --location "West Europe" \\
  --template-file admin-identity.bicep \\
  --parameters @admin-identity.parameters.json

# Preview changes
az deployment sub what-if \\
  --location "West Europe" \\
  --template-file admin-identity.bicep \\
  --parameters @admin-identity.parameters.json

# Deploy
az deployment sub create \\
  --location "West Europe" \\
  --template-file admin-identity.bicep \\
  --parameters @admin-identity.parameters.json \\
  --name admin-identity-deployment
```

## Security Considerations

### Contributor Role Permissions

The User Managed Identity is granted the **Contributor** role at subscription level, which provides:

- ✅ **Full resource management** - Create, modify, delete all Azure resources
- ❌ **Access management** - Cannot assign roles or manage permissions
- ❌ **Subscription administration** - No access to subscription-level administrative actions

### Alternative: Granular Permissions

If Owner role is too broad, you can modify the template to use:

- **Contributor** role - Resource management without access control
- **User Access Administrator** role - Access management only
- **Custom role** - Specific permissions tailored to your needs

To use alternative permissions, uncomment the relevant sections in `admin-identity.bicep` and comment out the Owner role assignment.

### OIDC Security

The federated identity credential ensures:

- 🔒 **No long-lived secrets** - Uses short-lived tokens only
- 🔒 **Repository-specific** - Tied to your specific GitHub repository
- 🔒 **Branch-specific** - Default configuration for `main` branch only
- 🔒 **GitHub-verified** - Tokens issued and verified by GitHub

## Customization

### Different Branch or Environment

To use with different branches or pull requests, modify the `oidcSubject` parameter:

```json
// For specific branch
{"oidcSubject": {"value": "ref:refs/heads/develop"}}

// For pull requests
{"oidcSubject": {"value": "pull_request"}}

// For specific environment
{"oidcSubject": {"value": "environment:production"}}
```

### Different Azure Region

Update the `location` parameter in the parameters file:

```json
{"location": {"value": "East US"}}
```

### Custom Resource Group Name

The resource group name can be customized via the `identityResourceGroupName` parameter:

```json
{"identityResourceGroupName": {"value": "my-custom-identity-rg"}}
```

## Outputs

After successful deployment, you'll receive:

- **clientId** - Use for `AZURE_CLIENT_ID` GitHub secret
- **principalId** - Azure AD principal ID of the identity
- **identityResourceId** - Full ARM resource ID
- **resourceGroupName** - Created resource group name
- **federatedSubject** - OIDC subject configuration
- **permissionsSummary** - Summary of granted permissions

## Troubleshooting

### Common Issues

1. **Insufficient Permissions**: Ensure you have Owner or User Access Administrator role
2. **Template Validation Fails**: Check parameter values and Azure CLI version
3. **Role Assignment Fails**: Verify subscription permissions and identity creation

### Cleanup

To remove all resources:

```bash
az group delete --name RESOURCE_GROUP_NAME --yes --no-wait
```

**Warning**: This will permanently delete the identity and all associated role assignments.

## Integration with GitHub Actions

After deployment, your GitHub Actions workflow can authenticate like this:

```yaml
- name: Azure login (OIDC)
  uses: azure/login@v2
  with:
    client-id: ${{ secrets.AZURE_CLIENT_ID }}
    tenant-id: ${{ secrets.AZURE_TENANT_ID }}
    subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

- name: Verify access
  run: |
    az account show
    az resource list --output table
```

The identity will have full administrative access to the subscription for resource deployment and management.

## Next Steps

Once the base infrastructure is deployed:

1. Update your GitHub repository secrets with the provided values
2. Test the authentication in your GitHub Actions workflow
3. Deploy your main application infrastructure using the new identity
4. Consider implementing additional security measures like conditional access policies

## Support

For issues or questions:
- Check Azure CLI logs: `az account get-access-token`  
- Verify identity in Azure Portal: Azure Active Directory → Managed Identities
- Review role assignments: Subscription → Access Control (IAM)
