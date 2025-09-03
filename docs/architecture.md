# Azure Deployment Architecture

![Architecture](./privee-architecture-diagram.svg)

Summary of resources, what they are and why they are used

- Azure Container Registry (ACR)
  - What: Private container image registry hosted in Azure.
  - Why: Hold built container images built by CI (GitHub Actions) so AKS can pull them. `modules/acr.bicep` and `acr-role-assignment.bicep` create and give AKS permission to pull.

- Azure Kubernetes Service (AKS)
  - What: Managed Kubernetes offering.
  - Why: Run the application as pods, provide autoscaling, integrations (managed identity, AAD, networking). `modules/aks.bicep` and `aks-rbac-assignment.bicep` define the cluster and RBAC glue.

- Azure Key Vault
  - What: Centralized secret and key management.
  - Why: Store sensitive configuration (DB passwords, API keys). The Secrets Store CSI Driver (and `k8s/secret-provider-class.yml`) mounts Key Vault secrets into pods so apps don't store secrets in plain text.

- Managed Identities
  - What: Azure-managed identities (system or user-assigned) for resources.
  - Why: Allow AKS (and other services) to authenticate to Key Vault and other Azure resources without credentials in code. Configured in `base/identity.bicep` / `base/admin-identity.bicep`.

- Cert-Manager + Let's Encrypt
  - What: Kubernetes controller for automated TLS certificate management.
  - Why: Issue and renew TLS certificates automatically for ingress hostnames. Configs live in `k8s/cert-manager` (issuers for staging/prod).

- Ingress Controller & Public IP / DNS
  - What: The ingress controller (e.g., nginx/Traefik deployed by manifests) plus a public IP and a DNS label.
  - Why: Terminate TLS, route external HTTP(s) traffic into the cluster to services and pods. DNS label / public IP resources are provisioned by `modules/ingress-dnslabel.bicep` or related scripts.

- Datastores: Cosmos DB and Azure Database for PostgreSQL
  - What: Managed database services (NoSQL and relational).
  - Why: Persist application data. `modules/cosmosdb-postgresql.bicep` provisions these.

- GitHub Actions OIDC and CI/CD
  - What: OIDC integration allows GitHub Actions to request short-lived tokens to authenticate to Azure.
  - Why: Securely push images to ACR and deploy infrastructure/manifests without storing long-lived Azure credentials. See `modules/gha-oidc-identity.bicep` in the repo.

How internet traffic is served (request flow)

1. A client/browser resolves the application hostname via DNS to the public IP provisioned for the ingress.
2. The request reaches Azure's public IP and is forwarded to AKS's Load Balancer (Service of type LoadBalancer) and then to the Ingress Controller.
3. The Ingress Controller matches the host/path and routes to the appropriate Service and backend Pod.
4. TLS is terminated at the Ingress Controller using certificates issued and renewed by cert-manager (which uses Let's Encrypt). Secrets for TLS or other credentials can be sourced from Key Vault via CSI.
5. Pods may connect to Cosmos DB or PostgreSQL using credentials retrieved from Key Vault or from environment/config maps.

Notes and pointers

- This architecture emphasizes: managed services (AKS, ACR, Key Vault, managed DBs), least-privilege access (managed identities, role assignments), and automated cert management.

Relevant files in this repo (under `.azure` and `k8s`)
- `.azure/modules/*` (bicep modules provisioning ACR, AKS, Key Vault, DBs, ingress DNS label, RBAC)
- `.azure/base/*` (identity and helper scripts)
- `.azure/k8s/*` (kubernetes manifests: `deployment.yml`, `service.yml`, `ingress.yml`, `secret-provider-class.yml`, `cert-manager` manifests)
- `.azure/scripts/*` (helper deployment scripts)

