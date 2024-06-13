Function PRTG-CreateLogFile(){    
    $datestart = Get-Date -Format "yyyy-MM-dd"
    $global:OutputFile = "FILE_PATH_TO_STORE_OUTPUT_FILE$datestart.log"
    $datetime = Get-Date -Format "yyyy-MM-dd-HH:mm:ss"
    Write-Output "$datetime - Log File Created" | Out-File -FilePath $OutputFile -Encoding utf8
}

# Add more log output files where necessary to alert PRTG
Function PRTG-LogOutput($output){
    $datetime = Get-Date -Format "yyyy-MM-dd-HH:mm:ss"
    Write-Output "$datetime - $output" | Out-File -FilePath $global:OutputFile -Encoding utf8 -Append
}

Function PRTG-ConnectToPRTG(){     
    Connect-PrtgServer prtg.<INSERT_COMPANY_PRTG_SITE> (New-Credential al005635 1887512227) -PassHash -Force
    $PRTGClient = Get-PrtgClient
}

Function PRTG-TransferPrep {
    $devices = Get-Group "Onboarding" | Get-Device | Where-Object {($_.TotalSensors -eq 0)}
    
    # Stores non-production devices. We will skip all production devices for now.
    $nonProd = @()
    
    # Filters out non production devices
    if ($devices) {
        foreach($device in $devices) {
            if ((($device.Name).Substring(5,2) -ne "PD")){
                $nonProd += $device
            }
        }
    }
    # Calls delete duplicates function 
    PRTG-DeleteDuplicates -nonProd ($nonProd)
}

Function PRTG-DeleteDuplicates() {
    param (
        $nonProd
    )
    $map = @{} # Use hashtable for efficiency
    $uniqueDevices = @()
    $sortedDevices = $nonProd | Sort-Object -Property Name -Descending

    foreach($device in $sortedDevices) {

        # If a duplicate device is found, compare device Ids and give priority to the older device.
        if($map[$device.Name]) {
            if($device.Id -lt $map["$device"]) {
                Write-Output "Duplicate device found: $($device)"
                Write-Output "Giving priority to ID: $($device.Id)"
                $nonPriorityID = $map["$device"]
                $map[$device.Name] = $device.Id

                # Takes user-input to identify how to move forward with duplicate
                $response = Read-Host "Would you like to remove $($device.Name) with $($nonPriorityID) [Y/N]? "
                
                if ($response -eq "Y" -or $response -eq "y"){
                    # Prompts a wizard that confirms deletion
                    Get-Device -Id $nonPriorityID | Remove-Object -Confirm
                    Write-Host "Processing response..."
                    Start-Sleep -Seconds 30
                    
                    # Checks device status. If device still exists, device was not deleted, otherwise we verify deletion later
                    $checkResponse = Get-Device -Id $nonPriorityID

                    if ($checkResponse) {
                        Write-Output "Understood. We are not deleting device."
                    }
                    else {
                        Write-Output "Deleting duplicate device..."
                        Start-Sleep -Seconds 15

                        # Re-verifies device status. If device still exists, something went wrong, otherwise, device was deleted
                        $ensureDeleted = Get-Device -Id $nonPriorityID

                        if($ensureDeleted) {
                            Write-Output "We were unable to deleted the device. Please stop the program and verify deletion in PRTG"
                        }
                        else{
                            Write-Output "Device successfully deleted!"
                        }
                    }
                }
                elseif ($response -eq "N" -or $response -eq "n"){
                    Write-Output "Understood. Device will not be deleted"
                    Continue
                }
                else {
                    Write-Output "Invalid response given. Device will not be deleted"
                    Continue
                }   
            }

            # I believe that I can condense this part of the script to one if statement...
            elseif ($device.Id -gt $map["$device"]) {
                Write-Output "Duplicate device found: $($device)"
                Write-Output "Giving priority to ID: $($map["$device"])"
                $nonPriorityID = $device.Id
                $priorityId = $map["$device"]
                $map[$device.Name] = $priorityId

                # Takes user-input to identify how to move forward with duplicate
                $response = Read-Host "Would you like to remove $($device.Name) with $($nonPriorityID) [Y/N]? "
                
                if ($response -eq "Y" -or $response -eq "y"){
                    # Prompts a wizard that confirms deletion
                    Get-Device -Id $nonPriorityID | Remove-Object -Confirm
                    Write-Host "Processing response..."
                    Start-Sleep -Seconds 30
                    
                    # Checks device status. If device still exists, device was not deleted, otherwise we verify deletion later
                    $checkResponse = Get-Device -Id $nonPriorityID

                    if ($checkResponse) {
                        Write-Output "Understood. We are not deleting device."
                    }
                    else {
                        Write-Output "Deleting duplicate device..."
                        Start-Sleep -Seconds 15

                        # Re-verifies device status. If device still exists, something went wrong, otherwise, device was deleted
                        $ensureDeleted = Get-Device -Id $nonPriorityID

                        if($ensureDeleted) {
                            Write-Output "We were unable to deleted the device. Please stop the program and verify deletion in PRTG"
                        }
                        else{
                            Write-Output "Device successfully deleted!"
                        }
                    }
                }
                elseif ($response -eq "N" -or $response -eq "n"){
                    Write-Output "Understood. Device will not be deleted"
                    Continue
                }
                else {
                    Write-Output "Invalid response given. Device will not be deleted"
                    Continue
                }
            }

            # If we make it here, something went wrong.
            else {
                Write-Output "Uh oh, Spaghettio's! Devices have the same ID. Verify that the devices do not contain the same ID. Exiting program..."
                Break
            }
        }

        # No duplicate was found, so we add the device to our table normally.
        else {
            $map.Add($device.Name, $device.Id)
        }
    }

    foreach($device in $map.Keys){
        $uniqueDevices += $device
    }

    # Calls clearance check function 
    PRTG-ClearanceCheck -uniqueDevices ($uniqueDevices)

}

