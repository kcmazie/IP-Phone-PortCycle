Param(
    [switch]$Console = $false,         #--[ Set to true to enable local console result display. Defaults to false ]--
    [switch]$Debug = $False            #--[ Generates extra console output for debugging.  Defaults to false ]--
    )
<#==============================================================================
         File Name : IP-Phone-PortCycle.ps1
   Original Author : Kenneth C. Mazie (kcmjr AT kcmjr.com)
                   : 
       Description : Script will injest a flat text file (IPList.txt) in the script folder containing the IP
                   : addresses of Cisco network switches, one per line.  It uses either stored or entered 
                   : credentials to access the switch console.  It then sends a "sh cdp neighbors" command 
                   : filtered to return only Cisco VoIP phones who's names start with SEP.  The returned list 
                   : is parsed, filtered and then each device switchport is identified.  Commands are then 
                   : sent to enter enable mode, select the appropriate port, shut it off, the turn it on.  
                   : The effect is to force the connected phone to reset and request a new DHCP address.
                   : 
             Notes : Normal operation is with no command line options.  If pre-stored credentials 
                   : are desired use this: https://github.com/kcmazie/CredentialsWithKey.
                   : Because the port list is derived from a returned list containing "SEP" only those ports
                   : get cycled.  The script is designed to cycle Cisco phones but can easily be retooled
                   : to detect and cycle ports for other things.
                   :
      Requirements : Requires the Posh-SSH module from the PowerShell gallery.  Script installs it if
                   : not found.  Otherwise https://www.powershellgallery.com/packages/Posh-SSH
                   : 
   Option Switches : See descriptions above.
                   :
          Warnings : Yes Virginia, this will interrupt users...
                   :   
             Legal : Public Domain. Modify and redistribute freely. No rights reserved.
                   : SCRIPT PROVIDED "AS IS" WITHOUT WARRANTIES OR GUARANTEES OF 
                   : ANY KIND. USE AT YOUR OWN RISK. NO TECHNICAL SUPPORT PROVIDED.
                   : That being said, feel free to ask if you have questions...
                   :
           Credits : Code snippets and/or ideas came from many sources including...
                   : https://stackoverflow.com/questions/71760114/posh-ssh-script-on-cisco-devices
                   : https://www.powershellgallery.com/packages/Invoke-CiscoCommand/1.1/Content/Invoke-CiscoCommand.ps1
                   : 
    Last Update by : Kenneth C. Mazie                                           
   Version History : v1.00 - 05-10-24 - Original release
    Change History : v1.10 - 00-00-00 - 
                   : 
==============================================================================#>
Clear-Host
#Requires -version 5

#--[ Variables ]---------------------------------------------------------------
$DateTime = Get-Date -Format MM-dd-yyyy_HHmmss 
$Today = Get-Date -Format MM-dd-yyyy 

#==[ RUNTIME TESTING OPTION VARIATIONS ]========================================
$Console = $true
$Debug = $True       #--[ DEBUG IS ENABLED TO AVOID YOU GETTING FIRED.  DISABLE TO RUN ]--

If($Debug){
    $Console = $true
}
#==============================================================================

if (!(Get-Module -Name posh-ssh*)) {    
    Try{  
        import-module -name posh-ssh
    }Catch{
        Write-host "-- Error loading Posh-SSH module." -ForegroundColor Red
        Write-host "Error: " $_.Error.Message  -ForegroundColor Red
        Write-host "Exception: " $_.Exception.Message  -ForegroundColor Red
    }
}

