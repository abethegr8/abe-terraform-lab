# Azure Terraform Infrastructure Lab

Infrastructure as Code (IaC) lab for provisioning Azure infrastructure with **Terraform**, storing state in **Azure Blob Storage**, and automating the Azure Kubernetes Service (AKS) lifecycle with **GitHub Actions**.

This repository is a hands-on platform engineering project focused on repeatable deployments, identity-based authentication, state management, and controlled infrastructure changes.

## Project goals

- Manage Azure infrastructure as version-controlled Terraform code.
- Keep independent Terraform projects in separate root modules and state files.
- Use an Azure Storage remote backend with state locking.
- Authenticate GitHub Actions to Azure using Microsoft Entra workload identity federation (OIDC), without long-lived Azure client secrets.
- Review Terraform plans before applying or destroying AKS infrastructure.
- Deploy and destroy lab infrastructure on demand to practice safely and manage costs.
- Expand the lab toward reusable modules, Kubernetes application delivery, and GitOps.

## Repository structure

```text
abe-terraform-lab/
├── .github/
│   └── workflows/
│       ├── terraform-aks.yml
│       ├── terraform-aks-deploy.yml
│       └── terraform-aks-destroy.yml
├── azure-aks-lab/
│   └── ... Terraform configuration for AKS
└── azure-storage-lab/
    └── ... Terraform configuration for Azure Storage exercises
```

Each lab is a separate Terraform root module. Changes in one lab do not automatically affect the other's state.

## Architecture

```text
Developer / GitHub repository
             |
             +----------------------------+
             |                            |
       Local Terraform              GitHub Actions
       (storage lab)                  (AKS lab)
             |                            |
       Azure CLI login             GitHub OIDC token
             |                            |
             |                   Microsoft Entra ID
             |                            |
             +-------------+--------------+
                           |
                 Azure Blob Storage
                   Terraform state
                           |
                 +---------+---------+
                 |                   |
             AKS state          Storage lab state
                 |                   |
             Azure AKS         Storage resources
```

The state storage account is managed separately from the resources in these labs, so destroying the AKS lab does **not** destroy its Terraform backend.

## Terraform remote state

Both labs use the `azurerm` backend in the same Azure Storage account and blob container, with **different state keys**:

| Lab | Backend state key | Execution |
| --- | --- | --- |
| `azure-aks-lab` | `aks/terraform.tfstate` | GitHub Actions or local CLI |
| `azure-storage-lab` | `storage/terraform.tfstate` | Local CLI |

Backend resources used in this lab:

- Resource group: `rg-tfstate`
- Storage account: `stabestfstate001`
- Blob container: `tfstate001`

Example backend configuration (use the appropriate `key` for each lab):

```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-tfstate"
    storage_account_name = "stabestfstate001"
    container_name       = "tfstate001"
    key                  = "storage/terraform.tfstate"
    use_azuread_auth     = true
  }
}
```

`use_azuread_auth = true` instructs the backend to use Microsoft Entra authentication for blob access. The identity running Terraform needs an appropriate data-plane role, such as **Storage Blob Data Contributor**, on the state container or an inherited scope. Azure subscription **Owner** or **Contributor** alone does not automatically grant blob data access through Entra ID.

> **State migration:** These labs previously used HCP Terraform workspaces. After confirming the old state was empty or otherwise safely accounted for, the projects were reconfigured to use Azure Blob Storage. Old HCP credentials, variables, and service principals can be retired once verified unused.

## AKS infrastructure

The AKS lab currently provisions:

- An Azure resource group (`lab-aks-rg`)
- An AKS cluster (`lab-aks1`)
- A default node pool with cluster autoscaling configured for **1–2 nodes**
- A system-assigned managed identity and OIDC issuer

The lab has been deployed in **West US**. Region, Kubernetes version, and VM SKU availability can change; check the Terraform configuration and Azure quota/capacity before deploying.

## GitHub Actions workflows

The repository currently includes three manually triggered workflows. **No pull-request automation is configured yet.**

| Workflow | Purpose | What it does |
| --- | --- | --- |
| `terraform-aks.yml` | Plan | Formats/checks, initializes, validates, and previews Terraform changes without applying them. |
| `terraform-aks-deploy.yml` | Deploy | Creates a saved plan, waits for approval, then applies that exact plan. |
| `terraform-aks-destroy.yml` | Destroy | Creates a destroy plan, requires an explicit `DESTROY` confirmation and approval, then applies the destroy plan. |

### Deploy workflow

```text
Manual workflow_dispatch
          |
          v
Checkout + Azure login (OIDC)
          |
          v
Terraform init / validate / plan
          |
          v
Upload saved plan artifact
          |
          v
GitHub environment: aks-lab
Required reviewer approval
          |
          v
Download saved plan artifact
          |
          v
Terraform apply tfplan
```

The deploy workflow separates the **plan** and **apply** jobs. The apply job uses the GitHub environment `aks-lab`, which has a required-reviewer gate. Saving the plan ensures the approved job applies the reviewed plan rather than silently recalculating it.

### Destroy workflow

```text
Manual workflow_dispatch
Input confirmation = DESTROY
          |
          v
Terraform plan -destroy
          |
          v
Upload saved destroy plan
          |
          v
GitHub environment approval
          |
          v
Terraform apply tfdestroyplan
```

