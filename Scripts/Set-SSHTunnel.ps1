Param(
  [string]$ip1,
  [string]$ip2,
  [string]$port1,
  [string]$port2,
  [string]$username1,
  [string]$username2,
  [string]$password1,
  [string]$password2,
  [string]$tunnelPort,
  [string]$mode="ssh",
  [string]$multiTunnelsArgs
)

function preventSoftFailure([int]$multipleOpeningTimeout,[string]$soft,[string]$subSoft){
  if ($multipleOpeningTimeout -ne $null){
    if ($multipleOpeningTimeout -gt 0){
      try{
        if ($subSoft -ne $null){
          $res=(Get-Process -Name $subSoft -ErrorAction Stop | Select Name, StartTime | sort StartTime -Descending)[0].StartTime
        }else{
          $res=(Get-Process -Name $soft -ErrorAction Stop | Select Name, StartTime | sort StartTime -Descending)[0].StartTime
        }
        if ($res -ne $null){
          if ($res -gt 0){
            $res=$($res).AddSeconds($multipleOpeningTimeout)
            if ($(Get-Date) -le $res){
              write-host "Waiting time $res sec to prevent $soft crash"
              while ($(Get-Date) -le $res){
                sleep 1
              }
            }
          }
        }
      }catch{}
    }
  }
}
function Get-RandomPort(){
  try{
      $moduleName="Get-NetworkStatistics.ps1"
      Unblock-File -Path "$($global:currentLocation)\modules\$($moduleName)" -ErrorAction Stop
      Import-Module "$($global:currentLocation)\modules\$($moduleName)" -Force -ErrorAction Stop -Scope Local
      do{
          $portUsed=$false
          $minTunnelPort=$($XmlDocument | Select-Xml -XPath "/Settings/Proto/SSHTunnel/tunnel/port/min" | ForEach-Object { $_.Node.value })
          $maxTunnelPort=$($XmlDocument | Select-Xml -XPath "/Settings/Proto/SSHTunnel/tunnel/port/max" | ForEach-Object { $_.Node.value })
          $tunnelPort=Get-Random -Minimum $minTunnelPort -Maximum $maxTunnelPort
          foreach ($usedPort in Get-NetworkStatistics | Select LocalPort) {
              if ($usedPort.LocalPort -eq $tunnelPort){
                  $portUsed=$true
                  break
              }
          }
      } while($portUsed -eq $true)
      #cls
      return $tunnelPort
  }catch{
      Throw "An error has occured while loading the powershell module $($moduleName)!"
  }
}

$scriptPath=$(split-path -parent $MyInvocation.MyCommand.Definition)
[xml]$XmlDocument=Get-Content -Path "$($scriptPath)\Config.xml"
$debugMode=$($XmlDocument | Select-Xml -XPath "/Settings/General/debugMode" | ForEach-Object { $_.Node.value })

$soft=$XmlDocument | Select-Xml -XPath "/Settings/Proto/SSHTunnel/app" | ForEach-Object { $_.Node.value }
$softPath="$($scriptPath)\$($XmlDocument | Select-Xml -XPath "/Settings/App/$($soft)/path" | ForEach-Object { $_.Node.value })"
$multipleOpeningTimeout="$($XmlDocument | Select-Xml -XPath "/Settings/App/$($soft)/multipleOpeningTimeout" | ForEach-Object { $_.Node.value })"
$subSoft="$($XmlDocument | Select-Xml -XPath "/Settings/App/$($soft)/subApp" | ForEach-Object { $_.Node.value })"

$defaultPort=$($XmlDocument | Select-Xml -XPath "/Settings/Proto/SSHTunnel/defaultPort" | ForEach-Object { $_.Node.value })
$defaultUsername=$($XmlDocument | Select-Xml -XPath "/Settings/Proto/SSHTunnel/defaultUsername" | ForEach-Object { $_.Node.value })
if($defaultUsername -eq $null){
  $defaultUsername=$($XmlDocument | Select-Xml -XPath "/Settings/General/defaultUsername" | ForEach-Object { $_.Node.value })
}
$defaultPassword=$($XmlDocument | Select-Xml -XPath "/Settings/Proto/SSHTunnel/defaultPassword" | ForEach-Object { $_.Node.value })
if($defaultPassword -eq $null){
  $defaultPassword=$($XmlDocument | Select-Xml -XPath "/Settings/General/defaultPassword" | ForEach-Object { $_.Node.value })
}

$global:currentScript=$MyInvocation.MyCommand.Name
$global:currentLocation=Split-Path -Path $MyInvocation.MyCommand.Path
trap {sleep 1}

$multiTunnelsArgs=$multiTunnelsArgs.Replace("`r","")
$multiTunnelsArgs=$multiTunnelsArgs.Replace("`n","")
if ($debugMode -eq "true"){
  Write-Host $multiTunnelsArgs
}

