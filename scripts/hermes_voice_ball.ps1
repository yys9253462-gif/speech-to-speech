Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$stateDir = Join-Path $env:APPDATA 'HermesCloudAudio'
$pidPath = Join-Path $stateDir 'voice-agent.pid'
$ballPidPath = Join-Path $stateDir 'voice-ball.pid'
New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
Set-Content -LiteralPath $ballPidPath -Value $PID -Encoding ASCII

function Get-AgentProcess {
    if (-not (Test-Path -LiteralPath $pidPath)) { return $null }
    try { Get-Process -Id ([int](Get-Content -LiteralPath $pidPath -Raw)) -ErrorAction Stop }
    catch { Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue; $null }
}

$form = New-Object System.Windows.Forms.Form
$form.FormBorderStyle = 'None'
$form.Size = New-Object System.Drawing.Size(74, 74)
$form.StartPosition = 'Manual'
$form.Location = New-Object System.Drawing.Point(([System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea.Right - 100), 160)
$form.TopMost = $true
$form.ShowInTaskbar = $false
$form.BackColor = [System.Drawing.Color]::Fuchsia
$form.TransparencyKey = [System.Drawing.Color]::Fuchsia

$ball = New-Object System.Windows.Forms.Button
$ball.Dock = 'Fill'
$ball.FlatStyle = 'Flat'
$ball.FlatAppearance.BorderSize = 0
$ball.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 18, [System.Drawing.FontStyle]::Bold)
$ball.ForeColor = [System.Drawing.Color]::White
$ball.Cursor = [System.Windows.Forms.Cursors]::Hand
$form.Controls.Add($ball)

$menu = New-Object System.Windows.Forms.ContextMenuStrip
$openItem = $menu.Items.Add('打开语音助手控制台')
$stopItem = $menu.Items.Add('停止语音助手')
$hideItem = $menu.Items.Add('隐藏悬浮球')
$exitItem = $menu.Items.Add('退出悬浮球')

function Update-Ball {
    $running = Get-AgentProcess
    if ($running) {
        $ball.Text = '听'
        $ball.BackColor = [System.Drawing.Color]::FromArgb(28, 150, 96)
        $ball.AccessibleName = '语音助手正在聆听'
        $ball.AccessibleDescription = '左键打开控制台；右键管理语音助手。'
        $stopItem.Enabled = $true
    } else {
        $ball.Text = '语'
        $ball.BackColor = [System.Drawing.Color]::FromArgb(95, 105, 120)
        $ball.AccessibleName = '语音助手未启动'
        $ball.AccessibleDescription = '左键打开控制台后启动；右键管理悬浮球。'
        $stopItem.Enabled = $false
    }
    $region = New-Object System.Drawing.Region (New-Object System.Drawing.Drawing2D.GraphicsPath)
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddEllipse(1, 1, $form.Width - 2, $form.Height - 2)
    $form.Region = New-Object System.Drawing.Region($path)
}

$openItem.Add_Click({ Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "$projectRoot\scripts\hermes_voice_console.ps1") })
$ball.Add_Click({ $openItem.PerformClick() })
$ball.Add_MouseUp({ param($sender, $event) if ($event.Button -eq [System.Windows.Forms.MouseButtons]::Right) { $menu.Show($form, $event.Location) } })
$stopItem.Add_Click({ $process = Get-AgentProcess; if ($process) { Stop-Process -Id $process.Id -Force }; Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue; Update-Ball })
$hideItem.Add_Click({ $form.Hide() })
$exitItem.Add_Click({ $form.Close() })

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 1000
$timer.Add_Tick({ Update-Ball })
$form.Add_Shown({ Update-Ball; $timer.Start() })
$form.Add_FormClosed({ Remove-Item -LiteralPath $ballPidPath -Force -ErrorAction SilentlyContinue })
[void]$form.ShowDialog()

