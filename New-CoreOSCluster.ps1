Function New-CoreOSCluster 
{
<#   
    .SYNOPSIS   
        Deploys a CoreOS cluster using specified configurations
    .DESCRIPTION 
        A script to build and maintain a CoreOS cluster
        - Builds any machines that don't exist
        - Stops and updates machine .vmx file as necessary
        - Waits for machine to start before taking down and updating next node
    .PARAMETER VMList
        Specifiies array of VMs to deploy
    .PARAMETER CIDR
        Specifies array of IPs to use
    .PARAMETER Gateway
        Specifies IP of Gateway 
    .PARAMETER DNS
        Specifies IP of DNS server
    .PARAMETER CloudConfig
        Specifies location of cloud-config.yml file
    .PARAMETER vCenter
        Specifies IP or FQDN of vCenter server
    .PARAMETER Template
        Specify name of CoreOS Template
    .PARAMETER VMHost
        Specify name of VMHost where VM(s) will be deployed
    .PARAMETER Cluster
        Specify name of Cluster where VM(s) will be deployed
    .PARAMETER Datastore
        Specify name of Datastore where VM(s) will be deployed
    .PARAMETER DatastoreCluster
        Specify name of Datastore Cluster where VM(s) will be deployed
    .PARAMETER Credential
        Specify credentials use to connect to vCenter
    .NOTES   
        Name: New-CoreOSCluster
        Author: Chris Arceneaux <carceneaux@thinksis.com>
        Credits: Robert Labrie <robert.labrie@gmail.com>, LucD <lucd@lucd.info>                
    .LINK
        https://coreos.com/os/docs/latest/booting-on-vmware.html
        https://github.com/robertlabrie/vmware_coreos
        http://www.lucd.info/2010/02/21/about-async-tasks-the-get-task-cmdlet-and-a-hash-table/
    .EXAMPLE   
        New-CoreOSCluster -VMList "coreos01" -CIDR "192.168.1.180/24" -Gateway 192.168.1.1 -DNS 192.168.1.4 -CloudConfig "cloud-config.yml" -vCenter "vc-mgmt.dc.local" -Template "coreos" -Cluster "ClusterName" -DatastoreCluster "DsClusterName" -Credential $cred

    Description 
    -----------     
    Creates/Updates the VM "coreos01" with the specified networking information using a VMware Cluster and Datastore Cluster and "cloud-config.yml"
    .EXAMPLE   
        New-CoreOSCluster -VMList "coreos01","coreos02" -CIDR "192.168.1.180/24","192.168.1.181/24" -Gateway 192.168.1.1 -DNS 192.168.1.4 -CloudConfig "cloud-configX2.yml" -vCenter "vc.dc.local" -Template "coreos" -VMHost "esxi.dc.local" -Datastore "DsName"

    Description 
    -----------     
    Creates/Updates the VM "coreos01","coreos02" with the specified networking information using a VMware Host and Datastore and "cloud-configX2.yml"
    As no Credentials was specified, Windows credentials will used to connect to vCenter and if they're insufficient, PowerShell will prompt
    for a Username/Password.    
#>
    [CmdletBinding()]
	[OutputType([String])]

    # Specifies parameters required for the PowerShell session.
	Param
    (
        # Array of VMs to deploy
        [Parameter(Mandatory=$true, 
        ValueFromPipeline=$true,
        ValueFromPipelineByPropertyName=$true, 
        ValueFromRemainingArguments=$false, 
        Position=0)] 
        [string[]]$VMList,

        # Array of IPs to use
        [Parameter(Mandatory=$true, 
        ValueFromPipeline=$true,
        ValueFromPipelineByPropertyName=$true, 
        ValueFromRemainingArguments=$false, 
        Position=1)] 
        [string[]]$CIDR,

        # IP of Gateway
        [Parameter(Mandatory=$true, 
        ValueFromPipeline=$true,
        ValueFromPipelineByPropertyName=$true, 
        ValueFromRemainingArguments=$false, 
        Position=2)]
        [string]$Gateway,

        # IP of DNS server
        [Parameter(Mandatory=$true, 
        ValueFromPipeline=$true,
        ValueFromPipelineByPropertyName=$true, 
        ValueFromRemainingArguments=$false, 
        Position=3)]
        [string]$DNS,
        
        # Location of cloud-config.yml file
        [Parameter(Mandatory=$false, 
        ValueFromPipeline=$true,
        ValueFromPipelineByPropertyName=$true, 
        ValueFromRemainingArguments=$false, 
        Position=4)] 
        [string]$CloudConfig,

        # IP or FQDN of vCenter server
        [Parameter(Mandatory=$true, 
        ValueFromPipeline=$true,
        ValueFromPipelineByPropertyName=$true, 
        ValueFromRemainingArguments=$false, 
        Position=5)] 
        [string]$vCenter,
        
        # Name of CoreOS Template
        [Parameter(Mandatory=$true, 
        ValueFromPipeline=$true,
        ValueFromPipelineByPropertyName=$true, 
        ValueFromRemainingArguments=$false, 
        Position=6)] 
        [string]$Template,

        # Name of VMHost where VM(s) will be deployed
        [Parameter(Mandatory=$false, 
        ValueFromPipeline=$true,
        ValueFromPipelineByPropertyName=$true, 
        ValueFromRemainingArguments=$false, 
        Position=7)] 
        [string]$VMHost,
        
        # Name of Cluster where VM(s) will be deployed
        [Parameter(Mandatory=$false, 
        ValueFromPipeline=$true,
        ValueFromPipelineByPropertyName=$true, 
        ValueFromRemainingArguments=$false, 
        Position=7)] 
        [string]$Cluster,
        
        # Name of Datastore where VM(s) will be deployed
        [Parameter(Mandatory=$false, 
        ValueFromPipeline=$true,
        ValueFromPipelineByPropertyName=$true, 
        ValueFromRemainingArguments=$false, 
        Position=8)]
        [string]$Datastore,
        
        # Name of Datastore Cluster where VM(s) will be deployed
        [Parameter(Mandatory=$false, 
        ValueFromPipeline=$true,
        ValueFromPipelineByPropertyName=$true, 
        ValueFromRemainingArguments=$false, 
        Position=8)]
        [string]$DatastoreCluster,

        # Credential to Run
        [Parameter(Mandatory=$false, 
        ValueFromPipeline=$true,
        ValueFromPipelineByPropertyName=$true, 
        ValueFromRemainingArguments=$false, 
        Position=9)] 
        [System.Management.Automation.PSCredential]$Credential
    )

    Begin
	{
		# Validating parameters
        Write-Verbose "Validating parameters"
        if (!$VMHost -and !$Cluster) {Write-Error "You must specify a VMHost or Cluster where the VM(s) can be deployed.";Exit}
        if (!$Datastore -and !$DatastoreCluster) {Write-Error "You must specify a Datastore or DatastoreCluster where the VM(s) can be deployed.";Exit}
        if ($VMList.count -ne $CIDR.count) {Write-Error "You must specify the same number of VMs and IPs.";Exit}
        
        # Loading VMWare snapin and connecting to vCenter
        Write-Verbose "Loading VMWare snapin and connecting to vCenter"
        Add-PSSnapin VMware.VimAutomation.Core | Out-Null
        
        # Connecting to vCenter
        Try
        {
            if (!($global:DefaultVIServers.Count))
            {
                if ($Credential) {Connect-VIServer $vCenter -Credential $Credential -ErrorAction "Stop" | Out-Null}
                else {Connect-VIServer $vCenter -ErrorAction "Stop" | Out-Null}
            }
        }
        Catch
        {
            Write-Error "Unable to connect to vCenter. Please make sure that you have specified the correct vCenter and the credentials used have access to vCenter."
			$ErrorMessage = $_.Exception.Message
			$FailedItem = $_.Exception.ItemName
			Write-Verbose $($ErrorMessage | Out-String)
			Write-Verbose $($FailedItem | Out-String)
            Exit
        }               
        Write-Verbose "Connected to vCenter successfully"
        
        # Validating VMware infrastructure
        Write-Verbose "Making sure VMware infrastructure exists"
        Try
        {
            Write-Verbose "Checking Template"
            $vmtemplate = Get-Template -Name $Template -ErrorAction "Stop"
            Write-Verbose "Checking VMHost if needed"
            if ($VMHost) {Get-VMHost -Name $VMHost -ErrorAction "Stop" | Out-Null}
            Write-Verbose "Checking Cluster if needed"
            if ($Cluster) {Get-Cluster -Name $Cluster -ErrorAction "Stop" | Out-Null}
            Write-Verbose "Checking Datastore if needed"
            if ($Datastore) {$vmdatastore = Get-Datastore -Name $Datastore -ErrorAction "Stop"}
            Write-Verbose "Checking VMHost if needed"
            if ($DatastoreCluster) {$vmdatastore = Get-DatastoreCluster -Name $DatastoreCluster -ErrorAction "Stop"}
        }
        Catch
        {
            Write-Error "Incorrect or Non-Existent VMware variable provided. Please specify the correct VMHost, Cluster, Datastore, or DatastoreCluster."
            $ErrorMessage = $_.Exception.Message
			$FailedItem = $_.Exception.ItemName
			Write-Verbose $($ErrorMessage | Out-String)
			Write-Verbose $($FailedItem | Out-String)
            Exit
        }
    }
    Process
    {
        # Setting VM specific information
        Write-Verbose "Setting VM specific information"
        Try
        {
            # Setting counter
            $vmcount = $VMList.count - 1   #adjusting count for proper array value
            Write-Verbose "Count: $vmcount"
            
            # Initializing hash table
            $vminfo = @{}
            
            # Loop to create table of machine specific information
            while ($vmcount -ne -1)
            {
                $vminfo[$VMList[$vmcount]] = @{'interface.0.ip.0.address'=$CIDR[$vmcount]}
                $vmcount--
                Write-Verbose "Count: $vmcount"
            }
            
            # Hashmap of properties common for all machines
            $gProps = @{
                'dns.server.0'=$DNS;
                'interface.0.route.0.gateway'=$Gateway;
                'interface.0.route.0.destination'='0.0.0.0/0';
                'interface.0.name' = 'ens192'; 
                'interface.0.role'='private';
                'interface.0.dhcp'='no';}
        }
        Catch
        {
            Write-Error "Error while parsing VM specific information."
            $ErrorMessage = $_.Exception.Message
			$FailedItem = $_.Exception.ItemName
			Write-Verbose $($ErrorMessage | Out-String)
			Write-Verbose $($FailedItem | Out-String)
            Exit
        }
        
        # Packing cloud-config.yml
        if (Test-Path $CloudConfig)
        {
            Write-Verbose "Converting cloud-config.yml..."
            $cc = Get-Content $CloudConfig -raw
            $b = [System.Text.Encoding]::UTF8.GetBytes($cc)
            $gProps['coreos.config.data'] = [System.Convert]::ToBase64String($b)
            $gProps['coreos.config.data.encoding'] = 'base64'
        }
        
        # Creating VMs and waiting till they've been deployed
        Write-Verbose "Creating VM(s) and waiting till they've been deployed"
        Try
        {
            # Create all the VMs specified in $VMList
            $taskTab = @{}
            foreach($vmname in $VMList)
            {
                if (get-vm | Where-Object {$_.Name -eq $vmname }) { continue }
                Write-Verbose "creating $vmname"
                # Logic to determine if VM is being deploy to a VMHost or a Cluster
                if ($VMHost) {$taskTab[(New-VM -Template $vmtemplate -Name $vmname -VMHost $VMHost -Datastore $vmdatastore.Name -RunAsync -ErrorAction "Stop").Id] = $vmname}
                else {$taskTab[(New-VM -Template $vmtemplate -Name $vmname -ResourcePool $Cluster -Datastore $vmdatastore.Name -RunAsync -ErrorAction "Stop").Id] = $vmname}
            }
            
            # Start each VM that is completed
            $runningTasks = $taskTab.Count
            while($runningTasks -gt 0){
            Get-Task | % {
                if($taskTab.ContainsKey($_.Id) -and $_.State -eq "Success"){
                $taskTab.Remove($_.Id)
                $runningTasks--
                }
                elseif($taskTab.ContainsKey($_.Id) -and $_.State -eq "Error"){
                $taskTab.Remove($_.Id)
                $runningTasks--
                }
            }
            Start-Sleep -Seconds 15
            }
        }
        Catch
        {
            Write-Error "VMs did not deploy properly."
            $ErrorMessage = $_.Exception.Message
			$FailedItem = $_.Exception.ItemName
			Write-Verbose $($ErrorMessage | Out-String)
			Write-Verbose $($FailedItem | Out-String)
            Exit
        }
    
        # Modifying VM VMX file
        Write-Verbose "Modifying VM VMX files"
        Try
        {
            # Setup and send the config
            foreach ($vmname in $VMList)
            {
                $vmxLocal = "$($ENV:TEMP)\$($vmname).vmx"
                Write-Verbose "Location of Local VMX file: $vmxLocal"
                $vm = Get-VM -Name $vmname -ErrorAction "Stop"
                
                # Power off VM if running
                Write-Verbose "Powering off VM: $vmname if running"
                if ($vm.PowerState -eq "PoweredOn") {$vm | Stop-VM -Confirm:$false | Out-Null}

                # Fetch the VMX file
                $vmxDatastore = $vm | Get-Datastore                
                Write-Verbose "Datastore: $vmxDatastore"
                $vmxRemote = "$($vmxDatastore.name):\$($vmname)\$($vmname).vmx"
                Write-Verbose "Location of Remote VMX file: $vmxRemote"
                if (Get-PSDrive | Where-Object { $_.Name -eq $vmxDatastore.Name}) { Remove-PSDrive -Name $vmxDatastore.Name }
                $null = New-PSDrive -Location $vmxDatastore -Name $vmxDatastore.Name -PSProvider VimDatastore -Root "\"
                Copy-DatastoreItem -Item $vmxRemote -Destination $vmxLocal
                
                # Strip out any existing guestinfo
                Write-Verbose "Removing old VMX info"
                $vmx = ((Get-Content $vmxLocal | Select-String -Pattern guestinfo -NotMatch) -join "`n").Trim()
                $vmx = "$($vmx)`n"

                # Build the property bag
                $props = $gProps
                $props['hostname'] = $vmname
                $vminfo[$vmname].Keys | ForEach-Object {
                    $props[$_] = $vminfo[$vmname][$_]
                }

                # Adding to the VMX
                Write-Verbose "Adding new VMX info"
                $props.Keys | ForEach-Object {
                    $vmx = "$($vmx)guestinfo.$($_) = ""$($props[$_])""`n" 
                }

                # Writing change to local VMX
                $vmx | Out-File $vmxLocal -Encoding ascii

                # Overwrite the remote VMX with the local VMX
                Write-Verbose "Overwriting old VMX file"
                Copy-DatastoreItem -Item $vmxLocal -Destination $vmxRemote

                # Start the VM
                Write-Verbose "Starting VM: $vmname"
                $vm | Start-VM | Out-Null
                $status = "toolsNotRunning"
                while ($status -eq "toolsNotRunning")
                {
                    Start-Sleep -Seconds 1
                    $status = (Get-VM -name $vmname | Get-View).Guest.ToolsStatus
                }
            }
        }
        Catch
        {
            Write-Error "Error while editing the VMX files"
            $ErrorMessage = $_.Exception.Message
			$FailedItem = $_.Exception.ItemName
			Write-Verbose $($ErrorMessage | Out-String)
			Write-Verbose $($FailedItem | Out-String)
            Exit
        }
    }
    End
    {
        Write-Verbose "Disconnecting from vCenter"
        Disconnect-VIServer * -Confirm:$false
        
        Clear-Host
        Write-Host "All CoreOS VMs have been deployed/updated successfully."
    }
}