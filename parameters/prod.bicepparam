// Parameter für die Prod-Umgebung
using '../main.bicep'

param environment  = 'prod'
param projectName  = 'iiot-pipeline'
// uniqueSuffix wird automatisch aus der Resource-Group-ID generiert (siehe main.bicep)
// location wird vom Resource Group übernommen
