#!/bin/bash

ValidarIp() {
    local ip=$1
    if [[ $ip =~ ^((25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.){3}(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])$ ]]; then
        return 0
    else
        return 1
    fi
}

PedirIp() {
    local mensaje=$1
    local ip=""
    while true; do
        read -p "$mensaje" ip
        if ValidarIp "$ip"; then
            echo "$ip"
            break
        else
            echo "IP no valida, intenta de nuevo"
        fi
    done
}

VerificarServicio() {
    if ! dpkg -l | grep -q isc-dhcp-server; then
        echo "Instalando Rol DHCP..."
        sudo apt-get update -y
        sudo apt-get install isc-dhcp-server -y
        sudo systemctl enable isc-dhcp-server
    else
        echo "El servicio DHCP ya esta instalado"
    fi

    echo "Configurando interfaz ens37 para DHCP..."
    sudo sed -i 's/^INTERFACESv4=.*/INTERFACESv4="ens37"/' /etc/default/isc-dhcp-server
}

Configurar() {
    read -p "Nombre del ambito: " scope
    rango_inicio=$(PedirIp "IP inicial: ")
    rango_fin=$(PedirIp "IP final: ")
    read -p "Tiempo de concesion (en segundos): " lease_time
    gateway=$(PedirIp "Gateway: ")
    dns=$(PedirIp "DNS: ")

    sudo bash -c "cat > /etc/dhcp/dhcpd.conf" <<EOF
default-lease-time $lease_time;
max-lease-time $lease_time;

subnet 192.168.100.0 netmask 255.255.255.0 {
    range $rango_inicio $rango_fin;
    option routers $gateway;
    option domain-name-servers $dns;
}
EOF

    echo "Validando configuración..."
    sudo dhcpd -t
    echo "Reiniciando servicio DHCP..."
    sudo systemctl restart isc-dhcp-server
}

ConsultarEstado() {
    echo "Estado del servicio DHCP:"
    systemctl status isc-dhcp-server --no-pager
}

ListarConcesiones() {
    echo "Concesiones activas:"
    cat /var/lib/dhcp/dhcpd.leases
}

while true; do
    echo "===== Automatización y Gestión del Servidor DHCP ====="
    echo "1.- Verificar la presencia del servicio"
    echo "2.- Configuración dinámica"
    echo "3.- Consultar el estado del servicio en tiempo real"
    echo "4.- Listar las concesiones (leases) activas"
    echo "5.- Salir"
    read -p "Selecciona una opción: " opcion

    case $opcion in
        1) VerificarServicio ;;
        2) Configurar ;;
        3) ConsultarEstado ;;
        4) ListarConcesiones ;;
        5) echo "Saliendo..."; break ;;
        *) echo "Opción inválida" ;;
    esac
    echo ""
done

