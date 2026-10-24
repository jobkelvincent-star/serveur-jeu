# Fabrique la "boîte" qui fait tourner le serveur chez l'hébergeur.
# GODOT_VERSION doit être la même version que celle de ton Godot (par exemple 4.7-stable, 4.7.1-stable...).
FROM debian:bookworm-slim

ARG GODOT_VERSION=4.7.1-stable

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates wget unzip libfontconfig1 libxcursor1 libxinerama1 libxrandr2 libxi6 libgl1 libasound2 \
    && rm -rf /var/lib/apt/lists/*

RUN wget -q "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_linux.x86_64.zip" -O /tmp/godot.zip \
    && unzip -q /tmp/godot.zip -d /tmp \
    && mv "/tmp/Godot_v${GODOT_VERSION}_linux.x86_64" /usr/local/bin/godot \
    && chmod +x /usr/local/bin/godot \
    && rm /tmp/godot.zip

WORKDIR /app
COPY . /app

EXPOSE 8080
CMD ["godot", "--headless", "--path", "/app", "--script", "res://serveur.gd"]
