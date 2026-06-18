# IIoT Cloud-Pipeline

**Reproduzierbare IIoT Cloud-Pipeline für industrielle Datenerfassung mittels Infrastructure as Code**

> Semesterarbeit CAS Cloud Computing – Markus Abegglen, Deleproject AG  
> Berner Fachhochschule, 2026

---

## Überblick

Dieses Repository enthält die gesamte Infrastruktur und Implementierung einer cloud-nativen IIoT-Pipeline auf Azure. Sensordaten von Industrieanlagen werden über ein Edge Gateway erfasst, in die Azure Cloud übertragen, containerisiert verarbeitet, in einer Datenbank gespeichert und via Power BI visualisiert.

```
Sensor / OPC UA
      │  MQTT / HTTPS
      ▼
Edge Gateway (Raspberry Pi, Docker)
      │
      ▼
Azure IoT Hub
      │  Event Hub (eingebettet)
      ▼
Azure Container Apps (Docker Processor)
      │
      ▼
Azure SQL Serverless (Zeitreihendaten)
      │
      ▼
Power BI Dashboard
```

---

## Projektstruktur

```
iiot-pipeline/
├── main.bicep                    # Einstiegspunkt – orchestriert alle Module
├── modules/
│   ├── iot-hub.bicep             # Azure IoT Hub + Consumer Groups
│   ├── container-apps.bicep      # Verarbeitungsschicht (Docker)
│   ├── storage.bicep             # Azure SQL Serverless
│   └── monitoring.bicep          # Log Analytics, Alerts
├── parameters/
│   ├── dev.bicepparam            # Dev-Umgebung (Free Tier, 1 Tag Retention)
│   └── prod.bicepparam           # Prod-Umgebung (S1, 3 Tage Retention)
└── scripts/
    └── deploy.sh                 # Azure CLI Deployment-Skript
```

---

## Voraussetzungen

- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) ≥ 2.50
- [Bicep CLI](https://learn.microsoft.com/azure/azure-resource-manager/bicep/install) ≥ 0.24 (oder via `az bicep install`)
- Azure Subscription mit Berechtigungen zum Erstellen von Resource Groups
- [VS Code](https://code.visualstudio.com/) mit [Bicep Extension](https://marketplace.visualstudio.com/items?itemName=ms-azuretools.vscode-bicep)

---

## Phasenplan

- [x] Phase 1 – Analyse & Architekturdesign, IoT Hub Bicep
- [ ] Phase 2 – Edge Gateway (Python, Raspberry Pi)
- [ ] Phase 3 – Container Apps Processor (Docker)
- [ ] Phase 4 – Azure SQL Serverless + Datenschema
- [ ] Phase 5 – Power BI Dashboard
- [ ] Phase 6 – Evaluation & Dokumentation

---

## Lizenz

MIT – Verwendung als Referenzarchitektur für Kundenprojekte der Deleproject AG ausdrücklich erwünscht.