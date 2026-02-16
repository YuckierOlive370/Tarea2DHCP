#!/bin/bash

INTERFAZ="ens37"
MASCARA="255.255.255.0"

ValidarIp() { # valida formato y descarta 255.255.255.255 y 0.0.0.0
    local ip=$1
    if [[ $ip =~ ^((25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.){3}(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])$ ]]; then
        [[ "$ip" != "255.255.255.255" && "$ip" != "0.0.0.0" && "$ip" != "127.0.0.1" ]]
        return $?
    fi
    return 1
}

IPaInt() {
    local IFS=.
    read -r a b c d <<< "$1"
    echo $(( (a<<24) + (b<<16) + (c<<8) + d ))
}

PedirIp() {
    local mensaje=$1
    while true; do
        read -p "$mensaje" ip
        if ValidarIp "$ip"; then
            echo "$ip"
            return
        else
            echo "IP no valida, intenta de nuevo"
        fi
    done
}

CalcularMascara() {
    local ip=$1
    local IFS=.
    read -r a b c d <<< "$ip"

    if (( a >= 1 && a <= 126 )); then
        echo "255.0.0.0"
    elif (( a >= 128 && a <= 191 )); then
        echo "255.255.0.0"
    elif (( a >= 192 && a <= 223 )); then
        echo "255.255.255.0"
    else
        echo "255.255.255.0"
    fi
}

MaskToPrefix() {
    case "$1" in
        255.0.0.0) echo 8 ;;
        255.255.0.0) echo 16 ;;
        255.255.255.0) echo 24 ;;
        255.255.255.128) echo 25 ;;
        255.255.255.192) echo 26 ;;
        255.255.255.224) echo 27 ;;
        255.255.255.240) echo 28 ;;
        255.255.255.248) echo 29 ;;
        255.255.255.252) echo 30 ;;
        255.255.255.254) echo 31 ;;
        255.255.255.255) echo 32 ;;
        *) echo 0 ;;
    esac
}

VerificarServicio() {
    if dpkg -l | grep -q bind9; then
        echo "DNS ya está instalado"
        read -p "¿Deseas reinstalarlo? (S/N): " r
        if [[ $r =~ ^[sS]$ ]]; then
            apt purge bind9 -y
            apt install bind9 dnsutils -y
        fi
    else
        echo "El servicio DNS no está instalado"
    fi
}

CalcularRedInversa() {
    local ip=$1
    local IFS=.
    read -r a b c d <<< "$ip"
    echo "$c.$b.$a"
}

PedirValor() {
    local mensaje=$1
    local defecto=$2
    local valor

    read -p "$mensaje [$defecto]: " valor
    echo "${valor:-$defecto}"
}

ConfigurarOpcionesBind() {
    echo "Configurando named.conf.options..."

    cat <<EOF > /etc/bind/named.conf.options
options {
    directory "/var/cache/bind";

    listen-on { any; };
    listen-on-v6 { any; };

    allow-query { any; };

    recursion yes;
    dnssec-validation auto;
};
EOF
}

Instalar() {
    if dpkg -l | grep -q bind9; then
        echo "DNS ya esta instalado si quieres volver a instalarlo vee a Verificar servicio..."
        return 1
    fi
    apt update
    apt install bind9 dnsutils -
    systemctl enable bind9
}

