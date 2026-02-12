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
        echo "255.0.0.0"      # Clase A
    elif (( a >= 128 && a <= 191 )); then
        echo "255.255.0.0"    # Clase B
    elif (( a >= 192 && a <= 223 )); then
        echo "255.255.255.0"  # Clase C
    else
        echo "255.255.255.0"  # Valor por defecto
    fi
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

}

Instalar() {
    if dpkg -l | grep -q isc-dhcp-server; then
    echo "DHCP ya esta instalado si quieres volver a instalarlo vee a Verificar servicio..."
    return 1
    fi

    echo "Iniciando la configuracion..."
    read -p "Nombre del ambito: " scope

    # Capturar IP fija del servidor 
    ip_fija=$(PedirIp "IP fija del servidor: ")
    mascara=$(CalcularMascara "$ip_fija")
    read -p "Gateway (opcional, deja vacio si no aplica): " gateway

    echo "IP fija del servidor: $ip_fija"
    # Calcular IP inicial del rango = IP fija + 1 
    inicioInt=$(IPaInt "$ip_fija") 
    inicioInt=$((inicioInt + 1)) 
    rango_inicio=$(printf "%d.%d.%d.%d" \
        $(( (inicioInt >> 24) & 255 )) \
        $(( (inicioInt >> 16) & 255 )) \
        $(( (inicioInt >> 8) & 255 )) \
        $(( inicioInt & 255 )) )
    echo "IP inicial del ámbito: $rango_inicio"

    # Configurar IP fija en la interfaz ens37 editando /etc/network/interfaces
    sudo bash -c "cat > /etc/network/interfaces.d/$INTERFAZ.cfg" <<EOF
    auto $INTERFAZ
    iface $INTERFAZ inet static
        address $ip_fija
        netmask $mascara
    EOF

    echo "Configuración de red escrita en /etc/network/interfaces.d/$INTERFAZ.cfg"
    echo "Recargando interfaz..."
    sudo ifdown $INTERFAZ && sudo ifup $INTERFAZ

#validar la ip final mismo rango
    while true; do
        rango_fin=$(PedirIp "IP final: ")

        inicioInt=$(IPaInt "$rango_inicio")
        finInt=$(IPaInt "$rango_fin")
        maskInt=$(IPaInt "$MASCARA")

        if (( inicioInt > finInt )); then
            echo "La IP inicial no puede ser mayor que la IP final"
        elif (( (inicioInt & maskInt) != (finInt & maskInt) )); then
            echo "El rango no pertenece a la misma subred"
        else
            break
        fi

    done

    echo "IP final valida: $rango_fin"

    read -p "DNS primario (opcional): " dns 
    read -p "DNS alternativo (opcional): " dns_alt
    read -p "Tiempo de concesion (en segundos): " lease_time

    redInt=$(( inicioInt & maskInt ))
    red=$(printf "%d.%d.%d.0" \
        $(( (redInt >> 24) & 255 )) \
        $(( (redInt >> 16) & 255 )) \
        $(( (redInt >> 8) & 255 )))

    # Configurar interfaz en /etc/default/isc-dhcp-server
    sudo sed -i "s/^INTERFACESv4=.*/INTERFACESv4=\"$INTERFAZ\"/" /etc/default/isc-dhcp-server

    echo "Instalando DHCP..."
    sudo apt-get update -y -qq > /dev/null 2>&1
    sudo apt-get install isc-dhcp-server -y -qq > /dev/null 2>&1
    sudo systemctl enable isc-dhcp-server > /dev/null 2>&1

    # Construir bloque de opciones dinámicamente
    options=""
    [[ -n "$gateway" ]] && options+="    option routers $gateway;\n"
    if [[ -n "$dns" || -n "$dns_alt" ]]; then
        dns_list=""
        [[ -n "$dns" ]] && dns_list="$dns"
        [[ -n "$dns_alt" ]] && dns_list="$dns_list, $dns_alt"
        options+="    option domain-name-servers $dns_list;\n"
    fi

    # Escribir configuración en dhcpd.conf
    sudo bash -c "cat > /etc/dhcp/dhcpd.conf" <<EOF
    default-lease-time $lease_time;
    max-lease-time $lease_time;

    subnet $red netmask $MASCARA {
        range $rango_inicio $rango_fin;
    $options}
    EOF

    echo "Validando configuración..."
    sudo dhcpd -t
    echo "Reiniciando servicio DHCP..."
    sudo systemctl restart isc-dhcp-server
    echo "Ambito DHCP configurado correctamente."

}

ListarConcesiones() {
    if dpkg -l | grep -q isc-dhcp-server; then
        systemctl status isc-dhcp-server --no-pager
        echo "Concesiones activas:"
        cat /var/lib/dhcp/dhcpd.leases
    else
        echo "No esta instalado DHCP"
    fi
}

Reiniciar() { # reinicia el servicio dhcp
    if dpkg -l | grep -q isc-dhcp-server; then
        sudo systemctl restart isc-dhcp-server
        echo "Servicio DHCP reiniciado."
    else
        echo "No esta instalado DHCP"
    fi
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