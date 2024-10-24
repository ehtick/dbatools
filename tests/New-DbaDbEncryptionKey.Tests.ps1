$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe "$CommandName Unit Tests" -Tags "UnitTests" {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'InputObject', 'EnableException', 'EncryptorName', 'EncryptionAlgorithm', 'Force', 'Type'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}


Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $PSDefaultParameterValues["*:Confirm"] = $false
        $passwd = ConvertTo-SecureString "dbatools.IO" -AsPlainText -Force
        $cred = New-Object System.Management.Automation.PSCredential "sqladmin", $passwd

        $masterkey = Get-DbaDbMasterKey -SqlInstance $TestConfig.instance2 -Database master
        if (-not $masterkey) {
            $delmasterkey = $true
            $masterkey = New-DbaServiceMasterKey -SqlInstance $TestConfig.instance2 -SecurePassword $passwd
        }
        $mastercert = Get-DbaDbCertificate -SqlInstance $TestConfig.instance2 -Database master | Where-Object Name -notmatch "##" | Select-Object -First 1
        if (-not $mastercert) {
            $delmastercert = $true
            $mastercert = New-DbaDbCertificate -SqlInstance $TestConfig.instance2
        }

        $db = New-DbaDatabase -SqlInstance $TestConfig.instance2
    }

    AfterAll {
        if ($db) {
            $db | Remove-DbaDatabase
        }
        if ($delmastercert) {
            $mastercert | Remove-DbaDbCertificate
        }
        if ($delmasterkey) {
            $masterkey | Remove-DbaDbMasterKey
        }
    }

    Context "Command actually works" {
        It "should create a new encryption key using piping" {
            $results = $db | New-DbaDbEncryptionKey -Force -EncryptorName $mastercert.Name
            $results.EncryptionAlgorithm | Should -Be "Aes256"
        }
        It "should create a new encryption key" {
            $null = Get-DbaDbEncryptionKey -SqlInstance $TestConfig.instance2 -Database $db.Name | Remove-DbaDbEncryptionKey
            $results = New-DbaDbEncryptionKey -SqlInstance $TestConfig.instance2 -Database $db.Name -Force -EncryptorName $mastercert.Name
            $results.EncryptionAlgorithm | Should -Be "Aes256"
        }
    }
}



Describe "$CommandName Integration Tests for Async" -Tags "IntegrationTests" {
    BeforeAll {
        $PSDefaultParameterValues["*:Confirm"] = $false
        $passwd = ConvertTo-SecureString "dbatools.IO" -AsPlainText -Force
        $masterkey = Get-DbaDbMasterKey -SqlInstance $TestConfig.instance2 -Database master
        if (-not $masterkey) {
            $delmasterkey = $true
            $masterkey = New-DbaServiceMasterKey -SqlInstance $TestConfig.instance2 -SecurePassword $passwd
        }

        $masterasym = Get-DbaDbAsymmetricKey -SqlInstance $TestConfig.instance2 -Database master

        if (-not $masterasym) {
            $delmasterasym = $true
            $masterasym = New-DbaDbAsymmetricKey -SqlInstance $TestConfig.instance2 -Database master
        }

        $db = New-DbaDatabase -SqlInstance $TestConfig.instance2
        $db | New-DbaDbMasterKey -SecurePassword $passwd
        $db | New-DbaDbAsymmetricKey
    }

    AfterAll {
        if ($db) {
            $db | Remove-DbaDatabase
        }
        if ($delmasterasym) {
            $masterasym | Remove-DbaDbAsymmetricKey
        }
        if ($delmasterkey) {
            $masterkey | Remove-DbaDbMasterKey
        }
    }

    # TODO: I think I need some background on this. Was the intention to create the key or not to creeate the key?
    # Currently $warn is:
    # [09:49:20][New-DbaDbEncryptionKey] Failed to create encryption key in random-1299050584 on localhost\sql2016 | Cannot decrypt or encrypt using the specified asymmetric key, either because it has no private key or because the password provided for the private key is incorrect.
    # Will leave it skipped for now.
    Context "Command does not work but warns" {
        # this works on docker, not sure what's up
        It -Skip "should warn that it cant create an encryption key" {
            ($null = $db | New-DbaDbEncryptionKey -Force -Type AsymmetricKey -EncryptorName $masterasym.Name -WarningVariable warn) *> $null
            $warn | Should -Match "n order to encrypt the database encryption key with an as"
        }
    }
}
