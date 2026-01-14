import time
import sys
import logging
from pathlib import Path
from http.server import HTTPServer, BaseHTTPRequestHandler
from threading import Thread
import json
from datetime import datetime

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[logging.StreamHandler(sys.stdout)]
)
logger = logging.getLogger("MockService")

# Read version from VERSION file
def get_version():
    version_file = Path(__file__).parent.parent / "VERSION"
    if version_file.exists():
        return version_file.read_text().strip()
    return "unknown"

VERSION = get_version()

class HealthHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        # Override to use our logger instead of stderr
        logger.info("%s - %s" % (self.client_address[0], format % args))

    def do_GET(self):
        if self.path == '/health' or self.path == '/':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()

            response = {
                'status': 'healthy',
                'service': 'DicomGatewayMock',
                'current_version': VERSION,
                'python_version': sys.version.split()[0]
            }

            # Add deployment history from database
            try:
                from .db import get_deployment_history

                deployments = get_deployment_history(limit=10)
                response['deployment_history'] = [
                    {
                        'version': d['version'],
                        'deployed_at': d['deployed_at'],
                        'method': d['deployment_method']
                    }
                    for d in deployments
                ]
            except Exception as e:
                response['deployment_history_error'] = str(e)

            self.wfile.write(json.dumps(response, indent=2).encode())
        else:
            self.send_response(404)
            self.end_headers()

def start_health_server(port=8080):
    """Start HTTP health check server in background thread"""
    server = HTTPServer(('0.0.0.0', port), HealthHandler)
    thread = Thread(target=server.serve_forever, daemon=True)
    thread.start()
    logger.info(f"Health server started on http://localhost:{port}/health")
    return server

def main():
    logger.info("Service Starting...")
    logger.info(f"Service Version: {VERSION}")
    logger.info(f"Python Version: {sys.version}")

    # Start health check server
    health_server = start_health_server(port=8080)

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
        health_server.shutdown()

if __name__ == "__main__":
    main()
