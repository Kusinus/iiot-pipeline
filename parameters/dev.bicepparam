// Parameter für die Dev-Umgebung
using '../main.bicep'

param environment  = 'dev'
param projectName  = 'iiot'
// uniqueSuffix wird automatisch via uniqueString() generiert
// location wird vom Resource Group übernommen
