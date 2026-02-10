#!/bin/bash

INTERFAZ="ens37"
MASCARA="255.255.255.0"

ValidarIp() { # valida formato y descarta 255.255.255.255 y 0.0.0.0
    local ip=$1
    if [[ $ip =~ ^((25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.){3}(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])$ ]]; then
        [[ "$ip" != "255.255.255.255" && "$ip" != "0.0.0.0" ]]
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

VerificarServicio() {
    if dpkg -l | grep -q isc-dhcp-server; then
        read -p "DHCP ya instalado. ¿Deseas reinstalarlo? (S/N): " r
        if [[ $r =~ ^[sS]$ ]]; then
            sudo apt-get remove isc-dhcp-server -y > /dev/null 2>&1
            Instalar
        else
            echo "Se mantiene la instalación existente"
        fi
    else
        echo "El servicio DHCP no esta instalado"
    fi

    sudo sed -i "s/^INTERFACESv4=.*/INTERFACESv4=\"$INTERFAZ\"/" /etc/default/isc-dhcp-server
}

Instalar() {
    read -p "Nombre del ambito: " scope

    rango_inicio=$(PedirIp "IP inicial: ")

    while true; do
        rango_fin=$(PedirIp "IP final: ")
        (( $(IPaInt "$rango_inicio") <= $(IPaInt "$rango_fin") )) && break
        echo "La IP inicial no puede ser mayor que la IP final"
    done

    # Validación correcta: inicio y fin en la misma subred
    inicioInt=$(IPaInt "$rango_inicio")
    finInt=$(IPaInt "$rango_fin")
    maskInt=$(IPaInt "$MASCARA")

    (( (inicioInt & maskInt) == (finInt & maskInt) )) || {
        echo "El rango no pertenece a la misma subred"
        return
    }

    read -p "Tiempo de concesion (en segundos): " lease_time
    gateway=$(PedirIp "Gateway: ")
    dns=$(PedirIp "DNS: ")

    # Red calculada desde el rango (NO desde la IP del servidor)
    redInt=$(( inicioInt & maskInt ))

    red=$(printf "%d.%d.%d.0" \
        $(( (redInt >> 24) & 255 )) \
        $(( (redInt >> 16) & 255 )) \
        $(( (redInt >> 8) & 255 )))

    sudo bash -c "cat > /etc/dhcp/dhcpd.conf" <<EOF
default-lease-time $lease_time;
max-lease-time $lease_time;

subnet $red netmask $MASCARA {
    range $rango_inicio $rango_fin;
    option routers $gateway;
    option domain-name-servers $dns;
}
EOF

    sudo dhcpd -t && sudo systemctl restart isc-dhcp-server
    echo "Ambito DHCP configurado correctamente."
}

ListarConcesiones() {
    systemctl status isc-dhcp-server --no-pager
    echo "Concesiones activas:"
    cat /var/lib/dhcp/dhcpd.leases
}

Reiniciar() { # reinicia el servicio dhcp
    sudo systemctl restart isc-dhcp-server
    echo "Servicio DHCP reiniciado."
}

while true; do
    echo "===== Automatización y Gestión del Servidor DHCP ====="
    echo "1.- Verificar la presencia del servicio"
    echo "2.- Instalar el servicio"
    echo "3.- Monitoreo"
    echo "4.- Reiniciar Servicios"
    echo "5.- Salir"
    read -p "Selecciona una opción: " opcion

    case $opcion in
        1) VerificarServicio ;;
        2) Instalar ;;
        3) ListarConcesiones ;;
        4) Reiniciar ;;
        5) echo "Saliendo..."; break ;;
        *) echo "Opción inválida" ;;
    esac
    echo ""
done