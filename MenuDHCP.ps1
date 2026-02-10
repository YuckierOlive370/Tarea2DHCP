function Validar-IP {
    param ($ip)
    if ($ip -match '^((25[0-5]|2[0-4]\d|1\d{2}|[1-9]?\d)\.){3}(25[0-5]|2[0-4]\d|1\d{2}|[1-9]?\d)$') {
        return ($ip -ne "255.255.255.255" -and $ip -ne "0.0.0.0")
    }
    return $false
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

function Instalar {
    param (
        [string]$subnetMask = "255.255.255.0"
    )
    Write-Host "Servicio DHCP Instalandose..." -ForegroundColor Green

    $scopeName = Read-Host "Nombre del ambito"
    $startIP   = Pedir-IP "IP inicial"

    do {
        $endIP = Pedir-IP "IP final"

        $startInt = IP-a-Int $startIP
        $endInt   = IP-a-Int $endIP

        if ($startInt -gt $endInt) {
            Write-Host "La IP inicial no puede ser mayor que la IP final"
        }
    } until ($startInt -le $endInt)

    $maskInt = IP-a-Int $subnetMask
    $startNet = $startInt -band $maskInt
    $endNet = $endInt -band $maskInt
    if ($startNet -ne $endNet) {
        Write-Host "La IP inicial y la IP final no pertenecen a la misma subred."
        return
    }

    $gateway = Pedir-IP "Gateway"

    $gwInt = IP-a-Int $gateway
    $gwNet = $gwInt -band $maskInt

    if ($gwNet -ne $startNet) {
        Write-Host "El gateway no pertenece al mismo rango de la subred."
        return
    }

    if ($gwInt -lt $startInt -or $gwInt -gt $endInt) {
        Write-Host "El gateway no se encuentra dentro del rango del ambito DHCP."
        return
    }

    $dns = Pedir-IP "DNS"

    do {
        $lease = Read-Host "Tiempo de concesion (dias)"
    } until ($lease -match '^\d+$')

    try {

        # Instalacion silenciosa DHCP
        Install-WindowsFeature DHCP -IncludeManagementTools -ErrorAction Stop | Out-Null
        Import-Module DhcpServer -ErrorAction Stop
        Start-Service DHCPServer

        # Crear el ambito
        Add-DhcpServerv4Scope `
            -Name $scopeName `
            -StartRange $startIP `
            -EndRange $endIP `
            -SubnetMask $subnetMask `
            -LeaseDuration (New-TimeSpan -Days $lease) | Out-Null
            
        Write-Host "Ambito creado y configurado correctamente." -ForegroundColor Green
    }
    catch {
        Write-Host "Error al crear el ambito: $_" -ForegroundColor Red
    }

    $scope = Get-DhcpServerv4Scope |
    Where-Object { $_.StartRange -eq $startIP -and $_.EndRange -eq $endIP }
    
    Set-DhcpServerv4OptionValue `
    -ScopeId $scope.ScopeId `
    -Router $gateway `
    -DnsServer $dns


}

function InstalarVal {
    $dhcpFeature = Get-WindowsFeature -Name DHCP
    if ($dhcpFeature.Installed) {
        Write-Host "El rol DHCP ya esta instalado."
        $respuesta = Read-Host "¿Deseas Eliminaro esto eliminara tus ambitos existenstes y se necesitara reinicar tu PC? (S/N)"
        if ($respuesta -match '^[sS]$') {
            Uninstall-WindowsFeature DHCP -ErrorAction Stop | Out-Null
            Restart-Computer
        } else {
            Write-Host "Se mantiene la instalacion existente."
        }
    } else {
        Instalar
    }
}

function VerificarServicio {
    if ((Get-WindowsFeature -Name DHCP).Installed) {
        Write-Host "El rol DHCP ya esta instalado."
    } else {
        Write-Host "El rol DHCP no esta instalado."
        $respuesta = Read-Host "¿Deseas instalarlo ahora? (S/N)"
        if ($respuesta -match '^[sS]$') {
            Instalar
        } else {
            Write-Host "Instalacion cancelada por el usuario."
        }
    }
}

function ReiniciarDHCP {
    Write-Host "Reiniciando servicio DHCP..."
    try {
        Restart-Service -Name "DHCPServer" -Force -ErrorAction Stop
        Write-Host "Servicio DHCP reiniciado correctamente." -ForegroundColor Green
    } catch {
        Write-Host "Error al reiniciar el servicio DHCP: $_" -ForegroundColor Red
    }
}


function ListarConcesiones{
    Get-Service DHCPServer

    Get-DhcpServerv4Lease |
    Select-Object IPAddress, HostName, ClientId, LeaseExpiryTime |
    Format-Table -AutoSize
}

$con = "S"

while ($con -match '^[sS]$') {
    Write-Host "Tarea 2: Automatizacion y Gestion del Servidor DHCP"
    Write-Host "++++++++ Menu de Opciones ++++++++"
    Write-Host "1.-Verificar la presencia del servicio"
    Write-Host "2.-Instalar el servicio"
    Write-Host "3.-Monitoreo"
    Write-Host "4.-Reiniciar Servivicios"
    Write-Host "5.-Salir"
    $op = [int](Read-Host "Selecciona: ")
    switch($op){
        1{VerificarServicio}
        2{InstalarVal}
        3{ListarConcesiones}
        4{ReiniciarDHCP}
        5{$con = "n"}
        default{Write-Host "Opcion no valida"}
    }
}
Write-Host "Programa terminado."