Function PRTG-ClearanceCheck() {
    param (
        $uniqueDevices
    )

    $secureDevices = @()
    $unsecureDevices = @()
    
    if($uniqueDevices) {
        foreach($device in $uniqueDevices) {

            if($device.Substring(0,2) -eq "*W"){
                $ping_result = Test-Connection $device -Count 1 -ErrorAction SilentlyContinue
                
                if ($ping_result) {
                    Write-Host "Checking priviledges for $($device)..."

                    # Calls valid communities function
                    $result = PRTG-RetreiveValidCommunities -device ($device)
                    Write-Host "Result is... $($result)"
                    
                    if($result) {
                        #Write-Host ($result)
                        Write-Host "Adding $($device) to secureDevices..."
                        $secureDevices += $device
                    }

                    else {
                        Write-Host "Necessary priviledges not found for $($device)"
                        Write-Host "Adding $($device) to unsecureDevices..."
                        $unsecureDevices += $device
                        # Type "$unsecureDevices" variable in terminal to see list of unsecure devices.
                    }
                }
                # Catch errors statements:

                elseif ($stoperror -like "The client cannot connect to the destination specified in the request." -or $stoperror -like "WinRM cannot complete the operation.")  {
                    Write-Host $stoperror
                    Write-Host "We were not able to connect to $($device)"
                }
                else {
                    Write-Host "Unexpected error found when connecting to $($device)"
                }
            } # Catch linux statement:
            elseif ($device.Substring(0,2) -eq "*L"){
                Write-Host "$($device) is a linux machine. We will go ahead and add this to secureDevices."
                $secureDevices += $device # This will catch all linux devices that we cannot ping.
            }
            # Empty list
            else {
                Write-Host "No devices found"
            }
        }
    }
    # Empty list
    else {
        Write-Host "No devices found in onboarding group"
    }

    if ($secureDevices) {
        Write-Host "Here is a list of devices ready to assign templates: $($secureDevices)"
        $response = Read-Host "Would you like to proceed with autodiscovery process [Y/N]? "
        
        if ($response -eq "Y" -or $response -eq "y"){
            Write-Host "Starting autodiscovery process"

            # Calls assign template function 
            PRTG-AssignTemplate -secureDevices $secureDevices
            Write-Host "Autodiscover process complete!"
        }
        elseif ($respone -eq "N" -or $response -eq "n") {
            Write-Host "Understood. Continuing program..."
        }
        else {
            Write-Host "Invalid reponse. Exiting program..."
            Break
        }
    }
    else {
        Write-Host "No secure devices found"
    }

    if ($unsecureDevices) {
        $response = Read-Host "Unsecure devices were found. Would you like to see the list of devices? [Y/N]? "

        if ($response -eq "Y" -or $response -eq "y") {
            Write-Host "List of unsecure devices: $($unsecureDevices)"
        }
        elseif($respone -eq "N" -or $response -eq "n") {
            Write-Host "Understood. Continuing program..."
        }

        else {
            Write-Host "Invalid reponse. Exiting program..."
            Break
        }
    }
    else {
        Write-Host "No unsecure devices found"
    }
}

