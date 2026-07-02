// Parameter für die Dev-Umgebung
using '../main.bicep'

param environment  = 'dev'
param projectName  = 'iiot-pipeline'
// uniqueSuffix wird automatisch aus der Resource-Group-ID generiert (siehe main.bicep)
// location wird vom Resource Group übernommen
