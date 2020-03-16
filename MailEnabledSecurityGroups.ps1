$mailEnabledSGs = Get-DistributionGroup | Where-Object {$_.GroupType -match "SecurityEnabled"} | Select Name,DisplayName,GroupType,PrimarySMTPaddress,legacyExchangeDN,Managedby,Alias,EmailAddresses


$mailEnabledSGs | Export-CSV C:\users\abaker\MailEnabledSGsBackup2.csv



foreach($DL in $filteredDLs)
{
    $Managers = $DL.ManagedBy
    $EmailAddresses = @()
    foreach ($user in $Managers)
    {
        $EmailAddresses += Get-Mailbox $user.ToString() | Select PrimarySMTPaddress
        $DL | Add-Member -membertype noteproperty -name EmailAddresses -value $EmailAddresses.PrimarySMTPaddress -Force

    }
    
}



foreach ($DL in $mailEnabledSGs)
{
    if ($DL.Name -match "SG-")
    {
        $SGname = $DL.Name
    }
    elseif ($DL.Name -match "DL-")
    {
        $SGname = $DL.Name -replace "DL-","SG-"
    }
    else
    {
        $SGname = $DL.Name
    }
    if ($DL.DisplayName -match "DL-")
    {
        $DLname = $DL.DisplayName
    }
    if ($DL.DisplayName -match "SG-")
    {
        $DLname = $DL.DisplayName -replace "SG-","DL-"
    }
    else {
        $DLname = $DL.DisplayName
    }
    $DL | Add-Member -membertype noteproperty -name SGName -value $SGname -Force
    $DL | Add-Member -membertype noteproperty -name DLName -value $DLname -Force
}


$filteredDLs = $mailEnabledSGs | Where-Object {$_.ManagedBy -match "rhonemus"}
$filteredDLs = $mailEnabledSGs | Where-Object {$_.Name -notmatch "DL-" -and $_.name -notmatch "SG-" }



#Static Method
foreach ($DL in $filteredDLs)
{
    $DL= Get-DistributionGroup "DL-US Person"
    $members = Get-DistributionGroupMember -Identity $DL.name -ResultSize Unlimited
    #Retrieve x500 address
    $DN = $DL.legacyExchangeDN
    #Retrieve all other addresses
    $Oldemails = Get-DistributionGroup $DL.name | Select-Object -ExpandProperty EmailAddresses

    #Remove Exchange Attributes from mail Enabled SG
    Disable-DistributionGroup $DL.name

    #Rename Mail Enabled SG to just an SG
    if ($DL.DisplayName -match "DL-")
    {
        Get-Adgroup $DL.DisplayName | Rename-ADObject -NewName $DL.NewName
    }

    Set-Adgroup $DL.newname -Remove @{ProxyAddresses=smtp:$DL.PrimarySMTPaddress}
    #move Newly renamed group to Domain Groups OU
    Get-Adgroup $DL.newname | Move-ADObject  -TargetPath "OU=Domain Groups,OU=Domain Users,DC=ad,DC=mc,DC=com"

    #Create New DL
    $alias = $DL.DLcreated -replace " ","_"
    $NewDL = New-DistributionGroup -Name $DL.name -Alias $alias -OrganizationalUnit "ad.mc.com/Exchange Objects/Distribution Lists" -MemberDepartRestriction Closed -MemberJoinRestriction Closed -ManagedBy rhonemus
    
    #Get current Emailaddresses
    $NewEmails = $NewDL | Select-Object -ExpandProperty EmailAddresses
    #Add old SMTP addresses to new group
    foreach ($email in $Oldemails)
    {
        $email = $email -replace "SMTP:","smtp:"
        if(!($NewEmails -icontains $email))
        {
            Set-DistributionGroup -Identity $newDL.name -EmailAddresses @{Add="$email"}
        }
    }
    #Add Members of old DL to new DL
    foreach ($member in $members)
    {
        Add-DistributionGroupMember -Identity $NewDL.name –Member $member.name -BypassSecurityGroupManagerCheck
    } 
    #Set the X500 address for new DL
    Set-DistributionGroup -Identity $NewDL -EmailAddresses @{Add="X500:$DN"}
    
}




#Dynamic DL Method
foreach ($DL in $filteredDLs)
{
    # $DL= Get-DistributionGroup "DL-IT Windows and Applications Team"
    #Retrieve x500 address
    $DN = $DL.legacyExchangeDN
    #Retrieve all other addresses
    $Oldemails = Get-DistributionGroup $DL.name | Select-Object -ExpandProperty EmailAddresses

    #Remove Exchange Attributes from mail Enabled SG
    Disable-DistributionGroup $DL.name -Confirm:$false

    $Group = Get-AdGroup $DL.name

    #Rename Group
    if ($DL.Name -match "DL-")
    {
       $Group = Get-Adgroup $DL.Name | Rename-ADObject -NewName $DL.NewName -PassThru
    }
    #Move Group 
    if ($DL.DistinguishedName -match "OU=Distribution Lists,OU=Exchange Objects,DC=ad,DC=mc,DC=com")
    {
        $Group = Get-Adgroup $Group.name | Move-ADObject -TargetPath "OU=Domain Groups,OU=Domain Users,DC=ad,DC=mc,DC=com" -PassThru
    }
    
    #Create New Dynamic DL
    $alias = $DL.DLcreated -replace " ","_"
    $DistinguishedName = $Group.DistinguishedName
    $NewDL = New-DynamicDistributionGroup -Name $DL.name -Alias $alias -OrganizationalUnit "ad.mc.com/Exchange Objects/Distribution Lists" -RecipientFilter {((RecipientType -eq 'UserMailbox') -and (memberOfgroup -eq "$DistinguishedName"))}
    
    #Get current Emailaddresses 
    $NewEmails = $NewDL | Select-Object -ExpandProperty EmailAddresses
    #Add old SMTP addresses to new group
    foreach ($email in $Oldemails)
    {
        $email = $email -replace "SMTP:","smtp:"
        if(!($NewEmails -icontains $email))
        {
            Set-DynamicDistributionGroup -Identity $newDL.name -EmailAddresses @{Add="$email"}
        }
    }

    #Set the X500 address for new DL
    Set-DynamicDistributionGroup -Identity $NewDL.name -EmailAddresses @{Add="X500:$DN"}
    
}
