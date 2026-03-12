Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$readerScript = Join-Path $scriptRoot "plan_reader.ps1"
$powershellExe = Join-Path $PSHOME "powershell.exe"

$form = New-Object System.Windows.Forms.Form
$form.Text = "Building Plan Room Mapper"
$form.StartPosition = "CenterScreen"
$form.Size = New-Object System.Drawing.Size(980, 700)
$form.MinimumSize = New-Object System.Drawing.Size(980, 700)

$uploadGroup = New-Object System.Windows.Forms.GroupBox
$uploadGroup.Text = "Upload Floor Plan Pdf"
$uploadGroup.Location = New-Object System.Drawing.Point(16, 16)
$uploadGroup.Size = New-Object System.Drawing.Size(932, 180)
$form.Controls.Add($uploadGroup)

$fileLabel = New-Object System.Windows.Forms.Label
$fileLabel.Text = "Selected file"
$fileLabel.Location = New-Object System.Drawing.Point(18, 34)
$fileLabel.AutoSize = $true
$uploadGroup.Controls.Add($fileLabel)

$fileTextBox = New-Object System.Windows.Forms.TextBox
$fileTextBox.Location = New-Object System.Drawing.Point(18, 56)
$fileTextBox.Size = New-Object System.Drawing.Size(700, 24)
$fileTextBox.ReadOnly = $true
$uploadGroup.Controls.Add($fileTextBox)

$uploadButton = New-Object System.Windows.Forms.Button
$uploadButton.Text = "Upload PDF"
$uploadButton.Location = New-Object System.Drawing.Point(736, 54)
$uploadButton.Size = New-Object System.Drawing.Size(160, 28)
$uploadGroup.Controls.Add($uploadButton)

$scaleLabel = New-Object System.Windows.Forms.Label
$scaleLabel.Text = "Plan scale"
$scaleLabel.Location = New-Object System.Drawing.Point(18, 100)
$scaleLabel.AutoSize = $true
$uploadGroup.Controls.Add($scaleLabel)

$scaleComboBox = New-Object System.Windows.Forms.ComboBox
$scaleComboBox.Location = New-Object System.Drawing.Point(18, 122)
$scaleComboBox.Size = New-Object System.Drawing.Size(260, 24)
$scaleComboBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
[void]$scaleComboBox.Items.Add("1/8 in = 1 ft")
[void]$scaleComboBox.Items.Add("3/16 in = 1 ft")
[void]$scaleComboBox.Items.Add("1/4 in = 1 ft")
[void]$scaleComboBox.Items.Add("1/2 in = 1 ft")
$scaleComboBox.SelectedIndex = 2
$uploadGroup.Controls.Add($scaleComboBox)

$runButton = New-Object System.Windows.Forms.Button
$runButton.Text = "Process Plan"
$runButton.Location = New-Object System.Drawing.Point(736, 118)
$runButton.Size = New-Object System.Drawing.Size(160, 30)
$uploadGroup.Controls.Add($runButton)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = "Choose a PDF or JSON file, then process the plan."
$statusLabel.Location = New-Object System.Drawing.Point(300, 126)
$statusLabel.Size = New-Object System.Drawing.Size(410, 20)
$uploadGroup.Controls.Add($statusLabel)

$outputLabel = New-Object System.Windows.Forms.Label
$outputLabel.Text = "Plan output"
$outputLabel.Location = New-Object System.Drawing.Point(18, 214)
$outputLabel.AutoSize = $true
$form.Controls.Add($outputLabel)

$outputTextBox = New-Object System.Windows.Forms.TextBox
$outputTextBox.Location = New-Object System.Drawing.Point(18, 238)
$outputTextBox.Size = New-Object System.Drawing.Size(930, 390)
$outputTextBox.Multiline = $true
$outputTextBox.ScrollBars = "Both"
$outputTextBox.ReadOnly = $true
$outputTextBox.Font = New-Object System.Drawing.Font("Consolas", 10)
$form.Controls.Add($outputTextBox)

$openDialog = New-Object System.Windows.Forms.OpenFileDialog
$openDialog.Filter = "Plan files (*.pdf;*.json)|*.pdf;*.json|PDF files (*.pdf)|*.pdf|JSON files (*.json)|*.json"
$openDialog.Title = "Upload Floor Plan Pdf"

$uploadButton.Add_Click({
    if ($openDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $fileTextBox.Text = $openDialog.FileName
        $statusLabel.Text = "Ready to process $([System.IO.Path]::GetFileName($openDialog.FileName))."
    }
})

$runButton.Add_Click({
    if ([string]::IsNullOrWhiteSpace($fileTextBox.Text)) {
        [System.Windows.Forms.MessageBox]::Show(
            "Choose a floor plan PDF or JSON file first.",
            "No File Selected",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
        return
    }

    $statusLabel.Text = "Processing plan..."
    $outputTextBox.Text = ""
    $form.UseWaitCursor = $true

    try {
        $result = & $powershellExe -ExecutionPolicy Bypass -File $readerScript -PlanFile $fileTextBox.Text -Scale $scaleComboBox.SelectedItem 2>&1
        $outputTextBox.Text = ($result -join [Environment]::NewLine)
        $statusLabel.Text = "Plan processed successfully."
    }
    catch {
        $outputTextBox.Text = $_.Exception.Message
        $statusLabel.Text = "Plan processing failed."
    }
    finally {
        $form.UseWaitCursor = $false
    }
})

[void]$form.ShowDialog()
