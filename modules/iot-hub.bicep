// =============================================================================
// Modul: Azure IoT Hub
// Beschreibung: Empfängt Telemetriedaten vom Edge Gateway und leitet sie
//               via eingebettetem Event Hub an die Verarbeitungsschicht weiter.
// =============================================================================

// ---------------------------------------------------------------------------
// Parameter
// ---------------------------------------------------------------------------

@description('Name des IoT Hubs (global eindeutig)')
param name string

@description('Azure Region')
param location string

@description('Umgebung (dev / test / prod)')
@allowed(['dev', 'test', 'prod'])
param environment string

@description('Ressource-Tags')
param tags object

// ---------------------------------------------------------------------------
// Variablen
// ---------------------------------------------------------------------------

// Dev: kostenloser Free-Tier (max. 8000 Nachrichten/Tag, 1x pro Subscription).
// Test/Prod: Standard S1 für Consumer Groups und Message Routing.
var skuName = environment == 'dev' ? 'F1' : 'S1'
var skuCapacity = 1

// Aufbewahrung der Nachrichten im eingebetteten Event Hub (1–7 Tage)
var retentionDays = environment == 'prod' ? 3 : 1

// Anzahl Partitionen im eingebetteten Event Hub
// 2 reicht für Prototyp; für höhere Parallelität später auf 4 erhöhen.
var partitionCount = 2

// ---------------------------------------------------------------------------
// IoT Hub Ressource
// ---------------------------------------------------------------------------

resource iotHub 'Microsoft.Devices/IotHubs@2023-06-30' = {
  name: name
  location: location
  tags: tags

  sku: {
    name: skuName
    capacity: skuCapacity
  }

  properties: {

    // --- Eingebetteter Event Hub (Telemetriedaten-Endpunkt) ---
    eventHubEndpoints: {
      events: {
        retentionTimeInDays: retentionDays
        partitionCount: partitionCount
      }
    }

    // --- Nachrichtenrouting ---
    // Standard-Route: alle Gerätenachrichten → eingebetteter Event Hub.
    // Später können weitere Routen (z.B. für Fehler, Alerts) ergänzt werden.
    routing: {
      fallbackRoute: {
        name:      '$fallback'
        source:    'DeviceMessages'
        condition: 'true'
        endpointNames: ['events']
        isEnabled: true
      }
    }

    // --- Nachrichtenbereichigung (Message Enrichments) ---
    // Fügt jeder Nachricht den Gerätenamen als Metadatum hinzu.
    // Vereinfacht spätere Verarbeitung in Container Apps.
    messagingEndpoints: {
      fileNotifications: {
        lockDurationAsIso8601: 'PT1M'
        ttlAsIso8601:          'PT1H'
        maxDeliveryCount:      10
      }
    }

    // --- Cloud-zu-Gerät Nachrichten (für spätere Steuerbefehle) ---
    cloudToDevice: {
      maxDeliveryCount: 10
      defaultTtlAsIso8601: 'PT1H'
      feedback: {
        lockDurationAsIso8601: 'PT5S'
        ttlAsIso8601:          'PT1H'
        maxDeliveryCount:      10
      }
    }

    // --- Features ---
    features: 'None' // 'DeviceManagement' nur bei Bedarf aktivieren

    // --- Öffentlicher Netzwerkzugang ---
    // Für Prototyp offen; in Prod via Private Endpoint einschränken.
    publicNetworkAccess: 'Enabled'

    // --- Mindest-TLS-Version ---
    minTlsVersion: '1.2'
  }
}

// ---------------------------------------------------------------------------
// Consumer Group für Container Apps Processor
// ---------------------------------------------------------------------------
// Jeder Consumer (Verarbeitungsservice) sollte eine eigene Consumer Group
// haben, um unabhängig lesen zu können. Hier eine Gruppe für den Processor.

resource consumerGroupProcessor 'Microsoft.Devices/IotHubs/eventHubEndpoints/ConsumerGroups@2023-06-30' = {
  name: '${iotHub.name}/events/processor'
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------

@description('Name des IoT Hubs')
output name string = iotHub.name

@description('Hostname des IoT Hubs (für Geräteverbindungen)')
output hostName string = iotHub.properties.hostName

@description('Connection String für Backend-Services (iothubowner Policy)')
output connectionString string = 'HostName=${iotHub.properties.hostName};SharedAccessKeyName=iothubowner;SharedAccessKey=${iotHub.listKeys().value[0].primaryKey}'

@description('Event Hub-kompatibler Endpunkt (für Consumer wie Container Apps)')
output eventHubEndpoint string = iotHub.properties.eventHubEndpoints.events.endpoint

@description('Event Hub-kompatibler Pfad (Entity Path)')
output eventHubPath string = iotHub.properties.eventHubEndpoints.events.path

@description('Consumer Group Name für den Processor')
output consumerGroupName string = 'processor'

@description('Ressource ID des IoT Hubs')
output resourceId string = iotHub.id
