// Parameter für die Test-Umgebung
using '../main.bicep'

param environment  = 'test'
param projectName  = 'iiot'
// uniqueSuffix wird automatisch via uniqueString() generiert
// location wird vom Resource Group übernommen