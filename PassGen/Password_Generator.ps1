# Password Generator - Paul.Coyle@networkrail.co.uk

Add-Type -AssemblyName System.Windows.Forms

function New-ComplexPassword {
    param(
        [int]$Length = 16,
        [bool]$NoSpecial = $false
    )

    $upper   = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.ToCharArray()
    $lower   = 'abcdefghijklmnopqrstuvwxyz'.ToCharArray()
    $digits  = '0123456789'.ToCharArray()

    # Clean special character list (no hidden characters)
    $special = '!@#%&?'.ToCharArray()

    if ($NoSpecial) {
        $special = @()
    }

    $mandatory = @()
    $mandatory += $upper[(Get-Random -Maximum $upper.Length)]
    $mandatory += $lower[(Get-Random -Maximum $lower.Length)]
    $mandatory += $digits[(Get-Random -Maximum $digits.Length)]

    if ($special.Count -gt 0) {
        $mandatory += $special[(Get-Random -Maximum $special.Length)]
    }

    $all = $upper + $lower + $digits + $special

    $remaining = $Length - $mandatory.Count
    if ($remaining -lt 0) { return "" }

    $random = for ($i = 1; $i -le $remaining; $i++) {
        $all[(Get-Random -Maximum $all.Length)]
    }

    return -join (($mandatory + $random) | Sort-Object { Get-Random })
}

function New-StructuredPassword {

    $words = @(
        "Apple","Brave","Crown","Delta","Eagle","Flame","Grape","Honey",
        "Ivory","Joker","Knock","Lemon","Magic","Night","Ocean","Pearl",
        "Queen","River","Stone","Tiger","Unity","Vivid","Whale","Xenon",
        "Young","Zebra"
    )

    # pick two unique 5-letter words
$wordPair = $words | Sort-Object { Get-Random } | Select-Object -First 2
$word1 = $wordPair[0]
$word2 = $wordPair[1]

    # 3 unique digits
$digitSet = 0..9
$digits = -join ($digitSet | Sort-Object { Get-Random } | Select-Object -First 3)

    # $digits = -join (1..3 | ForEach-Object { (Get-Random -Minimum 0 -Maximum 10) })

    $specialSet = '!@#%&?'.ToCharArray()
    $special = -join ($specialSet | Sort-Object { Get-Random } | Select-Object -First 3)

        return "$word1$special$word2$digits"
}

# GUI
$form = New-Object System.Windows.Forms.Form
$form.Text = "Password Generator"
$form.Size = New-Object System.Drawing.Size(420,300)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false

# --- PRIMARY FEATURE: Structured password ---
#$structured = New-Object System.Windows.Forms.CheckBox
#$structured.Text = "Structured 16-character password"
#$structured.Location = New-Object System.Drawing.Point(20,20)
#$structured.AutoSize = $true
#$structured.Checked = $true
$structured = New-Object System.Windows.Forms.CheckBox
$structured.Text = "Structured 16-char password"
$structured.Location = New-Object System.Drawing.Point(20,20)
$structured.AutoSize = $true
$structured.Checked = $true   # default tick

# Apply structured-mode lockout on startup
$lengthBox.Enabled = $false
$noSpecial.Enabled = $false
$noSpecial.Checked = $false

# Structured mode disables advanced options when toggled
$structured.Add_CheckedChanged({
    if ($structured.Checked) {
        $lengthBox.Enabled = $false
        $noSpecial.Enabled = $false
        $noSpecial.Checked = $false
    }
    else {
        $lengthBox.Enabled = $true
        $noSpecial.Enabled = $true
    }
})

$button = New-Object System.Windows.Forms.Button
$button.Text = "Generate"
$button.Width = 100
$button.Location = New-Object System.Drawing.Point(250,15)

$textbox = New-Object System.Windows.Forms.TextBox
$textbox.Width = 360
$textbox.Location = New-Object System.Drawing.Point(20,60)
$textbox.ReadOnly = $true

$copyButton = New-Object System.Windows.Forms.Button
$copyButton.Text = "Copy"
$copyButton.Width = 100
$copyButton.Location = New-Object System.Drawing.Point(150,100)

# --- SECONDARY FEATURE: Complex password options ---
$advLabel = New-Object System.Windows.Forms.Label
$advLabel.Text = "Advanced random password options:"
$advLabel.Location = New-Object System.Drawing.Point(20,140)
$advLabel.AutoSize = $true

$label = New-Object System.Windows.Forms.Label
$label.Text = "Password Length:"
$label.Location = New-Object System.Drawing.Point(20,170)
$label.AutoSize = $true

$lengthBox = New-Object System.Windows.Forms.NumericUpDown
$lengthBox.Location = New-Object System.Drawing.Point(130,168)
$lengthBox.Minimum = 8
$lengthBox.Maximum = 64
$lengthBox.Value = 20

$noSpecial = New-Object System.Windows.Forms.CheckBox
$noSpecial.Text = "No special characters"
$noSpecial.Location = New-Object System.Drawing.Point(20,200)
$noSpecial.AutoSize = $true

# Structured mode disables advanced options
$structured.Add_CheckedChanged({
    if ($structured.Checked) {
        $lengthBox.Enabled = $false
        $noSpecial.Enabled = $false
        $noSpecial.Checked = $false
    }
    else {
        $lengthBox.Enabled = $true
        $noSpecial.Enabled = $true
    }
})

# Generate button logic
$button.Add_Click({
    if ($structured.Checked) {
        $textbox.Text = New-StructuredPassword
    }
    else {
        $textbox.Text = New-ComplexPassword `
            -Length ([int]$lengthBox.Value) `
            -NoSpecial $noSpecial.Checked
    }
})

# Copy button
$copyButton.Add_Click({
    if ($textbox.Text -ne "") {
        Set-Clipboard -Value $textbox.Text
        [System.Windows.Forms.MessageBox]::Show("Password copied to clipboard!")
    }
})

# Add controls
$form.Controls.Add($structured)
$form.Controls.Add($button)
$form.Controls.Add($textbox)
$form.Controls.Add($copyButton)
$form.Controls.Add($advLabel)
$form.Controls.Add($label)
$form.Controls.Add($lengthBox)
$form.Controls.Add($noSpecial)

$form.Add_Shown({
    if ($structured.Checked) {
        $lengthBox.Enabled = $false
        $noSpecial.Enabled = $false
        $noSpecial.Checked = $false
    }
})

$form.ShowDialog()