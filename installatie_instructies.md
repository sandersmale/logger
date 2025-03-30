# Radiologger Installatie-instructies

Dit document bevat de instructies voor een betrouwbare installatie van Radiologger op een Digital Ocean VPS. Deze verbeterde methode zorgt ervoor dat **alle vereiste bestanden** worden gedownload voordat de installatie start.

## Vereisten

- Ubuntu 22.04 of 24.04 server
- Root-toegang
- Internetverbinding

## Installatieproces

### Optie 1: Snelle één-stap installatie (aanbevolen)

Deze methode downloadt het installatiescript en voert het direct uit:

```bash
sudo bash -c "wget -O full_download_install.sh https://raw.githubusercontent.com/sandersmale/logger/main/full_download_install.sh && chmod +x full_download_install.sh && ./full_download_install.sh"
```

### Optie 2: Handmatige installatie in stappen

Als je liever in stappen installeert:

1. Download het volledige installatiescript:
   ```bash
   wget -O full_download_install.sh https://raw.githubusercontent.com/sandersmale/logger/main/full_download_install.sh
   ```

2. Maak het uitvoerbaar:
   ```bash
   chmod +x full_download_install.sh
   ```

3. Voer het script uit:
   ```bash
   sudo ./full_download_install.sh
   ```

## Wat het installatiescript doet

Het `full_download_install.sh` script voert de volgende stappen uit:

1. Downloadt de volledige repository van GitHub
2. Maakt een backup van eventuele bestaande installaties
3. Kopieert alle bestanden naar de juiste locaties
4. Configureert de Radiologger gebruiker en benodigde mappen
5. Voert de installatie uit met de gedownloade bestanden
6. Controleert of alle cruciale bestanden aanwezig zijn
7. Creëert ontbrekende bestanden als dat nodig is
8. Installeert alle benodigde Python modules
9. Configureert en start de service

## Als je al het standaard installatiescript hebt gebruikt

Als je al het standaard installatiescript (`install.sh`) hebt uitgevoerd en problemen ondervindt, kun je alsnog overschakelen naar deze verbeterde methode. Het script zal automatisch een backup maken van je bestaande installatie en alle ontbrekende bestanden toevoegen.

## Troubleshooting

Als je na de installatie een 502 Bad Gateway error ziet, controleer dan de volgende zaken:

1. Controleer de status van de service:
   ```bash
   sudo systemctl status radiologger
   ```

2. Bekijk de logbestanden:
   ```bash
   sudo journalctl -u radiologger -n 50
   ```

3. Voer het diagnose script uit:
   ```bash
   sudo bash /opt/radiologger/diagnose_502.sh
   ```

Voor specifieke importfouten (zoals "ModuleNotFoundError: No module named 'forms'"), kun je het reparatiescript uitvoeren:

```bash
sudo bash /opt/radiologger/fix_auth_import.sh
```

## Na de installatie

Zodra de installatie succesvol is, kun je de webinterface openen via het IP-adres of domein van je server. Bij de eerste keer moet je:

1. Een admin-account aanmaken
2. De Wasabi S3 opslag configureren voor de archieffunctie

## Bestandslocaties

- Applicatiebestanden: `/opt/radiologger/`
- Logbestanden: `/var/log/radiologger/`
- Opnames: `/var/lib/radiologger/recordings/`
- Configuratiebestand: `/opt/radiologger/.env`
- Service definitie: `/etc/systemd/system/radiologger.service`