function Validar-IP {
    param ($ip)
    return $ip -match '^((25[0-5]|2[0-4]\d|1\d{2}|[1-9]?\d)\.){3}(25[0-5]|2[0-4]\d|1\d{2}|[1-9]?\d)$'
}

function IP-a-Int {
    param ([string]$ip)
    $bytes = [System.Net.IPAddress]::Parse($ip).GetAddressBytes()
    [Array]::Reverse($bytes)
    return [BitConverter]::ToUInt32($bytes, 0)
}

function Pedir-IP {
    param (
        [string]$mensaje
    )

    do {
        $ip = Read-Host $mensaje
        if (-not (Validar-IP $ip)) {
            Write-Host "IP no valida, intenta de nuevo"
        }
    } until (Validar-IP $ip)

    return $ip
}

function VerificarServicio{
    if ((Get-WindowsFeature -Name DHCP).installed) {
        Write-Host "DHCP ya esta instalando"
    } else {
        Write-Host "Instalando Rol DHCP..."
        Install-WindowsFeature DHCP -IncludeManagementTools
    }
}

function Configurar{
    if (-not (Get-WindowsFeature DHCP).Installed) {
    Write-Host "El rol DHCP no esta instalado. Instalalo primero."
    return
    }

    $scopeName = Read-Host "Nombre del ambito"
    $startIP = Pedir-IP "IP inicial"

    do {
    $endIP = Pedir-IP "IP final"

    $startInt = IP-a-Int $startIP
    $endInt   = IP-a-Int $endIP

    if ($startInt -gt $endInt) {
        Write-Host "La IP inicial no puede ser mayor que la IP final"
    }
    } until ($startInt -le $endInt)

    $gateway = Pedir-IP "Gateway"
    $dns = Pedir-IP "DNS"
    do {
        $lease = Read-Host "Tiempo de concesion (días)"
    } until ($lease -match '^\d+$')

    #verificar si ya existe un ambito
    $scopeExistente = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue |
    Where-Object { $_.StartRange -eq $startIP -or $_.EndRange -eq $endIP }


    if  ($scopeExistente) {
        Write-Host "El ambito DHCP ya existe. No se creara uno nuevo"
    } else {
        try {
            Add-DhcpServerv4Scope `
            -Name $scopeName `
            -StartRange $startIP `
            -EndRange $endIP `
            -SubnetMask 255.255.255.0 `
            -LeaseDuration (New-TimeSpan -Days $lease)
            Write-Host "Ambito creado correctamente"
            }
            catch {
                Write-Host "Error al crear el ambito: ya existe o es invalido"
                }

    }

    Set-DhcpServerv4OptionValue `
    -Router ([IPAddress]$gateway) `
    -DnsServer @([IPAddress]$dns)

}

function ConsultarEstado{
    Get-Service DHCPServer
}

function ListarConcesiones{
    Get-DhcpServerv4Lease |
    Select-Object IPAddress, HostName, ClientId, LeaseExpiryTime |
    Format-Table -AutoSize
}

$con = "S"

while ($con -eq "S") {
    Write-Host "Tarea 2: Automatizacion y Gestion del Servidor DHCP"
    Write-Host "++++++++ Menu de Opciones ++++++++"
    Write-Host "1.-Verificar la presencia del servicio"
    Write-Host "2.-Configuracion dinamica"
    Write-Host "3.-Consultar el estado del servicio en tiempo real"
    Write-Host "4.-Listar las concesiones (leases) activas"
    $op = [int](Read-Host "Selecciona: ")
    switch($op){
        1{VerificarServicio}
        2{Configurar}
        3{ConsultarEstado}
        4{ListarConcesiones}
        default{Write-Host "Opcion no valida"}
    }
    $con = Read-Host "¿Quieres seguir? (S/N)"
}
Write-Host "Programa terminado."
