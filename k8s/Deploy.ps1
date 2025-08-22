#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Privee Kubernetes Deployment Script
.DESCRIPTION
    This script deploys the Privee application to Kubernetes in the recommended order
.EXAMPLE
    .\Deploy.ps1
#>

[CmdletBinding()]
param()

# Set error action preference
$ErrorActionPreference = "Stop"

Write-Host "🚀 Starting Privee Kubernetes deployment..." -ForegroundColor Green

# Check if kubectl is available
try {
    kubectl version --client --short | Out-Null
    Write-Host "✅ kubectl is available" -ForegroundColor Green
}
catch {
    Write-Host "❌ kubectl is not installed or not in PATH" -ForegroundColor Red
    exit 1
}

# Check if we're connected to a cluster
try {
    kubectl cluster-info | Out-Null
    Write-Host "✅ Connected to Kubernetes cluster" -ForegroundColor Green
}
catch {
    Write-Host "❌ Not connected to a Kubernetes cluster" -ForegroundColor Red
    Write-Host "Please configure kubectl to connect to your cluster first" -ForegroundColor Yellow
    exit 1
}

# Get current directory (should be the k8s directory)
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Write-Host "📁 Deploying from: $ScriptDir" -ForegroundColor Cyan

try {
    # Step 1: Apply secrets first (dependencies)
    Write-Host "🔐 1/4 Applying secrets..." -ForegroundColor Yellow
    kubectl apply -f "$ScriptDir/secrets.yml"
    Write-Host "✅ Secrets applied successfully" -ForegroundColor Green

    # Step 2: Apply deployment (main application)
    Write-Host "🏗️  2/4 Applying deployment..." -ForegroundColor Yellow
    kubectl apply -f "$ScriptDir/deployment.yml"
    Write-Host "✅ Deployment applied successfully" -ForegroundColor Green

    # Step 3: Apply services (networking)
    Write-Host "🌐 3/4 Applying services..." -ForegroundColor Yellow
    kubectl apply -f "$ScriptDir/services.yml"
    Write-Host "✅ Services applied successfully" -ForegroundColor Green

    # Step 4: Apply debug pod (optional)
    Write-Host "🔍 4/4 Applying debug pod..." -ForegroundColor Yellow
    kubectl apply -f "$ScriptDir/debug-pod.yml"
    Write-Host "✅ Debug pod applied successfully" -ForegroundColor Green

    Write-Host ""
    Write-Host "🎉 Deployment completed successfully!" -ForegroundColor Green
    Write-Host ""

    # Wait for deployment to be ready
    Write-Host "⏳ Waiting for deployment to be ready..." -ForegroundColor Yellow
    try {
        kubectl rollout status deployment/privee --timeout=300s
        Write-Host "✅ Deployment is ready!" -ForegroundColor Green
    }
    catch {
        Write-Host "⚠️  Deployment is taking longer than expected" -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "📋 Current status:" -ForegroundColor Cyan
    kubectl get pods -l app=privee
    Write-Host ""
    kubectl get services
    Write-Host ""

    # Show how to access the application
    Write-Host "🌍 Application access:" -ForegroundColor Cyan
    Write-Host "- LoadBalancer service: kubectl get service main-application-service" -ForegroundColor White
    Write-Host "- Port forward for local access: kubectl port-forward deployment/privee 4000:4000" -ForegroundColor White
    Write-Host "- View logs: kubectl logs -l app=privee --tail=50" -ForegroundColor White

    Write-Host ""
    Write-Host "✨ Privee deployment complete!" -ForegroundColor Green

}
catch {
    Write-Host "❌ Deployment failed: $_" -ForegroundColor Red
    exit 1
}
