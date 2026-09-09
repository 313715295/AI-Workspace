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

function ConvertFrom-AiwStrictInputJson {
    param([Parameter(Mandatory)][string]$Text)
    if($Text.Length -gt 0 -and $Text[0] -eq [char]0xFEFF){throw 'INPUT_BOM'}
    if($Text.Contains("`r") -or $Text.Contains([char]0) -or $Text.Contains([char]0xFFFD) -or -not $Text.EndsWith("`n")){throw 'INPUT_TEXT_FORMAT'}
    try{$null=[Text.UTF8Encoding]::new($false,$true).GetBytes($Text)}catch{throw 'INPUT_UTF8'}
    try{$document=[System.Text.Json.JsonDocument]::Parse($Text)}catch{throw 'INPUT_JSON'}
    try{
        if($document.RootElement.ValueKind -ne [System.Text.Json.JsonValueKind]::Object){throw 'INPUT_OBJECT_TYPE'}
        Assert-AiwInputJsonMembers $document.RootElement
        $names=@($document.RootElement.EnumerateObject()|ForEach-Object{$_.Name})
    }finally{$document.Dispose()}
    try{$value=$Text|ConvertFrom-Json -Depth 100}catch{throw 'INPUT_JSON'}
    return [pscustomobject]@{MemberNames=[string[]]$names;Value=$value}
}

function Read-AiwStrictInputJson {
    param([Parameter(Mandatory)][string]$Path)
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw 'INPUT_MISSING'}
    $item=Get-Item -LiteralPath $Path -Force
    if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne0){throw 'INPUT_REPARSE'}
    $bytes=[IO.File]::ReadAllBytes($item.FullName)
    if($bytes.Length-ge3-and$bytes[0]-eq239-and$bytes[1]-eq187-and$bytes[2]-eq191){throw 'INPUT_BOM'}
    try{$text=[Text.UTF8Encoding]::new($false,$true).GetString($bytes)}catch{throw 'INPUT_UTF8'}
    return ConvertFrom-AiwStrictInputJson $text
}
Export-ModuleMember -Function Read-AiwStrictInputJson,ConvertFrom-AiwStrictInputJson
