#Defalt Value
$OSDisk = 0

#Retrieve SSD
$SSD = Get-PhysicalDisk | Where MediaType -eq 'SSD'

#Multiple SSDs
if (@($SSD).count -gt 1)
{
    #multiple nvme SSD, choose the smallest one
    if (@($SSD | where bustype -like 'nvme').count -gt 1)
    {
        $OSDisk = $SSD | Sort-Object -Property Size | Select-Object -ExpandProperty DeviceID -First 1 
    }
    elseif (@($SSD | where bustype -like 'nvme').count -eq 1)
    {
        $OSDisk = ($SSD | where bustype -like 'nvme').deviceid
    }
}

#Single SSD
elseif (@($SSD).count -eq 1)
    {
    #multiple physical disks, choose SSD
    if (@(get-physicaldisk).count -gt 1)
    {
        $OSDisk = ($SSD).deviceid
    }
#single pysical disks
    else
    {
        $OSDisk = 0
    }
}

(New-Object -COMObject Microsoft.SMS.TSEnvironment).Value('OSDDiskIndex') = $OSDisk
