#!/bin/bash

# ===============================
# VARIABLES (ajusta si es necesario)
# ===============================
INTERFAZ="ens37"
IP_DNS="192.168.1.10"
DOMINIO="reprobados.com"
RED_INVERSA="1.168.192"
ZONA_DIRECTA="/etc/bind/db.reprobados.com"
ZONA_INVERSA="/etc/bind/db.192"

# ===============================
# VALIDAR EJECUCIÓN COMO ROOT
# ===============================
if [[ $EUID -ne 0 ]]; then
    echo "❌ Debes ejecutar este script como root"
    exit 1
fi

echo "✅ Ejecutando como superusuario"

# ===============================
# MOSTRAR IP Y ADAPTADORES
# ===============================
echo "📡 Direcciones IP del sistema:"
ip a

# ===============================
# INSTALAR BIND9
# ===============================
echo "📦 Instalando BIND9..."
apt update
apt install bind9 dnsutils -y

# ===============================
# CONFIGURAR OPCIONES GENERALES
# ===============================
echo "⚙️ Configurando named.conf.options..."

cat <<EOF > /etc/bind/named.conf.options
options {
    directory "/var/cache/bind";

    recursion yes;
    allow-query { any; };

    forwarders {
        8.8.8.8;
        8.8.4.4;
    };

    dnssec-validation auto;
    listen-on { any; };
    listen-on-v6 { any; };
};
EOF

# ===============================
# CONFIGURAR ZONAS
# ===============================
echo "🗂️ Configurando zonas directa e inversa..."

cat <<EOF >> /etc/bind/named.conf.local

zone "$DOMINIO" {
    type master;
    file "$ZONA_DIRECTA";
};

zone "$RED_INVERSA.in-addr.arpa" {
    type master;
    file "$ZONA_INVERSA";
};
EOF

# ===============================
# CREAR ZONA DIRECTA
# ===============================
echo "📝 Creando zona directa..."

cat <<EOF > $ZONA_DIRECTA
\$TTL    604800
@   IN  SOA ns1.$DOMINIO. admin.$DOMINIO. (
            2         ; Serial
       604800         ; Refresh
        86400         ; Retry
      2419200         ; Expire
       604800 )       ; Negative Cache TTL

@       IN  NS      ns1.$DOMINIO.
ns1     IN  A       $IP_DNS
www     IN  A       $IP_DNS
EOF

# ===============================
# CREAR ZONA INVERSA
# ===============================
echo "🔁 Creando zona inversa..."

cat <<EOF > $ZONA_INVERSA
\$TTL    604800
@   IN  SOA ns1.$DOMINIO. admin.$DOMINIO. (
            2
       604800
        86400
      2419200
       604800 )

@       IN  NS      ns1.$DOMINIO.
10      IN  PTR     $DOMINIO.
EOF

# ===============================
# VERIFICAR CONFIGURACIÓN
# ===============================
echo "🔍 Verificando configuración..."
named-checkconf
named-checkzone $DOMINIO $ZONA_DIRECTA
named-checkzone $RED_INVERSA.in-addr.arpa $ZONA_INVERSA

# ===============================
# REINICIAR Y HABILITAR SERVICIO
# ===============================
echo "🔄 Reiniciando BIND9..."
systemctl restart bind9
systemctl enable bind9

echo "📊 Estado del servicio:"
systemctl status bind9 --no-pager

echo "✅ DNS configurado correctamente"
