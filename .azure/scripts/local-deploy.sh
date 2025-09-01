#!/bin/bash

# Local Azure deployment script
# This script replicates the GitHub Actions workflow for local development

set -e

# Configuration variables (matching the GitHub workflow)
RESOURCE_GROUP="privee-dev-rg"
AZURE_CONTAINER_REGISTRY="priveeregistry"
REGISTRY_URL="priveeregistry.azurecr.io"
PROJECT_NAME="privee"
CLUSTER_NAME="privee-aks"
CONTAINER_NAME="privee"
DEPLOYMENT_MANIFEST_PATH="./.azure/k8s/deployment.yml"
PHX_HOST="privee.northeurope.cloudapp.azure.com"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_step() {
    echo -e "${BLUE}==> $1${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
    exit 1
}

# Check if we're in the correct directory
if [ ! -f "Dockerfile" ] || [ ! -f "mix.exs" ]; then
    print_error "Please run this script from the project root directory"
fi

# Check if required tools are installed
command -v az >/dev/null 2>&1 || print_error "Azure CLI is required but not installed"
command -v docker >/dev/null 2>&1 || print_error "Docker is required but not installed"
command -v kubectl >/dev/null 2>&1 || print_error "kubectl is required but not installed"

# Generate image tag based on current git commit
GIT_SHA=$(git rev-parse HEAD)
if [ -z "$GIT_SHA" ]; then
    print_warning "Not in a git repository, using timestamp for image tag"
    GIT_SHA=$(date +%Y%m%d%H%M%S)
fi

print_step "Starting local Azure deployment process"
echo "Resource Group: $RESOURCE_GROUP"
echo "Registry: $REGISTRY_URL"
echo "Project: $PROJECT_NAME"
echo "Cluster: $CLUSTER_NAME"
echo "Image Tag: $GIT_SHA"
echo

# Step 1: Log in to ACR
print_step "Logging in to Azure Container Registry"
az acr login --name "$AZURE_CONTAINER_REGISTRY"
print_success "Successfully logged in to ACR"

# Step 2: Build and push Docker image
print_step "Building and pushing Docker image"
BUILD_DATE=$(date -u +'%Y-%m-%dT%H:%M:%SZ')

docker build \
    --build-arg BUILD_DATE="$BUILD_DATE" \
    --build-arg VCS_REF="$GIT_SHA" \
    --build-arg PHX_HOST="$PHX_HOST" \
    --build-arg ENABLE_DB_SSL=true \
    -t "$REGISTRY_URL/$PROJECT_NAME:$GIT_SHA" \
    -t "$REGISTRY_URL/$PROJECT_NAME:latest" \
    .

print_success "Docker image built successfully"

print_step "Pushing Docker image to ACR"
docker push "$REGISTRY_URL/$PROJECT_NAME:$GIT_SHA"
docker push "$REGISTRY_URL/$PROJECT_NAME:latest"
print_success "Docker image pushed successfully"

# Step 3: Set up Kubernetes context
print_step "Setting up Kubernetes context"
az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --overwrite-existing
print_success "Kubernetes context configured"

# Step 4: Deploy to Kubernetes
print_step "Deploying to Kubernetes"
if [ ! -f "$DEPLOYMENT_MANIFEST_PATH" ]; then
    print_error "Deployment manifest not found at $DEPLOYMENT_MANIFEST_PATH"
fi

# Update the deployment with the new image
kubectl set image deployment/privee privee="$REGISTRY_URL/$PROJECT_NAME:$GIT_SHA" --namespace=default

# Wait for rollout to complete
print_step "Waiting for deployment rollout to complete"
kubectl rollout status deployment/privee --namespace=default --timeout=300s

print_success "Deployment completed successfully!"

# Display deployment info
print_step "Deployment Information"
kubectl get deployment privee --namespace=default
kubectl get pods -l app=privee --namespace=default

print_step "Service Information"
kubectl get service privee-service --namespace=default 2>/dev/null || print_warning "Service 'privee-service' not found"

print_step "Ingress Information"
kubectl get ingress --namespace=default 2>/dev/null || print_warning "No ingress found"

print_success "Local deployment process completed!"
echo
echo "To check logs, run:"
echo "  kubectl logs -l app=privee --namespace=default -f"
echo
echo "To check pod status, run:"
echo "  kubectl get pods -l app=privee --namespace=default"
