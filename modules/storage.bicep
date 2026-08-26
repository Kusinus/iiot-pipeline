// =============================================================================
// Modul: Azure SQL Serverless
// Beschreibung: Persistenz der Zeitreihendaten (Sensor-Telemetrie), die der
//               Processor aus dem IoT Hub liest und hier ablegt.
// =============================================================================

// ---------------------------------------------------------------------------
// Parameter
// ---------------------------------------------------------------------------

@description('Name des SQL Servers (global eindeutig)')
param name string

@description('Name der Datenbank')
param databaseName string

@description('Azure Region')
param location string

@description('Umgebung (dev / test / prod)')
@allowed(['dev', 'test', 'prod'])
param environment string

@description('Ressource-Tags')
param tags object

@description('SQL-Admin-Login (Fallback-Auth neben Azure AD, für Entwicklung/Tests)')
param sqlAdminLogin string

@secure()
@description('SQL-Admin-Passwort (Fallback-Auth neben Azure AD, für Entwicklung/Tests)')
param sqlAdminPassword string

@description('Azure AD Objekt-ID des SQL-Administrators (z.B. eigener Benutzer für Dev)')
param aadAdminObjectId string

@description('Azure AD Login/UPN des SQL-Administrators')
param aadAdminLogin string

@description('Öffentliche IP, die für Tests/Entwicklung Zugriff auf den SQL Server erhält (Dev-Laptop / Edge-Standort)')
param allowedClientIp string

// ---------------------------------------------------------------------------
// SQL Server
// ---------------------------------------------------------------------------
// Mixed-Mode-Auth (SQL + Azure AD): SQL-Login vereinfacht lokale
// Entwicklung/Tests ohne interaktiven AAD-Login; Managed Identity des
// späteren Container-Apps-Processors nutzt stattdessen Azure AD (kein
// Secret im Container).

resource sqlServer 'Microsoft.Sql/servers@2023-08-01-preview' = {
  name: name
  location: location
  tags: tags
  properties: {
    administratorLogin:         sqlAdminLogin
    administratorLoginPassword: sqlAdminPassword
    minimalTlsVersion:           '1.2'
    publicNetworkAccess:         'Enabled' // Prototyp; in Prod via Private Endpoint einschränken
  }
}

resource aadAdmin 'Microsoft.Sql/servers/administrators@2023-08-01-preview' = {
  parent: sqlServer
  name: 'ActiveDirectory'
  properties: {
    administratorType: 'ActiveDirectory'
    login:              aadAdminLogin
    sid:                aadAdminObjectId
    tenantId:           subscription().tenantId
  }
}

// --- Firewall ---
// Azure-Dienste (Container Apps Processor) erlauben. Kein fixer
// Outbound-IP-Bereich ohne VNET-Integration, daher die von Azure
// vorgesehene Sonderregel 0.0.0.0-0.0.0.0.
resource firewallAzureServices 'Microsoft.Sql/servers/firewallRules@2023-08-01-preview' = {
  parent: sqlServer
  name: 'AllowAllWindowsAzureIps'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress:   '0.0.0.0'
  }
}

resource firewallDevClient 'Microsoft.Sql/servers/firewallRules@2023-08-01-preview' = {
  parent: sqlServer
  name: 'AllowDevClient'
  properties: {
    startIpAddress: allowedClientIp
    endIpAddress:   allowedClientIp
  }
}

// ---------------------------------------------------------------------------
// Datenbank (Serverless)
// ---------------------------------------------------------------------------
// Dev: kleinste Serverless-Stufe, Auto-Pause nach 60 Min. Inaktivität
// (keine Kosten während der Pause, nur Storage). Test/Prod: kein
// Auto-Pause, da durchgängige Verfügbarkeit erwartet wird.

resource sqlDatabase 'Microsoft.Sql/servers/databases@2023-08-01-preview' = {
  parent: sqlServer
  name: databaseName
  location: location
  tags: tags
  sku: {
    name:     'GP_S_Gen5'
    tier:     'GeneralPurpose'
    family:   'Gen5'
    capacity: 1
  }
  properties: {
    autoPauseDelay: environment == 'dev' ? 60 : -1
    minCapacity:    json('0.5')
    maxSizeBytes:   2147483648 // 2 GB - reicht für Prototyp-Zeitreihendaten
    zoneRedundant:  false
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------

@description('Name des SQL Servers')
output serverName string = sqlServer.name

@description('Vollqualifizierter DNS-Name des SQL Servers')
output serverFqdn string = sqlServer.properties.fullyQualifiedDomainName

@description('Name der Datenbank')
output databaseName string = sqlDatabase.name

@description('Ressource ID des SQL Servers')
output resourceId string = sqlServer.id
