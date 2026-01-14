import time
import sys
import logging
from pathlib import Path

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[logging.StreamHandler(sys.stdout)]
)
logger = logging.getLogger("MockService")

def main():
    logger.info("Service Starting...")
    logger.info(f"Python Version: {sys.version}")
    
    # Simulate config reading
    config_path = Path("config.yaml")
    if config_path.exists():
        logger.info(f"Config found at {config_path.absolute()}")
    else:
        logger.warning("No config.yaml found, using defaults")

    logger.info("Service Started. Entering main loop.")
    
    try:
        count = 0
        while True:
            logger.info(f"Heartbeat: {count}")
            count += 1
            time.sleep(5)
    except KeyboardInterrupt:
        logger.info("Service stopping...")

if __name__ == "__main__":
    main()
