# Minimal Role Assignment Permission Fix

This solution addresses the specific error: 
```
The client does not have permission to perform action 'Microsoft.Authorization/roleAssignments/write'
```

## Solution

Instead of granting broad admin roles, we create a **custom role** with only the specific permission mentioned in the error.

## Files

- `minimal-role-assignment-permission.bicep` - Creates custom role with minimal permissions
- `admin-identity.bicep` - Modified to use the custom role
- `deploy-minimal-fix.sh` - Script to deploy both templates in correct order

## Custom Role Permissions

The custom role `{namePrefix}-minimal-role-assigner-{environment}` grants only:

- `Microsoft.Authorization/roleAssignments/write` - Create role assignments
- `Microsoft.Authorization/roleAssignments/read` - Read role assignments  
- `Microsoft.Authorization/roleDefinitions/read` - Read role definitions

## Deployment

```bash
cd .azure/base
./deploy-minimal-fix.sh
```

This script:
1. Creates the custom role with minimal permissions
2. Deploys the admin identity with Contributor + custom role
3. Waits for role propagation

## Result

The GitHub Actions managed identity will have:
- **Contributor** role (resource management)
- **Custom minimal role** (only the specific permission from the error)

This is the absolute minimum permission needed to fix the role assignment error while maintaining security.