The destroy workflow is guarded to run from `main` and requires the exact confirmation text `DESTROY`. Its environment approval adds a second deliberate checkpoint. A successful lab run destroyed the AKS cluster and its resource group while leaving the independent state backend intact.

### State concurrency

Deploy and destroy workflows share a concurrency group (`terraform-aks-state`) to reduce the chance of overlapping state-changing runs. Azure Blob Storage also provides Terraform state locking. These protections complement each other; neither replaces proper review and authorization.

## Authentication and authorization

GitHub Actions uses **Microsoft Entra workload identity federation** with the app registration `github-terraform-aks-lab`.

- The plan job uses a federated credential associated with the repository's `main` branch.
- Approval-gated apply/destroy jobs use a federated credential associated with the GitHub environment `aks-lab`.
- GitHub Actions receives short-lived Azure credentials through OIDC instead of storing a long-lived client secret.
- The GitHub identity has Azure permissions to manage lab infrastructure and blob data access to the state backend.
- Local Terraform can use `az login`, provided the signed-in user has the required Azure and blob data permissions.

Repository variables used by the workflows:

```text
AZURE_CLIENT_ID
AZURE_TENANT_ID
AZURE_SUBSCRIPTION_ID
```

The workflows also configure Terraform authentication using environment variables such as `ARM_USE_OIDC=true` and `ARM_USE_AZUREAD=true`.

**Security note:** The GitHub app currently has relatively broad subscription-level Contributor access for the lab. A production implementation should narrow its scope and use separate least-privilege identities where practical. Public workflow logs and saved Terraform plan artifacts can expose infrastructure details or sensitive values; plan artifacts should be tightly access-controlled and short-lived. Do not commit credentials, `.tfstate` files, or Terraform plan binaries.

## Running Terraform locally

Requirements:

- Terraform compatible with this repository's version constraints
- Azure CLI
- Access to the Azure subscription and Terraform backend
- Suitable Azure RBAC permissions

```powershell
az login
az account show

cd C:\DevWork\abe-terraform-lab\azure-storage-lab
terraform init -reconfigure
terraform fmt -check
terraform validate
terraform state list
terraform plan
```

If `terraform state list` is empty but Terraform configuration defines resources, `terraform plan` may propose creating them. Always review the plan before applying.

## Running the AKS workflows

1. Open the repository's **Actions** tab in GitHub.
2. Select **Terraform AKS Plan** to preview changes without provisioning infrastructure.
3. Select **Terraform AKS Deploy** to generate a plan and request approval before provisioning AKS.
4. Approve the `aks-lab` environment job when the plan is expected.
5. When finished with the cluster, select **Terraform AKS Destroy**, enter `DESTROY`, inspect the destroy plan, and approve the protected job.

Deploying AKS incurs Azure charges. Destroying the cluster reduces ongoing lab costs, but always check for separately managed resources and billing items.

## What GitHub Actions enables

GitHub Actions is the automation layer between a Git commit and a controlled infrastructure operation. In this lab it already supports:

- **Repeatability:** Execute the same Terraform steps on a hosted runner.
- **Reviewability:** Keep workflow definitions and infrastructure code in Git.
- **Credentialless federation:** Use short-lived OIDC authentication to Azure.
- **Change previews:** Review Terraform plans before provisioning.
- **Approval gates:** Require a human decision before apply/destroy.
- **Lifecycle management:** Deploy and tear down the AKS lab on demand.
- **Traceability:** Inspect workflow runs, logs, and outcomes in GitHub.

### Planned improvements (not yet implemented)

- **Pull-request checks:** Run `terraform fmt`, backend-free `terraform init`, and `terraform validate` for incoming PRs without granting untrusted fork code Azure credentials.
- **Reusable Terraform modules:** Extract AKS, networking, and supporting infrastructure into reusable modules.
- **Security hardening:** Narrow Azure RBAC, protect environment deployments, pin third-party actions, and review artifact/log exposure.
- **Kubernetes application delivery:** Deploy a sample application with Helm after AKS provisioning.
- **GitOps:** Explore Argo CD to synchronize Kubernetes application configuration from Git.
- **Observability and operations:** Add monitoring, alerts, node-pool maintenance, and troubleshooting exercises.
- **Documentation:** Record architecture decisions, costs, screenshots, and deployment lessons learned.

## Lessons learned

1. **Terraform state is infrastructure-critical.** The backend must survive the resources it manages, and independent labs need independent state keys.
2. **Azure management-plane RBAC differs from blob data-plane RBAC.** Being a storage account Owner does not by itself grant Entra-based blob data access.
3. **OIDC trust is specific.** A federated credential for a branch does not automatically match a job running under a GitHub environment.
4. **Plan and apply are distinct stages.** Saving a plan and applying it after approval makes the deployment workflow more intentional.
5. **Destroy should be designed, not improvised.** Explicit confirmation, plan review, and approval support safe and economical experimentation.

## Disclaimer

This is a personal learning and portfolio lab, **not a production-ready reference implementation**. Review identity permissions, state security, networking, Kubernetes configuration, costs, and organizational policies before adapting these patterns for production.
