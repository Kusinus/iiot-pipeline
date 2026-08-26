// =============================================================================
// Modul: Azure Container Apps
// Beschreibung: Betreibt den Processor (IoT Hub Event Hub → Azure SQL) als
//               dauerhaft laufenden Background-Worker (kein HTTP-Ingress).
// =============================================================================

// ---------------------------------------------------------------------------
// Parameter
// ---------------------------------------------------------------------------

@description('Basisname (ohne Präfix) für Log Analytics / Container Apps Environment / Container App')
param name string

@description('Name der Container Registry (global eindeutig, keine Bindestriche)')
param acrName string

@description('Azure Region')
param location string

@description('Ressource-Tags')
param tags object

@description('Image für den Processor-Container. Vor dem ersten "az acr build" zeigt dies auf einen Platzhalter, damit die erste Container-App-Erstellung nicht am Image-Pull scheitert.')
param processorImage string = 'mcr.microsoft.com/k8se/quickstart:latest'

@secure()
@description('Event-Hub-kompatible Connection String (Policy "service", siehe iot-hub.bicep)')
param eventHubConnectionString string

@description('Name/Pfad des eingebetteten Event Hub des IoT Hub')
param eventHubName string

@description('Consumer Group für den Processor')
param consumerGroup string = 'processor'

@description('SQL-Server-FQDN')
param sqlServer string

@description('SQL-Datenbankname')
param sqlDatabase string

@description('SQL-Login (siehe storage.bicep)')
param sqlUser string

@secure()
@description('SQL-Passwort (siehe storage.bicep)')
param sqlPassword string

// ---------------------------------------------------------------------------
// Log Analytics (Pflichtabhängigkeit der Container Apps Environment)
// ---------------------------------------------------------------------------

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'log-${name}'
  location: location
  tags: tags
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
  }
}

// ---------------------------------------------------------------------------
// Container Apps Environment
// ---------------------------------------------------------------------------

resource containerAppsEnv 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: 'cae-${name}'
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey:  logAnalytics.listKeys().primarySharedKey
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Container Registry
// ---------------------------------------------------------------------------
// Basic-SKU mit Admin-User: einfachste Variante für den Prototyp (analog
// zum SQL-Login in storage.bicep). Für Kundenprojekte würde man stattdessen
// Managed Identity + AcrPull-Rollenzuweisung verwenden, um ganz ohne
// Registry-Secrets auszukommen.

resource acr 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' = {
  name: acrName
  location: location
  tags: tags
  sku: { name: 'Basic' }
  properties: {
    adminUserEnabled: true
  }
}

// ---------------------------------------------------------------------------
// Container App – Processor (Background-Worker, kein HTTP-Ingress)
// ---------------------------------------------------------------------------

resource processorApp 'Microsoft.App/containerApps@2024-03-01' = {
  // Container-App-Namen sind auf 32 Zeichen begrenzt – kein "-processor"-
  // Suffix mehr möglich, sobald der volle Namensteil (workload-env-region-suffix) dazukommt.
  name: 'ca-${name}'
  location: location
  tags: tags
  properties: {
    managedEnvironmentId: containerAppsEnv.id
    configuration: {
      activeRevisionsMode: 'Single'
      registries: [
        {
          server:               acr.properties.loginServer
          username:             acr.listCredentials().username
          passwordSecretRef:    'acr-password'
        }
      ]
      secrets: [
        { name: 'acr-password',               value: acr.listCredentials().passwords[0].value }
        { name: 'eventhub-connection-string', value: eventHubConnectionString }
        { name: 'sql-password',               value: sqlPassword }
      ]
    }
    template: {
      containers: [
        {
          name:  'processor'
          image: processorImage
          resources: {
            cpu:    json('0.25')
            memory: '0.5Gi'
          }
          env: [
            { name: 'EVENTHUB_CONNECTION_STRING', secretRef: 'eventhub-connection-string' }
            { name: 'EVENTHUB_NAME',              value: eventHubName }
            { name: 'CONSUMER_GROUP',             value: consumerGroup }
            { name: 'SQL_SERVER',                 value: sqlServer }
            { name: 'SQL_DATABASE',               value: sqlDatabase }
            { name: 'SQL_USER',                   value: sqlUser }
            { name: 'SQL_PASSWORD',               secretRef: 'sql-password' }
          ]
        }
      ]
      // Ein einzelner Consumer genügt für den Prototyp (kein Checkpoint-Store,
      // siehe database/schema.sql) – mehrere Instanzen würden konkurrierend
      // denselben Event Hub lesen, ohne Mehrwert für die Datenlast.
      scale: {
        minReplicas: 1
        maxReplicas: 1
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------

@description('Login-Server der Container Registry (für "az acr build")')
output acrLoginServer string = acr.properties.loginServer

@description('Name der Container Registry')
output acrName string = acr.name

@description('Name der Container App (Processor)')
output containerAppName string = processorApp.name

@description('Name der Container Apps Environment')
output environmentName string = containerAppsEnv.name