Configurar() {
    echo "===== CONFIGURACIÓN DE DNS ====="

    # Datos principales
    read -p "Dominio (ej: ejemplo.com): " DOMINIO
    if grep -q "zone \"$DOMINIO\"" /etc/bind/named.conf.local; then
    echo "La zona $DOMINIO ya existe"
    return
    fi

    IP_DNS=$(PedirIp "IP del servidor DNS: ")
    RED_INV=$(CalcularRedInversa "$IP_DNS")

    ConfigurarOpcionesBind

    ZONA_DIR="/etc/bind/db.$DOMINIO"
    ZONA_INV="/etc/bind/db.$RED_INV"

    # Serial automático
    SERIAL=$(date +%Y%m%d01)

    # Valores SOA configurables
    REFRESH=$(PedirValor "Refresh (segundos)" 604800)
    RETRY=$(PedirValor "Retry (segundos)" 86400)
    EXPIRE=$(PedirValor "Expire (segundos)" 2419200)
    NEGTTL=$(PedirValor "Negative Cache TTL (segundos)" 604800)

    # Registrar zonas en BIND
    cat <<EOF >> /etc/bind/named.conf.local
zone "$DOMINIO" {
    type master;
    file "$ZONA_DIR";
};

zone "$RED_INV.in-addr.arpa" {
    type master;
    file "$ZONA_INV";
};
EOF

    # Crear zona directa
    cat <<EOF > $ZONA_DIR
\$TTL 604800
@ IN SOA ns1.$DOMINIO. admin.$DOMINIO. (
    $SERIAL     ; Serial
    $REFRESH    ; Refresh
    $RETRY      ; Retry
    $EXPIRE     ; Expire
    $NEGTTL )   ; Negative Cache TTL

@   IN NS ns1.$DOMINIO.
ns1 IN A  $IP_DNS
www IN A  $IP_DNS
EOF

    # Zona inversa
    ULTIMO_OCTETO=${IP_DNS##*.}

    cat <<EOF > $ZONA_INV
\$TTL 604800
@ IN SOA ns1.$DOMINIO. admin.$DOMINIO. (
    $SERIAL
    $REFRESH
    $RETRY
    $EXPIRE
    $NEGTTL )

@ IN NS ns1.$DOMINIO.
$ULTIMO_OCTETO IN PTR $DOMINIO.
EOF

    # Validaciones
    named-checkconf || return
    named-checkzone $DOMINIO $ZONA_DIR || return
    named-checkzone $RED_INV.in-addr.arpa $ZONA_INV || return

    # Reinicio del servicio
    systemctl restart bind9

    echo "DNS configurado correctamente para $DOMINIO"
}

Reconfigurar() {
    echo "===== RECONFIGURANDO DNS ====="

    # Verificar sintaxis global
    if ! named-checkconf; then
        echo "Error en la configuración global de BIND"
        return 1
    fi

    # Verificar todas las zonas registradas
    while read -r zona; do
        archivo=$(grep -A2 "zone \"$zona\"" /etc/bind/named.conf.local | awk -F\" '/file/ {print $2}')
        if [[ -f $archivo ]]; then
            named-checkzone "$zona" "$archivo" || return 1
        fi
    done < <(grep 'zone "' /etc/bind/named.conf.local | awk -F\" '{print $2}')

    # Recargar servicio
    systemctl reload bind9

    if systemctl is-active --quiet bind9; then
        echo "DNS recargado correctamente"
    else
        echo "No se pudo recargar, intentando reiniciar..."
        systemctl restart bind9
    fi
}

ABCdominios() {
    echo "===== ABC DE DOMINIOS DNS ====="
    echo "1) Alta (crear dominio)"
    echo "2) Baja (eliminar dominio)"
    echo "3) Consulta (listar dominios)"
    echo "4) Volver"
    read -p "Selecciona una opción: " op

    case $op in
        1)
            echo "Alta de dominio"
            Configurar
            ;;

        2)
            echo "Baja de dominio"
            read -p "Dominio a eliminar (ej: ejemplo.com): " DOM

            # Obtener archivo de zona directa
            ZONA_DIR=$(grep -A2 "zone \"$DOM\"" /etc/bind/named.conf.local | awk -F\" '/file/ {print $2}')

            if [[ -z $ZONA_DIR ]]; then
                echo "El dominio no existe"
                return
            fi

            # Calcular red inversa desde la IP A
            IP_DNS=$(grep "IN A" "$ZONA_DIR" | awk '{print $NF}' | head -n1)
            RED_INV=$(CalcularRedInversa "$IP_DNS")
            ZONA_INV="/etc/bind/db.$RED_INV"

            # Eliminar zonas del archivo de configuración
            sed -i "/zone \"$DOM\"/,/};/d" /etc/bind/named.conf.local
            sed -i "/zone \"$RED_INV.in-addr.arpa\"/,/};/d" /etc/bind/named.conf.local

            # Eliminar archivos de zona
            rm -f "$ZONA_DIR" "$ZONA_INV"

            # Recargar DNS
            systemctl reload bind9

            echo "Dominio $DOM eliminado correctamente"
            ;;

        3)
            echo "Dominios configurados:"
            grep 'zone "' /etc/bind/named.conf.local | awk -F\" '{print $2}'
            ;;

        4)
            return
            ;;

        *)
            echo "Opción inválida"
            ;;
    esac
}

while true; do
    echo "===== Automatización y Gestión de DNS ====="
    echo "1.- Verificar Instalacion"
    echo "2.- Instalar"
    echo "3.- Configurar"
    echo "4.- Reconfigurar"
    echo "5.- ABC Dominios"
    echo "6.- Salir"
    read -p "Selecciona una opción: " opcion

    case $opcion in
        1) VerificarServicio ;;
        2) Instalar ;;
        3) Configurar ;;
        4) Reconfigurar ;;
        5) ABCdominios ;;
        6) echo "Saliendo..."; break ;;
        *) echo "Opción inválida" ;;
    esac
    echo ""
done
