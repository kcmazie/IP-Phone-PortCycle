# IP-Phone-PortCycle
WIll perform a shut/no shut on Cisco switchports where IP phones are detected

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