if($multiTunnelsArgs -ne ""){
  $arrConnObj=@()
  $arr=$multiTunnelsArgs -split ";"
  $arr | foreach {
    if ($_ -ne ""){
      $curSubArr=$_ -Replace "^(.*)(//)(.*)$",'$3' -split ","
      if($curSubArr[0] -eq ""){
          Throw "At least an IP must be set for the tunnel $($arr.IndexOf($_)+1)"
      }
      $connObj=New-Object PSCustomObject
      if($curSubArr[0] -eq ""){
        Throw "You must provide the ip address for each tunnel!"
      }else{
        $curSubSubArr=$curSubArr[0] -split ":"
        $connObj | Add-Member -type NoteProperty -name url -Value $curSubSubArr[0]
        if($($curSubSubArr[1] -replace "[\s|\n|\r]",'') -eq "" -or $curSubSubArr[1] -eq -1){
          $connObj | Add-Member -type NoteProperty -name port -Value $defaultPort
        }else{
          $connObj | Add-Member -type NoteProperty -name port -Value $curSubSubArr[1]
        }
      }
      if($($curSubArr[1] -replace "[\s|\n|\r]",'') -eq ""){
        $connObj | Add-Member -type NoteProperty -name username -Value $defaultUsername
      }else{
        $connObj | Add-Member -type NoteProperty -name username -Value $curSubArr[1]
      }
      if($($curSubArr[2] -replace "[\s|\n|\r]",'') -eq ""){
        $connObj | Add-Member -type NoteProperty -name password -Value $defaultPassword
      }else{
        $connObj | Add-Member -type NoteProperty -name password -Value $curSubArr[2]
      }
      $arrConnObj+=$connObj
    }
  }
  $arrConnObj=$arrConnObj | sort -Descending
  if ($debugMode -eq "true"){
    Write-Host ($arrConnObj | Format-Table | Out-String)
  }
  sleep 10
  if ($($arrConnObj.Length) -lt 2){
    Throw "You must provide at least two connections in order to establish a tunnel!"
  }

  For ($i=0; $i -lt $($arrConnObj.Length-1); $i++) {
    $currConnObj=$arrConnObj[$i]
    $nextConnObj=$arrConnObj[$i+1]
    $previousTunnel=$tunnelPort
    $tunnelPort=Get-RandomPort
    write-Host "Establishing tunnel $($i+1) on local port $($tunnelPort)..." -ForegroundColor "Yellow"

    if ($previousTunnel -eq ""){
      Write-Host "$($softPath) -ssh $($currConnObj.url) -P $($currConnObj.port) -l $($currConnObj.username) -pw <$($currConnObj.url) s password> -C -T -L $($tunnelPort):$($nextConnObj.url):$($nextConnObj.port) -N"
      Start-Process -FilePath $($softPath) -ArgumentList "-ssh $($currConnObj.url) -P $($currConnObj.port) -l $($currConnObj.username) -pw $($currConnObj.password) -C -T -L $($tunnelPort):$($nextConnObj.url):$($nextConnObj.port) -N" -WindowStyle Minimized
    }else{
       Write-Host "$($softPath) -ssh localhost -P $($previousTunnel) -l $($currConnObj.username) -pw <$($currConnObj.url) s password> -C -T -L $($tunnelPort):$($nextConnObj.url):$($nextConnObj.port) -N"
      Start-Process -FilePath $($softPath) -ArgumentList "-ssh localhost -P $($previousTunnel) -l $($currConnObj.username) -pw $($currConnObj.password) -C -T -L $($tunnelPort):$($nextConnObj.url):$($nextConnObj.port) -N" -WindowStyle Minimized
    }
    sleep 10
  }
  $lastConnObj=$arrConnObj[-1]

  if($mode -eq "scp"){
    Write-Host "&$($global:currentLocation)\Set-SCP.ps1 -ip localhost -username $($lastConnObj.username) -password ******** -port $($tunnelPort)"
    &"$($global:currentLocation)\Set-SCP.ps1" -ip "localhost" -username "$($lastConnObj.username)" -password "$($lastConnObj.password)" -port "$($tunnelPort)"
    #Start-Process -FilePath $($winSCPPath) -ArgumentList "scp://$($lastConnObj.username):$($lastConnObj.password)@localhost:$($tunnelPort)" -WindowStyle Maximized
  }elseif($mode -eq "ftp"){
    Write-Host "&$($global:currentLocation)\Set-SCP.ps1 -ip localhost -username $($lastConnObj.username) -password ******** -port $($tunnelPort)" -proto "FTP"
    &"$($global:currentLocation)\Set-SCP.ps1" -ip "localhost" -username "$($lastConnObj.username)" -password "$($lastConnObj.password)" -port "$($tunnelPort)" -proto "FTP"
    #Start-Process -FilePath $($winSCPPath) -ArgumentList "scp://$($lastConnObj.username):$($lastConnObj.password)@localhost:$($tunnelPort)" -WindowStyle Maximized
  }elseif($mode -eq "vnc"){
    Write-Host "&$($global:currentLocation)\Set-VNC.ps1 -ip localhost -password ******** -port $($tunnelPort)"
    &"$($global:currentLocation)\Set-VNC.ps1" -ip "localhost" -port "$($tunnelPort)" -password "$($lastConnObj.password)"
    #Start-Process -FilePath .\Set-VNC.ps1 -ip "localhost" -port $($tunnelPort) -password "$($lastConnObj.password)" -WindowStyle Maximized
  }else{
    Write-Host "&$($global:currentLocation)\Set-SSH.ps1 -ip localhost -username $($lastConnObj.username) -password ******** -port $($tunnelPort)"
    &"$($global:currentLocation)\Set-SSH.ps1" -ip "localhost" -username "$($lastConnObj.username)" -password "$($lastConnObj.password)" -port "$($tunnelPort)"
    #Start-Process -FilePath $($puttyPath) -ArgumentList "$($specArg2) -ssh $($specArg) localhost -P $($tunnelPort) -l $($lastConnObj.username) -pw $($lastConnObj.password)" -WindowStyle Maximized
  }

}else{
  $ip1=$ip1.Replace("`r","")
  $ip2=$ip2.Replace("`r","")
  $port1=$port1.Replace("`r","")
  $port2=$port2.Replace("`r","")
  $username1=$username1.Replace("`r","")
  $username2=$username2.Replace("`r","")
  $password1=$password1.Replace("`r","")
  $password2=$password2.Replace("`r","")
  $tunnelPort=$tunnelPort.Replace("`r","")
  if($ip1 -eq ""){
      Throw "The -ip1 argument must be set"
  }
  if($ip2 -eq ""){
      Throw "The -ip2 argument must be set"
  }
  if($port1 -eq ""){
      $port1=$defaultPort
  }
  if($port2 -eq ""){
      $port2=$defaultPort
  }
  if($username1 -eq ""){
      $username1=$defaultUsername
  }
  if($password1 -eq ""){
      $password1=$defaultPassword
  }
  if($username2 -eq ""){
      $username2=$username1
  }
  if($password2 -eq ""){
      $password2=$password1
  }

  if($tunnelPort -eq "" -or $tunnelPort -eq "{S:TunnelPort}"){
      $tunnelPort=Get-RandomPort
  }

  preventSoftFailure $multipleOpeningTimeout $subSoft $soft

  write-Host "Establishing tunnel on local port $($tunnelPort)..." -ForegroundColor "Yellow"
  write-host "Starting process $($softPath) -ssh $($ip1) -P $($port1) -l $($username1) -pw <$($ip1) s password> -C -T -L $($tunnelPort):$($ip2):$($port2) -N"
  Start-Process -FilePath $($softPath) -ArgumentList "-ssh $($ip1) -P $($port1) -l $($username1) -pw $($password1) -C -T -L $($tunnelPort):$($ip2):$($port2) -N" -WindowStyle Minimized
  sleep 10

  if($mode -eq "scp"){
    &"$($global:currentLocation)\Set-SCP.ps1" -ip "localhost" -username "$($username2)" -password "$($password2)" -port "$($tunnelPort)"
    #Start-Process -FilePath $($winSCPPath) -ArgumentList "scp://$($lastConnObj.username):$($lastConnObj.password)@localhost:$($tunnelPort)" -WindowStyle Maximized
  }elseif($mode -eq "ftp"){
    &"$($global:currentLocation)\Set-SCP.ps1" -ip "localhost" -username "$($username2)" -password "$($password2)" -port "$($tunnelPort)" -proto "FTP"
  #Start-Process -FilePath $($winSCPPath) -ArgumentList "scp://$($lastConnObj.username):$($lastConnObj.password)@localhost:$($tunnelPort)" -WindowStyle Maximized
  }elseif($mode -eq "vnc"){
    &"$($global:currentLocation)\Set-VNC.ps1" -ip "localhost" -password "$($password2)" -port "$($tunnelPort)"
    #Start-Process -FilePath .\Set-VNC.ps1 -ip "localhost" -port $($tunnelPort) -password "$($lastConnObj.password)" -WindowStyle Maximized
  }else{
    &"$($global:currentLocation)\Set-SSH.ps1" -ip "localhost" -username "$($username2)" -password "$($password2)" -port "$($tunnelPort)"
    #Start-Process -FilePath $($puttyPath) -ArgumentList "$($specArg2) -ssh $($specArg) localhost -P $($tunnelPort) -l $($lastConnObj.username) -pw $($lastConnObj.password)" -WindowStyle Maximized    
  }
}

if ($debugMode -eq "true"){
  sleep 150
}