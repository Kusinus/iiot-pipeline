// Parameter für die Dev-Umgebung
using '../main.bicep'

param environment  = 'dev'
param projectName  = 'iiot-pipeline'
// uniqueSuffix wird automatisch aus der Resource-Group-ID generiert (siehe main.bicep)
// location wird vom Resource Group übernommen

// Azure SQL – Admin-Zugriff
param sqlAdminLogin    = 'sqladmin'
param aadAdminObjectId = '7f83bf3e-3967-404c-856c-fbc0c5c05a01' // Abegglen Markus (abegm7@bfh.ch)
param aadAdminLogin    = 'abegm7@bfh.ch'
param allowedClientIp  = '178.197.200.40' // Dev-Laptop / Edge-Standort (gemeinsame OPNsense-NAT-IP)

// Secret: NIE ins Repo einchecken – kommt aus Umgebungsvariable (siehe scripts/deploy.sh)
param sqlAdminPassword = readEnvironmentVariable('SQL_ADMIN_PASSWORD')
