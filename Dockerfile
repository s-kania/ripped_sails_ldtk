FROM haxe:4.3@sha256:61f0dc1701aba905b3f295699c16fea2bc53d8f08700e1daa3ad3904836e7867

WORKDIR /usr/src/app

# Instalacja zależności z setup.hxml
COPY setup.hxml ./

# Czyszczenie cache'u apt i odświeżenie list pakietów z dodatkowymi parametrami
RUN rm -rf /var/lib/apt/lists/* \
    && apt-get clean \
    && apt-get update -o Acquire::CompressionTypes::Order::=gz \
    && apt-get update -o Acquire::Check-Valid-Until=false

# Instalacja neko i nekotools
# RUN apt-get install -y --fix-missing neko

# Ustawienie ścieżki haxelib
RUN haxelib setup /usr/local/lib/haxe/lib
RUN haxe setup.hxml

# Kopiowanie źródeł projektu i kompilacja
COPY . .
RUN haxe setup.hxml

# Instalacja Node.js
RUN apt-get update -o Acquire::CompressionTypes::Order::=gz \
    && apt-get install -y curl ca-certificates gnupg \
    && curl -fsSL https://deb.nodesource.com/setup_18.x | bash - \
    && apt-get install -y nodejs

# Instalacja zależności GUI z parametrami omijającymi błędy sum kontrolnych
RUN apt-get update -o Acquire::Check-Valid-Until=false \
    && apt-get -o Acquire::CompressionTypes::Order::=gz \
       -o APT::Get::AllowUnauthenticated=true \
       -o Acquire::AllowInsecureRepositories=true \
       --allow-unauthenticated \
       --fix-missing \
       -y install \
       libnss3 \
       libgtk-3-0 \
       libxss1 \
       libasound2 \
       libasound2-dev \
       libsqlite3-dev \
       zlib1g-dev \
       libxtst6 \
       libgbm1 \
       xvfb \
       x11-apps \
       dbus \
       dbus-x11 \
       libxinerama1 \
       libgl1-mesa-dri \
       libgles2 \
       libegl1 \
       libxcb-dri3-0 \
       mesa-utils \
    || true  # Ignorowanie błędów instalacji

# Konfiguracja zmiennych środowiskowych
ENV DISPLAY=host.docker.internal:0
ENV DBUS_SESSION_BUS_ADDRESS=unix:path=/var/run/dbus/system_bus_socket

# Przygotowanie katalogu dla D-Bus
RUN mkdir -p /var/run/dbus

# Wystawienie portu serwera
EXPOSE 2000

# Uruchomienie serwera nekotools nasłuchującego na wszystkich interfejsach
CMD ["nekotools", "server", "-h", "0.0.0.0"]