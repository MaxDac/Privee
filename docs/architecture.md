# Azure Deployment Architecture

Below is a diagram (Mermaid) that represents the inferred Azure deployment architecture for this project. The diagram was produced from files in the `.azure` folder (e.g. `modules/*.bicep`, `k8s/*.yml`, `base/*`, `k8s/cert-manager/*`).

```mermaid
flowchart LR
  %% Azure control plane & infra
  subgraph Azure[Azure]
    direction TB
    ACR[Azure Container Registry\n`modules/acr.bicep` / `acr-role-assignment.bicep`]
    AKS[Azure Kubernetes Service (AKS)\n`modules/aks.bicep` / `aks-rbac-assignment.bicep`]
    KV[Azure Key Vault\n`modules/keyvault.bicep` / `keyvault-role-assignment.bicep`]
    DBs[(Datastores)\nCosmos DB + PostgreSQL\n`modules/cosmosdb-postgresql.bicep`]
    PIP[Public IP & DNS\n`modules/ingress-dnslabel.bicep`]
    MI[Managed Identities\n`base/identity.bicep` / `base/admin-identity.bicep`]
    GHA[GitHub Actions OIDC Identity\n`modules/gha-oidc-identity.bicep`]
  end

  %% Kubernetes logical components
  subgraph AKSCluster["AKS Cluster (k8s)"]
    direction TB
    Ingress[Ingress Controller\n`k8s/ingress.yml`]
    CertManager[Cert-Manager\n`k8s/cert-manager/*.yml` (Let's Encrypt issuers)]
    CSI[Secrets Store CSI Driver\n`k8s/secret-provider-class.yml`]
    App[Application Deployment\n`k8s/deployment.yml`\n`k8s/service.yml`]
    Headless[Headless Service\n`k8s/headless-service.yml`]
  end

  %% CI/CD flows
  GHA -->|push images & deploy| ACR
  GHA -->|deploy manifests / az cli| AKS

  %% runtime flows
  ACR -->|image pull| AKS
  AKS -->|uses Managed Identity| MI
  MI -->|access & RBAC| KV
  KV -->|secrets via CSI| CSI
  CSI -->|mount secrets| App

  %% networking & TLS
  PIP -->|public endpoint / DNS| Ingress
  Ingress -->|routes traffic| App
  CertManager -->|issue TLS certs| Ingress

  %% data layer
  App -->|reads/writes| DBs

  %% role assignments & infra glue (annotations)
  ACR -. role assignment .-> AKS
  AKS -. role assignment .-> KV

  style Azure fill:#f8f9fb,stroke:#ccc
  style AKSCluster fill:#eef6ff,stroke:#9fc5ff
```

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

- To preview this Mermaid diagram locally: open `docs/architecture.md` in VS Code and use the built-in Markdown Preview or install a Mermaid-support extension (e.g., "Markdown Preview Mermaid Support" or "Markdown Preview Enhanced").
- To include a committed SVG artifact instead of relying on runtime rendering, generate an SVG from a `.mmd` source using the Mermaid CLI (`mmdc`) and commit it to `docs/`.
- This architecture emphasizes: managed services (AKS, ACR, Key Vault, managed DBs), least-privilege access (managed identities, role assignments), and automated cert management.

Relevant files in this repo (under `.azure` and `k8s`)
- `.azure/modules/*` (bicep modules provisioning ACR, AKS, Key Vault, DBs, ingress DNS label, RBAC)
- `.azure/base/*` (identity and helper scripts)
- `.azure/k8s/*` (kubernetes manifests: `deployment.yml`, `service.yml`, `ingress.yml`, `secret-provider-class.yml`, `cert-manager` manifests)
- `.azure/scripts/*` (helper deployment scripts)

If you'd like, I can also:
- Create a separate `docs/architecture.mmd` source file and an npm script to render an SVG into `docs/`.
- Expand the diagram to show VNet/subnet, NSGs, Azure Application Gateway or WAF if you plan to add them.
