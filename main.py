import os
import logging

# Configureer logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('app')
logger.info("Radiologger applicatie wordt gestart...")

# Importeer app.py (de volledige Flask app definitie)
from app import app

# Alleen voor lokale ontwikkeling
if __name__ == "__main__":
    # Debug modus automatisch inschakelen voor lokale ontwikkeling
    app.config['DEBUG'] = True
    logger.info("Applicatie gestart in debug modus op http://0.0.0.0:5000")
    app.run(host="0.0.0.0", port=5000, debug=True)