# Apache Configuratie Herstel Instructies

Als je problemen hebt met de Apache webserver configuratie voor Radiologger, bijvoorbeeld als je de default Apache pagina ziet in plaats van de Radiologger applicatie, volg dan deze instructies om het probleem op te lossen.

## Automatische Herstel Scripts

We hebben verschillende scripts die automatisch veel voorkomende Apache problemen kunnen oplossen:

### Methode 1: Gebruik het diagnose script

```bash
cd /opt/radiologger
sudo ./diagnose_apache.sh
```

Dit script zal:
1. Controleren of Apache correct is geconfigureerd
2. Controleren of alle benodigde modules zijn geactiveerd
3. De default site uitschakelen als deze nog actief is
4. De Radiologger site activeren
5. De configuratie herstellen indien nodig

### Methode 2: Gebruik het fix script

```bash
cd /opt/radiologger
sudo ./fix_apache_config.sh
```

Dit script zal specifiek:
1. De default Apache site deactiveren
2. De Radiologger site configureren en activeren
3. Apache herstarten

## Handmatige Stappen (als de scripts niet werken)

Als de automatische scripts het probleem niet oplossen, kun je deze handmatige stappen volgen:

1. **Schakel de default site uit**:
   ```bash
   sudo a2dissite 000-default
   ```

2. **Controleer of de Radiologger configuratie bestaat**:
   ```bash
   ls -la /etc/apache2/sites-available/radiologger*.conf
   ```

3. **Activeer de Radiologger site** (vervang de bestandsnaam indien nodig):
   ```bash
   sudo a2ensite radiologger_apache.conf
   ```

4. **Herstart Apache**:
   ```bash
   sudo systemctl restart apache2
   ```

5. **Controleer of de service draait**:
   ```bash
   sudo systemctl status radiologger
   sudo systemctl status apache2
   ```

## Browser Cache Problemen

Als je nog steeds de default Apache pagina ziet ondanks dat de configuratie correct is:

1. **Leeg je browser cache** (Ctrl+F5 of Cmd+Shift+R)
2. **Probeer een andere browser** of incognito/privé modus
3. **Controleer de directe verbinding** met de applicatie via poort 5000:
   ```bash
   curl -v http://localhost:5000/
   ```

## Verbindingstests

Om te controleren of de Apache configuratie werkt:

```bash
# Test directe verbinding met de app
curl -s http://localhost:5000/ | grep -o '<title>.*</title>'

# Test verbinding via Apache
curl -s http://localhost/ | grep -o '<title>.*</title>'
```

Als de directe verbinding werkt maar de Apache verbinding niet, is er een probleem met de Apache configuratie.

## Logs Controleren

Als je nog steeds problemen hebt, controleer dan de logs:

```bash
# Apache error logs
sudo tail -f /var/log/apache2/error.log

# Radiologger logs
sudo tail -f /var/log/radiologger/error.log

# Systemd logs voor de radiologger service
sudo journalctl -u radiologger -n 50
```

Bij verdere problemen, vraag hulp aan de systeembeheerder of open een issue op GitHub.