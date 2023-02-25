#Docs for powershell module at https://github.com/snazy2000/SnipeitPS/tree/master/SnipeitPS/Public
#Script auto creates manufacturer, model, and asset, and updates any existing assets with new DNS name
#If nothing has been updated within 30 days script will do a gratuitous check-in to mark that asset is still alive
#Maintainer gfoulk88@gmail.com

#Define your server url and api key, manage your api key at $url/account/api

$apikey = "verylongkeyhere"
$url = "https://snipeit.yourfqdn.com"

#type conversion to utilize api key

$secureString = ConvertTo-SecureString $apikey -AsPlainText -Force

Connect-SnipeitPS -URL $url -secureApiKey $secureString

#Lookup service tag from BIOS using wmi method
 
$assetTag = (Get-WmiObject win32_bios).SerialNumber


#Lookup DNS name, model, and manufacturer 
$computerName = $env:COMPUTERNAME
$modelno = (Get-WmiObject -class Win32_ComputerSystem).Model
$manufacturer = (Get-WmiObject -class Win32_ComputerSystem).Manufacturer

#Get memory - not implemented feel free to comment out or add custom field to your snipeit install to insert to
$cs = (Get-WmiObject -class Win32_ComputerSystem).TotalPhysicalMemory
$memoryAmount = [math]::Ceiling($cs / 1024 / 1024 / 1024)

#Get processor family - not implemented feel free to comment out or add custom field to your snipeit install to insert to
$cpu = (Get-WmiObject Win32_Processor).Name
if ($cpu -like "*i5*"){
    $cpuType = "i5"
}
elseif ($cpu -like "*i7*"){
    $cpuType = "i7"
}
elseif ($cpu -like "*i3*"){
	$cpuType = "i3"
} else {
    $cputype = $cpu
}

write-host System Information
write-host CPU $cpu in family $cputype
write-host ($memoryamount)GB of memory

#Find model category-- please define any models/categories you use here
#Does not auto-create so populate snipe-it with your categories before deploying

if($modelno -like "*Opti*") {
    $modelcategoryname = "Desktop"
} elseif ($modelno -like "*Latitude*") {
    $modelcategoryname = "Laptop"
} elseif ($modelno -like "*XPS*") {
    $modelcategoryname = "Laptop"
} elseif ($modelno -like "*Precision*") {
    $modelcategoryname = "Desktop"
} elseif ($modelno -like "*PowerEdge*") {
    $modelcategoryname = "Server"
} elseif ($modelno -like "*Surface*") {
    $modelcategoryname = "Laptop"
} elseif ($modelno -like "*XPS 13*") {
    $modelcategoryname = "Laptop"
} elseif ($modelno -like "*ZQClass*") {
    $modelcategoryname = "ThinClient"
} else {
    $modelcategoryname = "#N/A"
}

write-host "Starting Snipe-it check in to URL $url please wait. . . "

#With hundreds of hosts you might want to up these timings for the first time you run this script

Start-Sleep -Milliseconds (Get-Random -Minimum 300 -Maximum 800)
	
#Define model name structure
#$modelname = $modelno + " " + $cpuType + "/" + $memoryAmount
$modelname = $modelno

#Search for model ID in snipeit based on name, later tries to find the earliest duplicate if there are multiple matches
$modelSelection = Get-SnipeitModel -search $modelname

#Wait then check again if we didn't get a model id back, in case someone else is creating at same time
if(([string]::IsNullOrEmpty($modelSelection)))
{
#Sleep random then check again to prevent clobbering
Start-Sleep -Milliseconds (Get-Random -Minimum 300 -Maximum 20000)

#$modelSelection = Get-SnipeitModel | Where-Object {$_.name -like "*$modelname*"}
$modelSelection = Get-SnipeitModel -search $modelname
}

#Create Model if Doesn't exist
if(([string]::IsNullOrEmpty($modelSelection)))
{
    write-host ($manufacturer + " - " + $modelname + " - model doesn't exist, creating now")
    #Find Manufacturer ID
    $manufacturerselection = Get-Manufacturer -url $url -apikey $apikey | Where-Object {$_.name -eq $manufacturer}

    #Create Manufacturer if not exist

    $manufacturerselection = Get-Manufacturer -url $url -apikey $apikey | Where-Object {$_.name -eq $manufacturer}
    if(([string]::IsNullOrEmpty($manufacturerselection)))
    {
        $manufacturerselection = New-Manufacturer -url $url -apikey $apikey -name $manufacturer
    }

    #Find Model Category

    $categoryselection = Get-Category -url $url -apikey $apikey | Where-Object {$_.name -eq $modelcategoryname }

    # Create Model
    $modelSelection = New-Model -url $url -apikey $apikey -name $modelname -manufacturer_id $manufacturerselection.id -fieldset_id 1 -category_id $categoryselection.id
}

# Create or update asset

$modelID = [int]($modelSelection.id | measure -Minimum).Minimum

#debug from when I was having problems with creating duplicate models
#write-host ("Lowest model array: " + $modelID)
#Get-SnipeitAsset -search $assetTag

$assetExists = Get-SnipeitAsset -search $assetTag

#If asset tag not found, create new asset
if(([string]::IsNullOrEmpty($assetExists)))
{
    Start-Sleep -Milliseconds (Get-Random -Minimum 300 -Maximum 5000)
    write-host "Creating new asset $assetTag"
    New-SnipeitAsset -Name $computerName -tag $assetTag -Model_id $modelID -Status "2"
}
#If asset tag found, evaluate to see if we need to do an update
else {
    #convert last update timestamp from snipeit to usable format
    $json = $($assetexists.updated_at)[0] | convertTo-json
    $dateString = (ConvertFrom-Json $json).datetime
    $date = [DateTime]::ParseExact($dateString, 'yyyy-MM-dd HH:mm:ss', $null)
    
    #configure based on how often you want to see updates
    #I used every 30 days so I don't get hundreds of superfluous updates a day in my dashboard
    if($date -lt (get-date).AddDays(-30).Date)
    {
        Set-SnipeitAsset -id $assetexists.id -notes "Powershell 30 day inventory check-in @ $(Get-Date -format 'u')"
        write-host "Has not checked in within 30 days, last check in $date, updated above"
    } else {
        write-host "Has checked in within 30 days, as of $date"
    }
    #check model ID, this is nice if you have a database where someone was creating these manually
    if($assetexists.model.id -eq $modelID) {
        write-host "Model $modelname Matches ID $modelID"
    } else {
        write-host "Model $modelname ID $assetexists.model.id doesn't match earliest match $modelID, updating"
        Set-SnipeitAsset -id $assetExists.id -model_id $modelID -notes "Powershell updated model ID# @ $(Get-Date -format 'u')"
    }
    #update asset name to current DNS name
    if($assetexists.name -eq $computerName) {
        write-host "Computer DNS name $computerName matches asset name. "
    } else {
        write-host "Computer DNS name $computerName does not match asset name $assetexists.name"
        Set-SnipeitAsset -id $assetExists.id -name $computerName -notes "Powershell updated asset name @ $(Get-Date -format 'u')"
    }
    
}