#==[ Functions ]===============================================================
Function LoadConfig ($Config, $ExtOption){
    If ($Config -ne "failed"){
        $ExtOption | Add-Member -Force -MemberType NoteProperty -Name "Domain" -Value $Config.Settings.General.Domain        
        $ExtOption | Add-Member -Force -MemberType NoteProperty -Name "CredDrive" -Value $Config.Settings.Credentials.CredDrive
        $ExtOption | Add-Member -Force -MemberType NoteProperty -Name "PasswordFile" -Value $Config.Settings.Credentials.PasswordFile
        $ExtOption | Add-Member -Force -MemberType NoteProperty -Name "KeyFile" -Value $Config.Settings.Credentials.KeyFile
    }Else{
        StatusMsg "MISSING XML CONFIG FILE.  File is required.  Script aborted..." " Red" $True
        $Message = (
'--[ External XML config file example ]-----------------------------------
--[ To be named the same as the script and located in the same folder as the script ]--
--[ Email settings in example are for future use.                                   ]--

<?xml version="1.0" encoding="utf-8"?>
<Settings>
    <General>
        <SmtpServer>mailserver.company.org</SmtpServer>
        <SmtpPort>25</SmtpPort>
        <RecipientEmail>InformationTechnology@company.org</RecipientEmail>
        <Domain>company.org</Domain>
    </General>
    <Credentials>
  		<CredDrive>c:</CredDrive>
        <PasswordFile>Pass.txt</PasswordFile>
        <KeyFile>Key.txt</KeyFile>
    </Credentials>    
    <Recipients>
        <Recipient>me@company.org</Recipient>
        <Recipient>you@company.org</Recipient>
        <Recipient>them@company.org</Recipient>
    </Recipients>
</Settings> ')
Write-host $Message -ForegroundColor Yellow
    }
    Return $ExtOption
}

Function StatusMsg ($Msg, $Color, $ExtOption){
    If ($ExtOption.Console){
        Write-Host "-- Script Status: $Msg" -ForegroundColor $Color
    }
}

#=[ End of Functions ]========================================================

#=[ Begin Processing ]========================================================
#--[ Load external XML options file ]------------------------------------------------
$ExtOption = New-Object -TypeName psobject 
If ($Console){
    $ExtOption | Add-Member -Force -MemberType NoteProperty -Name "Console" -Value $True 
}
If ($Debug){
    $ExtOption | Add-Member -Force -MemberType NoteProperty -Name "Debug" -Value $True 
    StatusMsg " -- DEBUG MODE.  No actual resets will be performed --" "Red" $ExtOption
    StatusMsg " -- DEBUG MODE.  Commands will be echoed within --[ ]--" "Red" $ExtOption
}

$ConfigFile = $PSScriptRoot+"\"+($MyInvocation.MyCommand.Name.Split("_")[0]).Split(".")[0]+".xml"
If (Test-Path $ConfigFile){                          #--[ Error out if configuration file doesn't exist ]--
    StatusMsg "Reading XML config file..." "Magenta" $ExtOption    
    [xml]$Config = Get-Content $ConfigFile           #--[ Read & Load XML ]--  
    $ExtOption = LoadConfig $Config $ExtOption
}Else{
    LoadConfig "failed"
    StatusMsg "MISSING XML CONFIG FILE.  File is required.  Script aborted..." " Red" 
    break;break;break
}

#--[ Prepare Credentials ]--
$UN = $Env:USERNAME
$DN = $Env:USERDOMAIN
$UID = $DN+"\"+$UN

#--[ Test location of encrypted files, remote or local ]--
If ($Null -eq $ExtOption.PasswordFile){
    $Credential = Get-Credential -Message 'Enter an appropriate Domain\User and Password to continue.'
    $ExtOption | Add-Member -Force -MemberType NoteProperty -Name "Credential" -Value $Credential
}Else{
    If (Test-Path -path ($ExtOption.CredDrive+'\'+$ExtOption.PasswordFile)){
        $PF = ($ExtOption.CredDrive+'\'+$ExtOption.PasswordFile)
        $KF= ($ExtOption.CredDrive+'\'+$ExtOption.KeyFile)
    }Else{
        $PF = ($PSScriptRoot+'\'+$ExtOption.PasswordFile)
        $KF = ($PSScriptRoot+'\'+$ExtOption.KeyFile)
    }
    $Base64String = (Get-Content $KF)
    $ByteArray = [System.Convert]::FromBase64String($Base64String)
    $Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $UID, (Get-Content $PF | ConvertTo-SecureString -Key $ByteArray)
    $ExtOption | Add-Member -Force -MemberType NoteProperty -Name "Credential" -Value $Credential
}

StatusMsg "Processing Cisco Switches " "Yellow" $ExtOption
$ListFileName = "$PSScriptRoot\IPlist.txt"
$IPList  = @()
If (Test-Path -Path $ListFileName){  #--[ Verify that a text file exists and pull IP's from it then create a new spreadsheet. ]--
    $IPList = Get-Content $ListFileName  
    StatusMsg "IP text file was found, loading IP list from it..." "green" $ExtOption
}Else{
    Write-host "-- No IP list found...  Aborting." -ForegroundColor Red
    Break;Break;Break
}

#--[ Begin Processing of IP List ]--------------------------------------------
$ErrorActionPreference = "stop"
#--[ NOTE: If a line in the text file starts with "#," that line is ignored ]--
ForEach ($Line in $IPList | Where-Object {$_ -NotLike "#"}){
    $IP = ($Line.Split(";")[0]) 
    StatusMsg "Current Switch: [$IP]" "cyan" $ExtOption

    #--[ Test network connection.  Column 1 (A) ]----------------------------------------------
    If (Test-Connection -ComputerName $IP -count 1 -BufferSize 16 -Quiet){
        $Connection = $True
    }Else{
        Start-Sleep -Seconds 2
            If (Test-Connection -ComputerName $IP -count 1 -BufferSize 16 -Quiet){
                $Connection = $True
            }Else{
                StatusMsg "--- No Connection ---" "Red" $ExtOption
            }
    }

    If ($Connection){
        Get-SSHSession | Select-Object SessionId | Remove-SSHSession | Out-Null  #--[ Remove any existing sessions ]--
        New-SSHSession -ComputerName $IP -AcceptKey -Credential $Credential | Out-Null
        $Session = Get-SSHSession -Index 0 
        $Stream = $Session.Session.CreateShellStream("dumb", 0, 0, 0, 0, 1000)
        $Stream.Write("terminal Length 0`n")
        Start-Sleep -Milliseconds 60
        $Stream.Read() | Out-Null
        $Command = 'sh cdp n | i SEP'
        $Stream.Write("$Command`n")
        $ResponseRaw = $Stream.Read()
        $Response = $ResponseRaw -split "`r`n" | ForEach-Object{$_.trim()}
        while (($Response[$Response.Count -1]) -notlike "*#") {
            Start-Sleep -Milliseconds 60
            $ResponseRaw = $Stream.Read()
            $Response = $ResponseRaw -split "`r`n" | ForEach-Object{$_.trim()}
        }

        ForEach ($Line in $Response){
            If (($Line -like "*SEP*") -and ($Line -like "*Phone*")){
                StatusMsg "--[ Detected device details = $Line ]--" "cyan" $ExtOption
                $Phone = $Line.Split(" ")[0] 
                $Port = "Gi"+$Line.Split(" ")[3]
                $CommandList = "config t;int $Port;shut;no shut;exit" 
                $Msg = "Cycling device "+$Phone+" on port "+$Port 
                StatusMsg $Msg "Yellow" $ExtOption
                Foreach ($Command in $CommandList.Split(";")){
                    If ($ExtOption.Debug){
                        StatusMsg "--[ $Command ]--" "Cyan" $ExtOption
                    }Else{
                        $SSHStream.WriteLine(('{0}' -f $Command))
                    }
                    Start-Sleep -Milliseconds 200
                }
            }
        }
    }Else{
        StatusMsg "--- No Connection ---" "Red" $ExtOption
    }
    StatusMsg "Clearing run variables." "magenta" $ExtOption
    Remove-variable Response -ErrorAction "SilentlyContinue" 
    StatusMsg "End of Switch $IP" "magenta" $ExtOption
}

Write-Host ""
StatusMsg "--- COMPLETED ---" "red" $ExtOption
 
