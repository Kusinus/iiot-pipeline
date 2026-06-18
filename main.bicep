// =============================================================================
// IIoT Cloud-Pipeline – Hauptdatei
// Autor: Markus Abegglen | CAS Cloud Computing | Deleproject AG
// Beschreibung: Orchestriert alle Module der IIoT Azure-Pipeline
// =============================================================================

targetScope = 'resourceGroup'

// ---------------------------------------------------------------------------
// Parameter
// ---------------------------------------------------------------------------

@description('Umgebung: dev oder prod')
@allowed(['dev', 'test', 'prod'])
param environment string = 'dev'

@description('Azure Region für alle Ressourcen')
param location string = resourceGroup().location

@description('Projektkürzel – wird in alle Ressourcennamen eingebettet')
@maxLength(8)
param projectName string = 'iiot'

@description('Eindeutiger Suffix für global eindeutige Ressourcennamen')
param uniqueSuffix string = uniqueString(resourceGroup().id)

// ---------------------------------------------------------------------------
// Gemeinsame Variablen
// ---------------------------------------------------------------------------

var prefix = '${projectName}-${environment}'
var tags = {
  project:     projectName
  environment: environment
  managedBy:   'bicep'
  owner:       'deleproject'
}

// ---------------------------------------------------------------------------
// Module
// ---------------------------------------------------------------------------

module iotHub 'modules/iot-hub.bicep' = {
  name: 'deploy-iot-hub'
  params: {
    name:        '${prefix}-hub-${uniqueSuffix}'
    location:    location
    environment: environment
    tags:        tags
  }
}

// Platzhalter – werden in späteren Phasen aktiviert:
// module containerApps 'modules/container-apps.bicep' = { ... }
// module storage       'modules/storage.bicep'        = { ... }
// module monitoring    'modules/monitoring.bicep'     = { ... }

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------

output iotHubName          string = iotHub.outputs.name
output iotHubHostName      string = iotHub.outputs.hostName
output iotHubConnectionStr string = iotHub.outputs.connectionString
