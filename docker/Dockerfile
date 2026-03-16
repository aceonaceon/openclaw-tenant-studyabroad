FROM ghcr.io/openclaw/openclaw:latest

USER root

# ===== System packages (add your packages here) =====
# Base image is Debian bookworm. Use apt-get to install system tools.
# Remove or comment out packages you don't need.
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    && rm -rf /var/lib/apt/lists/*

# ===== npm global packages (add your packages here) =====
# Uncomment and add packages as needed:
# RUN npm install -g sharp puppeteer

# ===== Lobster platform files =====
RUN mkdir -p /opt/lobster/shared-skills /opt/lobster/base-workspace

COPY skills/ /opt/lobster/shared-skills/
COPY platform/ /opt/lobster/base-workspace/
COPY docker/entrypoint.sh /opt/lobster/entrypoint.sh
RUN chmod +x /opt/lobster/entrypoint.sh
RUN chown -R node:node /opt/lobster

USER node

ENTRYPOINT ["/opt/lobster/entrypoint.sh"]
CMD ["node", "dist/index.js"]
