<#
.SYNOPSIS
 Generate entity classes from tables in a database

.DESCRIPTION
 Use the MySQL .NET Connector to query a MariaDB database schema and generate
 a programming language class per table. In the first instance it will generate
 java classes but it should support other languages in future

.NOTES
 Date Created: 2018-11-17
 Author: Raj Julha

#>

[CmdletBinding()]
Param(
    [string]$cfgfile = ".\genconfig.json" # TODO: Add validation on existence of config file
)
   # $currentScriptDirectory = Get-Location
   # [System.IO.Directory]::SetCurrentDirectory($currentScriptDirectory.Path)

$config = Get-Content $cfgfile -Raw | ConvertFrom-Json   

$config.assemblies | ForEach-Object {
    # $MySqlLibPath = (Join-Path -Path (Get-Location) -ChildPath "assemblies\MySQL.Data.dll")
    $LibPath = (Join-Path -Path (Get-Location) -ChildPath $_)
    Add-Type -Path $LibPath    
}

# START OF JAVA GENERATATION Functions 
# Will be moved to external class

class JavaGenerator 
{
    $DbTypeToLanguageMap = @{
        bigint = 'Long'
        bit = 'Boolean'
        blob = 'Undefined'
        char = 'char'
        date = 'Date'
        datetime = 'DateTime'
        decimal = 'Double'
        double = 'Double'
        enum = ''
        float = 'Float'
        int = 'Integer'
        longblob = ''
        longtext = 'String'
        mediumtext = 'String'
        set = ''
        smallint = 'Integer'
        text = 'String'
        time = ''
        timestamp = ''
        tinyint = 'Integer'
        tinytext = 'String'
        varbinary = ''
        varchar = 'String'
    }


    $DbFieldName
    $DbFieldType
    $LangFieldName
    $LanFieldType
    $PascalName

    JavaGenerator()
    {}

    JavaGenerator($DbFieldName, $DbFieldType)
    {
        $this.DbFieldName = $DbFieldName
        $this.DbFieldType = $DbFieldType
        $this.LangFieldName = $this.ConvertSnakeCaseToCamelCase($this.DbFieldName) #  ($this.DbFieldName -replace "_", "").ToLower()
        $this.PascalName = $this.ConvertToPascalCase($this.LangFieldName)
        $this.LanFieldType = $this.DbTypeToLanguageMap[$this.DbFieldType]
    }

    [string]ConvertToPascalCase($InputStr)
    {
        $MatchEval = {$args[0].Value.ToUpper()}
        $Pattern = "^."
        return [System.Text.RegularExpressions.Regex]::Replace($InputStr, $Pattern, $MatchEval)
    }

    [string]ConvertSnakeCaseToCamelCase($InputStr)
    {
        $MatchEval = {
            $args[0].Value.Replace("_", "").ToUpper()
        }
        $Pattern = "(_[a-z])+"
        return [System.Text.RegularExpressions.Regex]::Replace($InputStr, $Pattern, $MatchEval)        
    }

    [String] GetPrivateVarName()
    {                
        return $this.ConvertSnakeCaseToCamelCase($this.DbFieldName)
    }

    [string]getPrivateLineDefinition()
    {        
        $PrivateLine = "    private $($this.LanFieldType) $($this.LangFieldName); // DBField: $($this.DbFieldName) $($this.DbFieldType)" 

        return $PrivateLine 
    }
    
    [string]getGetterLine()
    {
        $GetterLine = @()
        $GetterLine += "    public $($this.LanFieldType) get$($this.PascalName)() {"
        $GetterLine += "        return this.$($this.LangFieldName); // " + $this.DbFieldName
        $GetterLine += "    }"
        <#
        	public Long getIdBatch() {
                return this.idBatch;
            }
        #>
        return  ($GetterLine -join "`r`n") #  Note the backtick
    }

    [string]getSetterLine()
    {
        $SetterLine = @()
        $SetterLine += "    public set$($this.PascalName)($($this.LanFieldType) $($this.LangFieldName)) {"
        $SetterLine += "        this.$($this.LangFieldName) = $($this.LangFieldName); // " + $this.DbFieldName
        $SetterLine += "    }"
        <#
            public void setIdBatch(Long idBatch) {
                this.idBatch = idBatch;
            }
        #>

        return  ($SetterLine -join "`r`n") #  ($SetterLine -join "`r`n")  # Note the backtick
    }

    [String]ToString()
    {
        return $this.DbFieldName + "," + $this.DbFieldType
    }
}
# END OF JAVA CLASS GENERATOR

<#
.SYNOPSIS
 Generate a Java class form fields piped from a DB Query

.DESCRIPTION

.PARAMETER DbRow
 A .NET DataRow object containing fieldname and type. This would normally be from a query of INFORMATION_SCHEMA.COLUMNS
 table

.PARAMETER EntityName 
 The table name for which a an entity class is to be generated

.PARAMETER OutputLocation

.PARAMETER EntityName

.PARAMETER Namespace

