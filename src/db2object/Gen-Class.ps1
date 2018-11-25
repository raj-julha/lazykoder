<#
.SYNOPSIS
 Generate entity classes from tables in a database

.DESCRIPTION
 Use the MySQL .NET Connector to query a MariaDB database schema and generate
 a programming language class per table. In the first instance it will generate
 java classes but it should support other languages in future

 Download mysql connector for .NET from https://dev.mysql.com/downloads/connector/net/8.0.html 
 Development of this script was performed using mysql-connector-net-8.0.13.msi

.NOTES
 Date Created: 2018-11-17
 Author: Raj Julha

#>

[CmdletBinding()]
Param(
    [string]$cfgfile = ".\genconfig.json", # TODO: Add validation on existence of config file
    [switch]$SaveQueryResult = $false
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
# Will be moved to external class or
# a powershell PSM module

class JavaGenerator 
{
    $DbTypeToLanguageMap = @{
        bigint = 'Long'
        bit = 'Boolean'
        blob = 'String'
        char = 'String'
        date = 'Date'
        datetime = 'Date'
        decimal = 'Double'
        double = 'Double'
        enum = ''
        float = 'Float'
        int = 'Integer'
        longblob = 'String'
        longtext = 'String'
        mediumtext = 'String'
        set = ''
        smallint = 'Integer'
        text = 'String'
        time = 'Timstamp'
        timestamp = 'Timstamp'
        tinyint = 'Integer'
        tinytext = 'String'
        varbinary = 'Byte'
        varchar = 'String'
    }


    [string]$DbFieldName
    [string]$DbFieldType
    [string]$LangFieldName
    [string]$LanFieldType
    [string]$PascalName
    [string]$PropertyType

    # Note: Contrary to C# we cannot have constructor chaining using this(), this(x) etc.
    # See stackoverflow link for workaround
    # See https://blogs.technet.microsoft.com/heyscriptingguy/2015/09/09/powershell-5-classes-constructor-overloading/
    # https://stackoverflow.com/questions/44413206/constructor-chaining-in-powershell-call-other-constructors-in-the-same-class

    # Hidden, chained helper methods that the constructors must call.
    hidden Init([string]$DbFieldName) { $this.Init($DbFieldName, "varchar", "default")}    # We can also use $null for empty args
    hidden Init([string]$DbFieldName, [string]$DbFieldType) { $this.Init($DbFieldName, $DbFieldType, "default")}
    hidden Init([string]$DbFieldName, [string]$DbFieldType, $PropertyType) 
    {

        $this.DbFieldName = $DbFieldName
        $this.DbFieldType = $DbFieldType
        $this.PropertyType = $PropertyType
        $this.LangFieldName = $this.ConvertSnakeCaseToCamelCase($this.DbFieldName) #  ($this.DbFieldName -replace "_", "").ToLower()
        $this.PascalName = $this.ConvertToPascalCase($this.LangFieldName)
        $this.LanFieldType = $this.DbTypeToLanguageMap[$this.DbFieldType]
        
    }

    JavaGenerator()
    {}

    JavaGenerator($DbFieldName, $DbFieldType)
    {
        $this.Init($DbFieldName, $DbFieldType)
    }

    <#
    PropertyType can be Object or List. 
    TODO: See how we can use enums
    #>
    JavaGenerator($DbFieldName, $DbFieldType, $PropertyType)
    {
        $this.Init($DbFieldName, $DbFieldType, $PropertyType)    
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
        $PrivateLine = ""     
        if($this.PropertyType -eq "default"){
            $PrivateLine = "    private $($this.LanFieldType) $($this.LangFieldName); // DBField: $($this.DbFieldName) $($this.DbFieldType)" 
        }
        elseif ($this.PropertyType -eq "Entity") {
            $PrivateLine = "    private $($this.PascalName) $($this.LangFieldName); "
        }
        elseif ($this.PropertyType -eq "List") {
            $PrivateLine = "    private List<$($this.PascalName)> $($this.LangFieldName)s; "
        }
        else{
            $PrivateLine = "    private $($this.LanFieldType) $($this.LangFieldName); // DBField: $($this.DbFieldName) $($this.DbFieldType)" 
        }


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
        $SetterLine += "    public void set$($this.PascalName)($($this.LanFieldType) $($this.LangFieldName)) {"
        $SetterLine += "        this.$($this.LangFieldName) = $($this.LangFieldName); // " + $this.DbFieldName
        $SetterLine += "    }"
        <#
            public void setIdBatch(Long idBatch) {
                this.idBatch = idBatch;
            }
        #>

        return  ($SetterLine -join "`r`n") #  ($SetterLine -join "`r`n")  # Note the backtick
    }


    # TODO: Expose a single GetGetterLine method with argument and then call specific ones like this one
    [string]getObjectGetterLine()
    {
        $GetterLine = @()
        $GetterLine += "    public $($this.PascalName) get$($this.PascalName)() {"
        $GetterLine += "        return this.$($this.LangFieldName); // " + $this.DbFieldName
        $GetterLine += "    }"

        <#

            public BatchItem getBatchItem() {
                return this.batchItem;
            }
            
        #>

        return  ($GetterLine -join "`r`n") #  Note the backtick
    }

    [string]getObjectSetterLine()
    {
        $SetterLine = @()
        $SetterLine += "    public void set$($this.PascalName)($($this.PascalName) $($this.LangFieldName)) {"
        $SetterLine += "        this.$($this.LangFieldName) = $($this.LangFieldName); // " + $this.DbFieldName
        $SetterLine += "    }"

        <#
            public void setBatchItem(BatchItem batchItem) {
                this.batchItem = batchItem;
            }
        #>
        return  ($SetterLine -join "`r`n") #  ($SetterLine -join "`r`n")  # Note the backtick
    }

    [string]getListGetterLine()
    {
        $GetterLine = @()
        $GetterLine += "    public List<$($this.PascalName)> get$($this.PascalName)s() {"
        $GetterLine += "        return this.$($this.LangFieldName)s; // " + $this.DbFieldName
        $GetterLine += "    }"
        <#
            public List<RefObject> getRefObjects() {
                return this.refObjects;
            }

            Must have this in variables definitions
            private List<RefObject> refObjects = new HashSet<RefObject>(0);
        #>
        return  ($GetterLine -join "`r`n") #  Note the backtick
    }

    [string]getListSetterLine()
    {
        $SetterLine = @()
        $SetterLine += "    public set$($this.PascalName)s(List<$($this.PascalName)> $($this.LangFieldName)s) {"
        $SetterLine += "        this.$($this.LangFieldName)s = $($this.LangFieldName)s; // " + $this.DbFieldName
        $SetterLine += "    }"
        <#
            public void setBatchItems(Set<BatchItem> batchItems) {
                this.batchItems = batchItems;
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

# BEGIN RELATIONSHIP GENERATOR
class EntityRelationGenerator {
    $RelationShipMap
    $PrivateItems
    $GetterSetterItems # Check how we can indicate it is an array
    [string]$PrivatePropText

    EntityRelationGenerator() {}

    hidden GenerateCode(){
        # $myRel.RelationShipMap | Where-Object {$_.PropertyType -eq "List"}
        #  |
        $this.PrivateItems = @()
        $this.GetterSetterItems = @()

        $Props = @()
        $this.RelationShipMap | Where-Object {$_.ForeignObject -ne ""} | ForEach-Object {
                # $Props += ($_.ForeignObject  + " xyz")

                $obj1 = [JavaGenerator]::new($_.ForeignObject, "varchar", $_.PropertyType)
                $Props += $obj1

            }

        $Props | ForEach-Object {
            # $_.PropertyType
            $this.PrivateItems += $_.getPrivateLineDefinition()
            $this.GetterSetterItems += $_.getObjectGetterLine()
            $this.GetterSetterItems += $_.getObjectSetterLine()

        }          
        # $this.PrivatePropText = $Props -join "|"
    }
    EntityRelationGenerator([string]$RelationMapJsonString){
        $this.RelationShipMap = ($RelationMapJsonString | ConvertFrom-Json) # | ConvertFrom-Json
        $this.GenerateCode()
    }


    [string]GetPrivateDefinitions()
    {
        # //$RelationShipMap
        # $ts1 = @()
        # $this.RelationShipMap | Where-Object {$_.PropertyType -eq "Entity"} | ForEach-Object {$ts1 += $_.ForeignObject }
        # return "private " + ($ts1 -join "|"  )
        return $this.PrivatePropText

    }
}


# END RELATIONSHIP GENERATOR

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
        $ClassLines += "// --- OBJECTDEFINITIONPLACEHOLDER ---" 
        $ClassLines += "" 
        $FieldItems | ForEach-Object { 
                $ClassLines += $_.getGetterLine()
                $ClassLines += $_.getSetterLine() 
            }

        $ClassLines += "" 
        ## Another step will replace this with block of text which should be preceeded anf followed by newlines
        $ClassLines += "// --- OBJECTMETHODPLACEHOLDER ---"  
        $ClassLines += "" 
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

$ConnectionString = $config.connectionString #   "Server=localhost;Uid=raj;Pwd=xyz;database=mydbname;"
# $Query = "SELECT @@Version"

$config.dbTables | ForEach-Object {

    $TmpQuery1 = $config.query.tableQuery -join " " -replace "{{database}}", $config.database 
    $TmpQuery1 = $TmpQuery1 -replace "{{dbTable}}", $_

    $TmpQuery2 = $config.query.linksQuery -join " " -replace "{{database}}", $config.database 
    $TmpQuery2 = $TmpQuery2 -replace "{{dbTable}}", $_

    $Query = $TmpQuery1 + " " + $TmpQuery2

    Write-Verbose $Query

    $data, $data1 = Get-SqlData -ConnectionString $ConnectionString -Query $Query 
    if($SaveQueryResult){
        $cfgFilenameOnly = $_ + "-" + [System.IO.Path]::GetFileNameWithoutExtension($cfgfile)
        $outData1 = (Join-Path -Path $config.outputLocation -ChildPath ("$($cfgFilenameOnly)_1.csv"))
        $outData2 = (Join-Path -Path $config.outputLocation -ChildPath ("$($cfgFilenameOnly)_2.csv"))
        $data | Export-Csv -Path $outData1 -NoTypeInformation

        $data1 | Export-Csv -Path $outData2 -NoTypeInformation
    }
    # https://stackoverflow.com/questions/20688860/how-to-convert-datatable-to-json-using-convertto-json-in-powershell-v3
    # We want to convert the DataTable object type into a JSO string so that we pass it around 
    # without any dependency of this object as well as to reduce its unnecessary properties for our use
    $EntityRelation = ($data1 | Select-Object $data1.columns.columnname) |  ConvertTo-Json 
    
    $myRel = [EntityRelationGenerator]::new($EntityRelation) # Check if $EntityRelation is a string representation of a JSON object or a JSON object
    # $myRel.RelationShipMap | Where-Object {$_.PropertyType -eq "List"}
    # $myRel.GetPrivateDefinitions()
    $myRel.PrivateItems
    $myRel.GetterSetterItems
    # $data1 # Build a lookup object or pass the datatable itself for foreign key creation
    $data | New-Class -OutputLocation $config.outputLocation -EntityName "$_" -Namespace $config.namespace
}

$obj1 = [JavaGenerator]::new("batch_item", "varchar", "List")
$obj1.PropertyType
$obj1.getObjectGetterLine()
$obj1.getObjectSetterLine()

$obj1.getListGetterLine()
$obj1.getListSetterLine()

