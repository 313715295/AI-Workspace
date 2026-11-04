Set-StrictMode -Version Latest

function Assert-AiwInputJsonMembers($Element) {
    if ($Element.ValueKind -eq [System.Text.Json.JsonValueKind]::Object) {
        $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach($property in $Element.EnumerateObject()) {
            if(-not $seen.Add($property.Name)){throw ('INPUT_FIELD_COUNT|'+$property.Name)}
            Assert-AiwInputJsonMembers $property.Value
        }
    } elseif($Element.ValueKind -eq [System.Text.Json.JsonValueKind]::Array) {
        foreach($item in $Element.EnumerateArray()){Assert-AiwInputJsonMembers $item}
    }
}

function ConvertFrom-StrictJsonValue {
    param([Parameter(Mandatory)][string]$Text,[switch]$RequireObject,[string[]]$StringFields=@(),[string[]]$NullableStringFields=@())
    if($Text.Length -gt 0 -and $Text[0] -eq [char]0xFEFF){throw 'INPUT_BOM'}
    if($Text.Contains([char]0) -or $Text.Contains([char]0xFFFD)){throw 'INPUT_TEXT_FORMAT'}
    try{$null=[Text.UTF8Encoding]::new($false,$true).GetBytes($Text)}catch{throw 'INPUT_UTF8'}
    try{$document=[System.Text.Json.JsonDocument]::Parse($Text)}catch{throw 'INPUT_JSON'}
    try{
        $isObject=$document.RootElement.ValueKind -eq [System.Text.Json.JsonValueKind]::Object
        if($RequireObject-and-not$isObject){throw 'INPUT_OBJECT_TYPE'}
        Assert-AiwInputJsonMembers $document.RootElement
        $names=[string[]]@(if($isObject){$document.RootElement.EnumerateObject()|ForEach-Object{$_.Name}})
        $strings=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
        foreach($field in @($StringFields)+@($NullableStringFields)){
            if([string]::IsNullOrWhiteSpace($field)-or$strings.ContainsKey($field)){throw 'INPUT_STRING_FIELDS'}
            $token=[Text.Json.JsonElement]::new()
            if(-not$document.RootElement.TryGetProperty($field,[ref]$token)){throw ('INPUT_STRING_FIELD_MISSING|'+$field)}
            if($token.ValueKind-eq[Text.Json.JsonValueKind]::String){$strings.Add($field,$token.GetString())}
            elseif($field-cin$NullableStringFields-and$token.ValueKind-eq[Text.Json.JsonValueKind]::Null){$strings.Add($field,$null)}
            else{throw ('INPUT_STRING_FIELD_TYPE|'+$field)}
        }
    }finally{$document.Dispose()}
    try{$value=ConvertFrom-Json -InputObject $Text -Depth 100 -NoEnumerate}catch{throw 'INPUT_JSON'}
    foreach($field in $strings.Keys){$value.PSObject.Properties[$field].Value=$strings[$field]}
    return [pscustomobject]@{MemberNames=[string[]]$names;Value=$value}
}

function Read-StrictJsonText {
    param([Parameter(Mandatory)][string]$Path)
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw 'INPUT_MISSING'}
    $item=Get-Item -LiteralPath $Path -Force
    if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne0){throw 'INPUT_REPARSE'}
    $bytes=[IO.File]::ReadAllBytes($item.FullName)
    if($bytes.Length-ge3-and$bytes[0]-eq239-and$bytes[1]-eq187-and$bytes[2]-eq191){throw 'INPUT_BOM'}
    try{$text=[Text.UTF8Encoding]::new($false,$true).GetString($bytes)}catch{throw 'INPUT_UTF8'}
    return $text
}

function ConvertFrom-AiwStrictInputJson {
    param([Parameter(Mandatory)][string]$Text,[string[]]$StringFields=@(),[string[]]$NullableStringFields=@())
    ConvertFrom-StrictJsonValue $Text -RequireObject -StringFields $StringFields -NullableStringFields $NullableStringFields
}

function Read-AiwStrictInputJson {
    param([Parameter(Mandatory)][string]$Path,[string[]]$StringFields=@(),[string[]]$NullableStringFields=@())
    ConvertFrom-AiwStrictInputJson (Read-StrictJsonText $Path) -StringFields $StringFields -NullableStringFields $NullableStringFields
}

function Read-AiwStrictJsonValue {
    param([Parameter(Mandatory)][string]$Path)
    ConvertFrom-StrictJsonValue (Read-StrictJsonText $Path)
}
Export-ModuleMember -Function Read-AiwStrictInputJson,ConvertFrom-AiwStrictInputJson,Read-AiwStrictJsonValue