#>
Function New-Class
{
    [CmdletBinding()]
    Param(
        [Parameter(ValueFromPipeline)]
        $DbRow,
        [string]$OutputLocation,
        [string]$EntityName,
        [string]$Namespace
    )

    BEGIN {

        # The pascal case conversion function is inside the class generator        
        $PascalEntity = [JavaGenerator]::new($EntityName, "varchar")
        
        $Outfile = Join-Path -Path $OutputLocation -ChildPath ("$($PascalEntity.PascalName).java")
        $ClassLines = @() # Ensure first item is added with += and not = as this would make it a string
        Write-Verbose "Creating Class name: $Outfile"
        Write-Verbose "package $Namespace;"
        $ClassLines += "package $Namespace;"
        $ClassLines += "// Generated on $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff'))"

        Write-Verbose ""
        
        $ClassLines += "public class $($PascalEntity.PascalName) implements Serializable {"
        $ClassLines += "" # blank line
        $FieldItems = @()
    }

    PROCESS {
        # $_.COLUMN_NAME #  | gm
        # $_.DATA_TYPE
        $def2 = [JavaGenerator]::new($_.COLUMN_NAME, $_.DATA_TYPE)
        $FieldItems += $def2        
    }

    END {
        $FieldItems | ForEach-Object { $ClassLines += $_.getPrivateLineDefinition() }
        $ClassLines += "" 
        $FieldItems | ForEach-Object { 
                $ClassLines += $_.getGetterLine()
                $ClassLines += $_.getSetterLine() 
            }
              
        $ClassLines += "}"
        Write-Verbose "Closing Class name: $Outfile"
        $classText = ($ClassLines -join "`r`n")
        Write-Verbose $classText
        $classText | Out-File -FilePath $Outfile # should set encoding too  
    }
}

<#
.SYNOPSIS
 Query database to expose DataTable objects

.DESCRIPTION

.PARAMETER ConnectionString
 A connection string specific to the underlying database engine
 For the moment we're using MySQL .NET connector

.PARAMETER Query
 A semi-colon separated of SQL statements

#>
Function Get-SqlData{
    [CmdletBinding()]
    Param(
        [string]$ConnectionString,
        [string]$Query
    )

    try {
 
        Write-Verbose "ConnectionString: $ConnectionString"
        $connection = New-Object MySql.Data.MySqlClient.MySqlConnection
        $connection.ConnectionString = $ConnectionString
        Write-Verbose "Open Database Connection"
        $connection.Open()
        
        
        Write-Verbose "Run MySQL Querys"
        $command = New-Object MySql.Data.MySqlClient.MySqlCommand($query, $connection)
        $dataAdapter = New-Object MySql.Data.MySqlClient.MySqlDataAdapter($command)
        $dataSet = New-Object System.Data.DataSet
        $recordCount = $dataAdapter.Fill($dataSet, "data") #  $dataAdapter.Fill($dataSet)  | Out-Null
        $dtblCount = $dataSet.Tables.Count
        Write-Verbose "Number of records: $recordCount"
        Write-Verbose "Number of datatables: $dtblCount "
        # $dataSet.Tables | Select-Object TableName 
        $tbl1 = $dataSet.Tables[0].TableName
        $tbl2 = $dataSet.Tables[1].TableName
        Write-Verbose "datatables: $tbl1, $tbl2 " # data, data1
        # $dataSet.Tables["data"]  #| Format-Table
        # Return 2 datatables
        $dataSet.Tables["data"], $dataSet.Tables["data1"]  #| Format-Table  #| Format-Table
    }
    catch {
        Write-Host "Could not run MySQL Query" $Error[0]
    }
    Finally {
        Write-Verbose "Close Connection"
        $connection.Close()
    }    
}

$ConnectionString = $config.connectionString #   "Server=localhost;Uid=raj;Pwd=julha;database=idefix;"
# $Query = "SELECT @@Version"

$config.dbTables | ForEach-Object {

    $TmpQuery1 = $config.query.tableQuery -join " " -replace "{{database}}", $config.database 
    $TmpQuery1 = $TmpQuery1 -replace "{{dbTable}}", $_

    $TmpQuery2 = $config.query.linksQuery -join " "
    $Query = $TmpQuery1 + " " + $TmpQuery2

    Write-Verbose $Query

    $data, $data1 = Get-SqlData -ConnectionString $ConnectionString -Query $Query 
    $data
    
    # $data1 # Build a lookup object or pass the datatable itself for foreign key creation
    # $data | New-Class -OutputLocation "E:\junk" -EntityName "$_" -Namespace $config.namespace
}


# Get a list of distinct TABLE_NAME values from dataset and then build a filter for each
# $data | New-Class -OutputLocation "E:\junk" -EntityName "Country" -Namespace $config.namespace

$QueryTemp = @"
SELECT Table_NAME, COLUMN_NAME, DATA_TYPE FROM information_schema.COLUMNS
WHERE table_schema = 'mydbname' and table_name = '$_' ORDER BY table_name, ordinal_position;

SELECT T.* FROM 
(SELECT A.Table_Name AS ContainerObject, REPLACE(F.REF_NAME,'mydbname/', '') AS ForeignObject, 'Object' AS PropertyType  FROM information_schema.TABLES A
LEFT OUTER JOIN information_schema.`INNODB_SYS_FOREIGN` F ON (A.TABLE_NAME = REPLACE(F.FOR_NAME,'mydbname/', ''))
WHERE A.table_schema = 'mydbname'  and table_name = '$_'
UNION
SELECT A.Table_Name AS ContainerObject, REPLACE(F2.FOR_NAME, 'mydbname/', '') AS ForeignObject, 'List' AS ProperTyType FROM information_schema.TABLES A
LEFT OUTER JOIN information_schema.`INNODB_SYS_FOREIGN` F2 ON (A.TABLE_NAME = REPLACE(F2.REF_NAME,'mydbname/', ''))
WHERE A.table_schema = 'mydbname' and table_name = '$_' ) AS T
ORDER BY T.ContainerObject

"@
