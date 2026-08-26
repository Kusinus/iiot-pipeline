// =============================================================================
// IIoT Cloud-Pipeline – Hauptdatei
// Autor: Markus Abegglen | CAS Cloud Computing | Deleproject AG
// Beschreibung: Orchestriert alle Module der IIoT Azure-Pipeline
// =============================================================================

targetScope = 'resourceGroup'

// ---------------------------------------------------------------------------
// Parameter
// ---------------------------------------------------------------------------

@description('Umgebung: dev, test oder prod')
@allowed(['dev', 'test', 'prod'])
param environment string = 'dev'

@description('Azure Region für alle Ressourcen')
param location string = resourceGroup().location

@description('Projektname – für Tags und Anzeige, nicht zwingend Teil der Ressourcennamen')
@maxLength(20)
param projectName string = 'iiot-pipeline'

@description('Kurzer Workload-Name für Ressourcennamen. Bewusst ohne "iot", da der Ressourcentyp-Präfix (z.B. "iot-") das schon ausdrückt – sonst entsteht eine Wiederholung wie "iot-iiot-...".')
@maxLength(20)
param workloadName string = 'pipeline'

@description('Kurzer, deterministischer Suffix für global eindeutige Ressourcennamen (IoT Hub, Storage, ...)')
param uniqueSuffix string = take(uniqueString(resourceGroup().id), 6)

@description('SQL-Admin-Login (Fallback-Auth neben Azure AD, für Entwicklung/Tests)')
param sqlAdminLogin string = 'sqladmin'

@secure()
@description('SQL-Admin-Passwort (Fallback-Auth neben Azure AD, für Entwicklung/Tests) – wird nicht in Parameterdateien eingecheckt, siehe scripts/deploy.sh')
param sqlAdminPassword string

@description('Azure AD Objekt-ID des SQL-Administrators (z.B. eigener Benutzer für Dev)')
param aadAdminObjectId string

@description('Azure AD Login/UPN des SQL-Administrators')
param aadAdminLogin string

@description('Öffentliche IP, die für Tests/Entwicklung Zugriff auf den SQL Server erhält (Dev-Laptop / Edge-Standort)')
param allowedClientIp string

// ---------------------------------------------------------------------------
// Gemeinsame Variablen
// ---------------------------------------------------------------------------

// Namenskonvention nach Cloud Adoption Framework:
//   <resource-type-abkürzung>-<workload>-<environment>-<region>-<instanz>
// "workloadName" statt "projectName", damit der Ressourcentyp-Präfix nicht
// mit sich selbst wiederholt wird (z.B. "iot-iiot-..." bei projectName
// "iiot-pipeline" – der Typ "iot-" sagt ja schon, dass es ein IoT Hub ist).
// Bei global eindeutigen Ressourcentypen (IoT Hub, Storage Account, Key
// Vault, ...) ersetzt "uniqueSuffix" (ein kurzer, deterministischer Hash)
// die fortlaufende Instanznummer – ein Klartext-Name wie "iot-pipeline-dev-swn"
// wäre weltweit sehr wahrscheinlich schon vergeben. Bei rein
// RG-/Subscription-scoped Ressourcen (Container Apps, Log Analytics, ...)
// genügt stattdessen eine fortlaufende Nummer ("001").
//
// Ressourcentyp-Abkürzungen (siehe https://aka.ms/azure/abbreviations):
//   iot-   IoT Hub            st      Storage Account (keine Bindestriche!)
//   cae-   Container Apps Env log-    Log Analytics Workspace
//   ca-    Container App      appi-   Application Insights
var locationAbbreviations = {
  switzerlandnorth: 'swn'
  switzerlandwest:  'sww'
  westeurope:       'weu'
  northeurope:      'neu'
}
var regionAbbr = locationAbbreviations[?location] ?? location

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
    name:        'iot-${workloadName}-${environment}-${regionAbbr}-${uniqueSuffix}'
    location:    location
    environment: environment
    tags:        tags
  }
}

module storage 'modules/storage.bicep' = {
  name: 'deploy-storage'
  params: {
    name:              'sql-${workloadName}-${environment}-${regionAbbr}-${uniqueSuffix}'
    databaseName:      'sensordata'
    location:          location
    environment:       environment
    tags:              tags
    sqlAdminLogin:     sqlAdminLogin
    sqlAdminPassword:  sqlAdminPassword
    aadAdminObjectId:  aadAdminObjectId
    aadAdminLogin:     aadAdminLogin
    allowedClientIp:   allowedClientIp
  }
}

// Platzhalter – werden in späteren Phasen aktiviert:
// module containerApps 'modules/container-apps.bicep' = { ... }
// module monitoring    'modules/monitoring.bicep'     = { ... }

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------

output iotHubName          string = iotHub.outputs.name
output iotHubHostName      string = iotHub.outputs.hostName
output iotHubConnectionStr string = iotHub.outputs.connectionString

output sqlServerName string = storage.outputs.serverName
output sqlServerFqdn string = storage.outputs.serverFqdn
output sqlDatabaseName string = storage.outputs.databaseName
