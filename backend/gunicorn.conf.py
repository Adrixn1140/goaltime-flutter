"""Railway inyecta PORT. No requiere un puerto fijo ni un dispositivo Android."""

import os

bind = f"0.0.0.0:{int(os.getenv('PORT', '5000'))}"
workers = int(os.getenv("WEB_CONCURRENCY", "1"))
timeout = 120
accesslog = "-"
errorlog = "-"
