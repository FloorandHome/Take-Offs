param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$PlanFile,

    [Parameter(Mandatory = $false)]
    [ValidateSet("1/8 in = 1 ft", "3/16 in = 1 ft", "1/4 in = 1 ft", "1/2 in = 1 ft")]
    [string]$Scale = "1/4 in = 1 ft"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function New-PlanError {
    param([string]$Message)
    throw [System.ArgumentException]::new($Message)
}

function Ensure-Integer {
    param(
        [object]$Value,
        [string]$Field,
        [string]$RoomName
    )

    if ($null -eq $Value) {
        New-PlanError "Room '$RoomName' is missing '$Field'"
    }

    try {
        return [int]$Value
    }
    catch {
        New-PlanError "Room '$RoomName' has non-integer '$Field': '$Value'"
    }
}

function New-Room {
    param(
        [string]$Name,
        [int]$X,
        [int]$Y,
        [int]$Width,
        [int]$Length
    )

    [pscustomobject]@{
        name      = $Name
        x         = $X
        y         = $Y
        width     = $Width
        length    = $Length
        area      = $Width * $Length
        perimeter = 2 * ($Width + $Length)
    }
}

function Parse-PlanData {
    param(
        [object]$Data,
        [string]$Scale
    )

    if ($null -eq $Data) {
        New-PlanError "Plan must be a JSON object"
    }

    $unit = if ([string]::IsNullOrWhiteSpace([string]$Data.unit)) { "m" } else { [string]$Data.unit }
    $roomsRaw = @($Data.rooms)
    if ($roomsRaw.Count -eq 0) {
        New-PlanError "Field 'rooms' must be a non-empty list"
    }

    $rooms = @()
    foreach ($entry in $roomsRaw) {
        $name = [string]$entry.name
        if ([string]::IsNullOrWhiteSpace($name)) {
            New-PlanError "Every room needs a non-empty string 'name'"
        }

        $x = Ensure-Integer -Value $entry.x -Field "x" -RoomName $name
        $y = Ensure-Integer -Value $entry.y -Field "y" -RoomName $name
        $width = Ensure-Integer -Value $entry.width -Field "width" -RoomName $name
        $length = Ensure-Integer -Value $entry.length -Field "length" -RoomName $name

        if ($width -le 0 -or $length -le 0) {
            New-PlanError "Room '$name' must have positive width and length"
        }

        $rooms += New-Room -Name $name.Trim() -X $x -Y $y -Width $width -Length $length
    }

    Validate-NoOverlap -Rooms $rooms

    [pscustomobject]@{
        unit  = $unit.Trim()
        rooms = $rooms
        scale = $Scale
    }
}

function Get-JsonObjectFromText {
    param([string]$Text)

    $start = 0
    while ($true) {
        $start = $Text.IndexOf("{", $start)
        if ($start -lt 0) {
            return $null
        }

        $depth = 0
        $inString = $false
        $escape = $false

        for ($index = $start; $index -lt $Text.Length; $index++) {
            $char = $Text[$index]

            if ($inString) {
                if ($escape) {
                    $escape = $false
                }
                elseif ($char -eq '\') {
                    $escape = $true
                }
                elseif ($char -eq '"') {
                    $inString = $false
                }
                continue
            }

            if ($char -eq '"') {
                $inString = $true
            }
            elseif ($char -eq '{') {
                $depth++
            }
            elseif ($char -eq '}') {
                $depth--
                if ($depth -eq 0) {
                    $candidate = $Text.Substring($start, $index - $start + 1)
                    if ($candidate.Contains('"rooms"') -or $candidate.Contains("'rooms'")) {
                        return $candidate
                    }
                    break
                }
            }
        }

        $start++
    }
}

function Parse-LabeledPlanText {
    param([string]$Text)

    $unit = "m"
    $unitMatch = [regex]::Match($Text, "\bunit\b\s*[:=]?\s*([A-Za-z]+)\b", "IgnoreCase")
    if ($unitMatch.Success) {
        $unit = $unitMatch.Groups[1].Value
    }

    $roomPattern = [regex]"(?:\broom\b\s*[:=-]?\s*)?(?:\bname\b\s*[:=]\s*(?<name>[A-Za-z][A-Za-z0-9 _-]*))(?<body>.*?)(?=(?:\broom\b\s*[:=-]?\s*)?(?:\bname\b\s*[:=])|$)"
    $matches = $roomPattern.Matches($Text)
    if ($matches.Count -eq 0) {
        return $null
    }

    $rooms = @()
    foreach ($match in $matches) {
        $name = $match.Groups["name"].Value.Trim(" ", "-", ":", "`r", "`n", "`t")
        $body = $match.Groups["body"].Value
        $x = Find-Number -Text $body -Field "x"
        $y = Find-Number -Text $body -Field "y"
        $width = Find-Number -Text $body -Field "width"
        $length = Find-Number -Text $body -Field "length"
        if ($null -in @($x, $y, $width, $length)) {
            continue
        }

        $rooms += [pscustomobject]@{
            name   = $name
            x      = $x
            y      = $y
            width  = $width
            length = $length
        }
    }

    if ($rooms.Count -eq 0) {
        return $null
    }

    [pscustomobject]@{
        unit  = $unit
        rooms = $rooms
    }
}