Function PRTG-RetreiveValidCommunities {
    param (
        $device
    )
    # Retreive's ValidCommunities  
    $query = Invoke-Command -ComputerName $device -ScriptBlock {Get-ItemProperty -Path Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\services\SNMP\Parameters\ValidCommunities}
    
    # Formatting Begin ====================================================
    
    $queryToString= [string]$query
    $array = @()

    foreach($item in $queryToString) {
        $array += $item
    }

    $split_elements = $array -split ';'
    $new_array = @()

    foreach($element in $split_elements) {
        $new_array += $element    
    }

    $new_array = $new_array -replace '@{', '' -replace '}','' -replace ' ', ''
    
    # Formatting End ======================================================

    # Searching for device clearance...
    for($i = 0; $i -le $new_array.Length -1; $i++) {
        if ($new_array[$i] -eq "g6TS^YuXY3wx6snb^o2V=4") {
            $result = "$($device) has valid clearance"
            return $result
        }
        else {
            Continue
        }
    }
}

Function PRTG-AssignTemplate {
    param (
        $secureDevices
    )
    $winTemplate = Get-DeviceTemplate "Server - WIN"
    $linTemplate = Get-DeviceTemplate "Linux Server" 

    # Assigns templates to secureDevices
    if($secureDevices) {
        foreach($device in $secureDevices) {
            if($device.Substring(0,2) -eq "*W") {
                Write-Host "Adding Windows Template to $($device)..."
                #PRTG-LogOutput("Adding Windows Template to $($device)")
                Get-Device -Name $($device) | Start-AutoDiscovery $winTemplate
                Write-Host "Sleeping..."
                Start-Sleep -Seconds 120 # 3 mins and 30 secs
                Write-Host "Awake!!!"
            }
            elseif($device.Substring(0,2) -eq "*L") {
                Write-Host "Adding Linux Template to $($device)..."
                #PRTG-LogOutput("Adding Linux Template to $($device)")
                Get-Device -Name $($device) | Start-AutoDiscovery $linTemplate
                Write-Host "Sleeping..."
                Start-Sleep -Seconds 210 # 3 mins and 30 secs
                Write-Host "Awake!!!"
            }
            else {
                #PRTG-LogOutput("$($device) is neither a Windows or Linux machine. We will not give template for now.")
                Write-Host "$($device) is neither a windows or linux machine. We will skip this one for now."
            }
        }
    }
    else {
        Write-Host "No devices received an auto-discovery template"
    }
}

Function PRTG-TransferOnboarding() {
    $devicesList = @()
    $devicesList = Get-Group Onboarding | Get-Device | Where-Object {($_.TotalSensors -gt 1)} # 5/6 being the amt for win template
    $devicesToMove = @()

    if ($devicesList) {
        foreach($device in $devicesList) {
            if ((($device.Name).Substring(5,2) -ne "PD")){
                $devicesToMove += $device
            }
        }
    }
    else {
        Write-Host "There are no devices no move."
    }

    if($devicesToMove) {
        foreach($device in $devicesToMove) {
            if (($device.Name).Substring(0,2) -eq "*W") {
                #PRTG-LogOutput("Moving $($device.Name) to Server-Windows group")
                Write-Host "Moving $($device) to Server-Windows group"
                Get-Device -Name $($device.Name) | Move-Object -DestinationId 237456
                Write-Host "Sleeping..."
                Start-Sleep -Seconds 60
                Write-Host "Awake!!!"
            }
            elseif (($device.Name).Substring(0,2) -eq "*L") {
                #PRTG-LogOutput("Moving $($device.Name) to Server-Linux group")
                Write-Host "Moving $($device.Name) to Server-Linux group"
                Get-Device -Name $($device.Name) | Move-Object -DestinationId 237457
                Write-Host "Sleeping..."
                Start-Sleep -Seconds 120
                Write-Host "Awake!!!"
            }
            else {
                #PRTG-LogOutput("$($device.Name) is neither a Windows or Linux machine. We will keep it in Onboarding for now.")
                Write-Host "$($device.Name) is not a dev device. We will keep in in Onboarding for now."
                #Write-Host "$($device.Name) is neither a Windows or Linux machine. We will keep it in Onboarding for now."
            }
        }
    }
    else {
        Write-Host "Zero Onboarding devices have been moved."
    }
}

# Run this code to prepare devices in onboarding group for transfer
PRTG-TransferPrep

# Run this program to commit actual transfer of devices to respective OS server groups
#PRTG-TransferOnboarding