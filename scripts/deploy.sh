#!/usr/bin/env bash
# =============================================================================
# deploy.sh – IIoT Pipeline Deployment via Azure CLI
# Verwendung: ./scripts/deploy.sh [dev|prod] [resource-group]
# =============================================================================

set -euo pipefail

ENVIRONMENT="${1:-dev}"
RESOURCE_GROUP="${2:-rg-iiot-${ENVIRONMENT}}"
LOCATION="switzerlandnorth"

echo "🚀 Deploying IIoT Pipeline"
echo "   Umgebung:       ${ENVIRONMENT}"
echo "   Resource Group: ${RESOURCE_GROUP}"
echo "   Region:         ${LOCATION}"
echo ""

# Resource Group erstellen falls nicht vorhanden
az group create \
  --name "${RESOURCE_GROUP}" \
  --location "${LOCATION}" \
  --tags project=iiot environment="${ENVIRONMENT}" managedBy=bicep \
  --output table

echo ""
echo "📦 Starte Bicep Deployment..."

az deployment group create \
  --resource-group "${RESOURCE_GROUP}" \
  --template-file "./main.bicep" \
  --parameters "./parameters/${ENVIRONMENT}.bicepparam" \
  --name "iiot-deploy-$(date +%Y%m%d-%H%M%S)" \
  --output table

echo ""
echo "✅ Deployment abgeschlossen!"
echo ""

# Outputs anzeigen
echo "📋 Deployment Outputs:"
az deployment group show \
  --resource-group "${RESOURCE_GROUP}" \
  --name "$(az deployment group list --resource-group "${RESOURCE_GROUP}" --query '[0].name' -o tsv)" \
  --query 'properties.outputs' \
  --output table
