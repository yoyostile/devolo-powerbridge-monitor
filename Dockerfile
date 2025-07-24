FROM ruby:3.2-slim

WORKDIR /app

RUN apt-get update && apt-get install -y curl \
    && rm -rf /var/lib/apt/lists/*

COPY devolo_monitor.rb /app/
COPY devolo_cli.rb /app/
COPY logger.rb /app/

RUN useradd -m -u 1000 appuser && \
    chown -R appuser:appuser /app

USER appuser

ENV RUBYOPT="-W0"
ENV CONFIG_FILE="/app/config.yml"

RUN echo '#!/bin/bash\n\
if [ ! -f "$CONFIG_FILE" ]; then\n\
    echo "Config file not found. Please mount config.yml to $CONFIG_FILE"\n\
    echo "Example: docker run -v /path/to/config.yml:$CONFIG_FILE yoyostile/devolo-powerbridge-monitor"\n\
    exit 1\n\
fi\n\
\n\
case "$1" in\n\
    "monitor")\n\
        exec ruby devolo_cli.rb monitor\n\
        ;;\n\
    "check")\n\
        exec ruby devolo_cli.rb check\n\
        ;;\n\
    "restart")\n\
        exec ruby devolo_cli.rb restart\n\
        ;;\n\
    "help"|"--help"|"-h")\n\
        exec ruby devolo_cli.rb help\n\
        ;;\n\
    *)\n\
        echo "Usage: docker run yoyostile/devolo-powerbridge-monitor [monitor|check|restart|help]"\n\
        echo "Default action is monitor"\n\
        exec ruby devolo_cli.rb monitor\n\
        ;;\n\
esac' > /app/entrypoint.sh && chmod +x /app/entrypoint.sh

ENTRYPOINT ["/app/entrypoint.sh"]

CMD ["monitor"]