function Find-Number {
    param(
        [string]$Text,
        [string]$Field
    )

    $match = [regex]::Match($Text, "\b$Field\b\s*[:=]?\s*(-?\d+)\b", "IgnoreCase")
    if (-not $match.Success) {
        return $null
    }
    return [int]$match.Groups[1].Value
}

function Get-PlanDataFromTexts {
    param([string[]]$Texts)

    foreach ($text in $Texts) {
        $jsonCandidate = Get-JsonObjectFromText -Text $text
        if ($jsonCandidate) {
            try {
                return $jsonCandidate | ConvertFrom-Json
            }
            catch {
            }
        }

        $labeled = Parse-LabeledPlanText -Text $text
        if ($null -ne $labeled) {
            return $labeled
        }
    }

    return $null
}

function Expand-DeflateBytesToString {
    param([byte[]]$Bytes)

    try {
        $inputStream = New-Object System.IO.MemoryStream(,$Bytes)
        $outputStream = New-Object System.IO.MemoryStream
        $deflateStream = New-Object System.IO.Compression.DeflateStream($inputStream, [System.IO.Compression.CompressionMode]::Decompress)
        $buffer = New-Object byte[] 4096
        while (($read = $deflateStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $outputStream.Write($buffer, 0, $read)
        }
        $deflateStream.Dispose()
        $inputStream.Dispose()
        $decoded = [System.Text.Encoding]::GetEncoding("iso-8859-1").GetString($outputStream.ToArray())
        $outputStream.Dispose()
        return $decoded
    }
    catch {
        return $null
    }
}

function Get-OcrPdfText {
    param([string]$Path)

    $tesseract = (Get-Command tesseract -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue)
    if (-not $tesseract) {
        return $null
    }

    $renderer = (Get-Command pdftoppm -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue)
    if (-not $renderer) {
        $renderer = (Get-Command magick -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue)
    }
    if (-not $renderer) {
        return $null
    }

    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
    New-Item -Path $tempDir -ItemType Directory | Out-Null
    try {
        $images = Render-PdfToImages -Path $Path -TempPath $tempDir -Renderer $renderer
        $ocrParts = @()
        foreach ($image in $images) {
            $ocrParts += & $tesseract $image "stdout" 2>$null
        }
        return ($ocrParts -join [Environment]::NewLine).Trim()
    }
    finally {
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Render-PdfToImages {
    param(
        [string]$Path,
        [string]$TempPath,
        [string]$Renderer
    )

    $rendererName = [System.IO.Path]::GetFileNameWithoutExtension($Renderer).ToLowerInvariant()
    if ($rendererName -eq "pdftoppm") {
        $outputPrefix = Join-Path $TempPath "page"
        & $Renderer "-png" $Path $outputPrefix 2>$null | Out-Null
        return Get-ChildItem -Path $TempPath -Filter "page-*.png" | Sort-Object Name | Select-Object -ExpandProperty FullName
    }

    $outputPattern = Join-Path $TempPath "page-%03d.png"
    & $Renderer "-density" "300" $Path $outputPattern 2>$null | Out-Null
    return Get-ChildItem -Path $TempPath -Filter "page-*.png" | Sort-Object Name | Select-Object -ExpandProperty FullName
}

function Load-PdfPlanData {
    param([string]$Path)

    $rawBytes = [System.IO.File]::ReadAllBytes($Path)
    $latin1 = [System.Text.Encoding]::GetEncoding("iso-8859-1")
    $rawText = $latin1.GetString($rawBytes)
    $candidateTexts = New-Object System.Collections.Generic.List[string]
    $candidateTexts.Add($rawText)

    $streamPattern = [regex]::new("<<.*?>>\s*stream\r?\n(.*?)\r?\nendstream", [System.Text.RegularExpressions.RegexOptions]::Singleline)
    foreach ($match in $streamPattern.Matches($rawText)) {
        $streamText = $match.Groups[1].Value
        $candidateTexts.Add($streamText)

        $streamBytes = $latin1.GetBytes($streamText)
        $decoded = Expand-DeflateBytesToString -Bytes $streamBytes
        if ($decoded) {
            $candidateTexts.Add($decoded)
        }
    }

    $data = Get-PlanDataFromTexts -Texts $candidateTexts.ToArray()
    if ($null -ne $data) {
        return $data
    }

    $ocrText = Get-OcrPdfText -Path $Path
    if ($ocrText) {
        $data = Get-PlanDataFromTexts -Texts @($ocrText)
        if ($null -ne $data) {
            return $data
        }
    }

    New-PlanError "No building plan data found in PDF. Provide a text-based PDF with embedded plan data, or install OCR tools for scanned/image PDFs."
}

function Validate-NoOverlap {
    param([object[]]$Rooms)

    for ($i = 0; $i -lt $Rooms.Count; $i++) {
        for ($j = $i + 1; $j -lt $Rooms.Count; $j++) {
            $roomA = $Rooms[$i]
            $roomB = $Rooms[$j]
            $overlapX = $roomA.x -lt ($roomB.x + $roomB.width) -and $roomB.x -lt ($roomA.x + $roomA.width)
            $overlapY = $roomA.y -lt ($roomB.y + $roomB.length) -and $roomB.y -lt ($roomA.y + $roomA.length)
            if ($overlapX -and $overlapY) {
                New-PlanError "Rooms '$($roomA.name)' and '$($roomB.name)' overlap"
            }
        }
    }
}

function Get-SymbolMap {
    param([object[]]$Rooms)

    $used = @{}
    $symbolMap = @{}
    $fallback = "123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ".ToCharArray()

    foreach ($room in $Rooms) {
        $preferred = $room.name.Substring(0, 1).ToUpperInvariant()
        if ([char]::IsLetterOrDigit([char]$preferred) -and -not $used.ContainsKey($preferred)) {
            $symbol = $preferred
        }
        else {
            $symbol = $null
            foreach ($candidate in $fallback) {
                $candidateText = [string]$candidate
                if (-not $used.ContainsKey($candidateText)) {
                    $symbol = $candidateText
                    break
                }
            }
        }

        $used[$symbol] = $true
        $symbolMap[$room.name] = $symbol
    }

    return $symbolMap
}

function Render-Map {
    param([object]$Plan)

    $maxX = 0
    $maxY = 0
    foreach ($room in $Plan.rooms) {
        $maxX = [Math]::Max($maxX, $room.x + $room.width)
        $maxY = [Math]::Max($maxY, $room.y + $room.length)
    }

    $canvas = @()
    for ($y = 0; $y -lt $maxY; $y++) {
        $row = @()
        for ($x = 0; $x -lt $maxX; $x++) {
            $row += "."
        }
        $canvas += ,$row
    }

    $symbolMap = Get-SymbolMap -Rooms $Plan.rooms
    foreach ($room in $Plan.rooms) {
        $symbol = $symbolMap[$room.name]
        for ($y = $room.y; $y -lt ($room.y + $room.length); $y++) {
            for ($x = $room.x; $x -lt ($room.x + $room.width); $x++) {
                $canvas[$y][$x] = $symbol
            }
        }
    }

    $rows = New-Object System.Collections.Generic.List[string]
    $rows.Add("Scale: $($Plan.scale)")
    $rows.Add("Building plan map (top view):")
    for ($y = $maxY - 1; $y -ge 0; $y--) {
        $rows.Add(("{0,2} | " -f $y) + ($canvas[$y] -join " "))
    }
    $rows.Add("   + " + ("-" * ($maxX * 2 - 1)))
    $rows.Add("     " + ((0..($maxX - 1)) -join " "))

    $legendEntries = @()
    foreach ($room in $Plan.rooms) {
        $legendEntries += "$($symbolMap[$room.name])=$($room.name)"
    }
    $rows.Add("Legend: " + ($legendEntries -join ", "))
    return $rows -join [Environment]::NewLine
}

function Render-RoomDimensions {
    param([object]$Plan)

    $unit2 = "$($Plan.unit)^2"
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("Room dimensions:")
    $lines.Add(("{0,-20} {1,-15} {2,-7} {3,-7} {4,-8} {5,-10}" -f "Room", "Position (x,y)", "Width", "Length", "Area", "Perimeter"))
    $lines.Add("-" * 75)

    $totalArea = 0
    foreach ($room in $Plan.rooms) {
        $totalArea += $room.area
        $position = "($($room.x),$($room.y))"
        $areaText = "$($room.area) $unit2"
        $perimeterText = "$($room.perimeter) $($Plan.unit)"
        $lines.Add(("{0,-20} {1,-15} {2,-7} {3,-7} {4,-8} {5,-10}" -f $room.name, $position, $room.width, $room.length, $areaText, $perimeterText))
    }

    $lines.Add("-" * 75)
    $lines.Add("Total area: $totalArea $unit2")
    return $lines -join [Environment]::NewLine
}

function Load-Plan {
    param(
        [string]$Path,
        [string]$Scale
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        New-PlanError "Plan file not found: $Path"
    }

    $extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    if ($extension -eq ".pdf") {
        $data = Load-PdfPlanData -Path $Path
    }
    else {
        $data = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    }

    return Parse-PlanData -Data $data -Scale $Scale
}

$plan = Load-Plan -Path $PlanFile -Scale $Scale
Write-Output (Render-Map -Plan $plan)
Write-Output ""
Write-Output (Render-RoomDimensions -Plan $plan)
