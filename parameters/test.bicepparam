// Parameter für die Test-Umgebung
// Dient u.a. dem Redeployment-Test in eine frische Ressourcengruppe
// (Kapitel 6.3, Reproduzierbarkeit) – bewusst als "test" statt "dev", da
// pro Subscription nur ein F1-Free-Tier-IoT-Hub erlaubt ist (siehe
// modules/iot-hub.bicep) und der produktive Dev-Hub dafür nicht angetastet
// werden soll.
using '../main.bicep'

param environment  = 'test'
param projectName  = 'iiot-pipeline'
// uniqueSuffix wird automatisch aus der Resource-Group-ID generiert (siehe main.bicep)
// location wird vom Resource Group übernommen

// Azure SQL – Admin-Zugriff (gleicher Administrator wie in dev, siehe
// parameters/dev.bicepparam)
param sqlAdminLogin    = 'sqladmin'
param aadAdminObjectId = '7f83bf3e-3967-404c-856c-fbc0c5c05a01' // Abegglen Markus (abegm7@bfh.ch)
param aadAdminLogin    = 'abegm7@bfh.ch'
param allowedClientIp  = '147.87.6.14' // Dev-Client-IP zum Zeitpunkt des Redeployment-Tests (10.09.2026)

// Secret: NIE ins Repo einchecken – kommt aus Umgebungsvariable (siehe scripts/deploy.sh)
param sqlAdminPassword = readEnvironmentVariable('SQL_ADMIN_PASSWORD')