Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$stateDir = Join-Path $env:APPDATA 'HermesCloudAudio'
$configPath = Join-Path $stateDir 'config.json'
$pidPath = Join-Path $stateDir 'voice-agent.pid'

function Get-Settings {
    $values = @{ HermesBaseUrl='http://127.0.0.1:8642/v1'; AudioBaseUrl='https://gpt.isoziyuan.com/v1'; KeyFile=(Join-Path $env:USERPROFILE '.hermes-cloud-audio\api_key'); HermesKey='' }
    if (Test-Path $configPath) { try {
        $saved = Get-Content $configPath -Raw | ConvertFrom-Json
        foreach ($name in $values.Keys) { if ($null -ne $saved.$name) { $values[$name] = [string]$saved.$name } }
        if ($values.HermesKey) { $values.HermesKey = [System.Net.NetworkCredential]::new('', (ConvertTo-SecureString $values.HermesKey)).Password }
    } catch {} }
    $values
}
function Save-Settings($values) {
    New-Item -ItemType Directory -Force $stateDir | Out-Null
    $protected = if ($values.HermesKey) { ConvertTo-SecureString $values.HermesKey -AsPlainText -Force | ConvertFrom-SecureString } else { '' }
    @{ HermesBaseUrl=$values.HermesBaseUrl; AudioBaseUrl=$values.AudioBaseUrl; KeyFile=$values.KeyFile; HermesKey=$protected } | ConvertTo-Json | Set-Content $configPath -Encoding UTF8
}
function Get-AgentProcess {
    if (-not (Test-Path $pidPath)) { return $null }; try { Get-Process -Id ([int](Get-Content $pidPath -Raw)) -ErrorAction Stop } catch { Remove-Item $pidPath -Force -ErrorAction SilentlyContinue; $null }
}
function Get-HermesApiSettings {
    $command = Get-Command hermes.exe -ErrorAction SilentlyContinue
    if (-not $command) { $command = Get-Command hermes -ErrorAction SilentlyContinue }
    if (-not $command) { throw '未找到 Hermes 命令行程序。请先安装并启动 Hermes。' }
    function Get-HermesConfigValue([string]$name) {
        # Windows PowerShell turns Hermes' "Config key not set" stderr into a
        # terminating NativeCommandError when the script uses Stop globally.
        # Temporarily allow that expected exit and use the exit code below.
        $savedPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $raw = @(& $command.Source config get $name 2>$null)
            $exitCode = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $savedPreference
        }
        if ($exitCode -ne 0) { return '' }
        $value = ([string]($raw | Select-Object -First 1)).Trim()
        if ($value -match '^Config key not set:') { return '' }
        return $value
    }
    $key = Get-HermesConfigValue 'API_SERVER_KEY'
    if (-not $key) { throw 'Hermes 尚未配置 API_SERVER_KEY。请先在 Hermes 中启用 API Server。' }
    $serverHost = Get-HermesConfigValue 'API_SERVER_HOST'
    $serverPort = Get-HermesConfigValue 'API_SERVER_PORT'
    if (-not $serverHost -or $serverHost -eq '0.0.0.0') { $serverHost = '127.0.0.1' }
    if (-not $serverPort) { $serverPort = '8642' }
    @{ Key=$key; BaseUrl="http://$serverHost`:$serverPort/v1" }
}

$settings = Get-Settings
$form = [System.Windows.Forms.Form]@{ Text='Hermes 云端语音助手'; Size=[System.Drawing.Size]::new(670,440); StartPosition='CenterScreen'; Font=[System.Drawing.Font]::new('Microsoft YaHei UI',10); FormBorderStyle='FixedDialog'; MaximizeBox=$false }
$title = [System.Windows.Forms.Label]@{Text='Hermes 云端语音助手'; Location=[System.Drawing.Point]::new(25,18); AutoSize=$true; Font=[System.Drawing.Font]::new('Microsoft YaHei UI',18,[System.Drawing.FontStyle]::Bold)}; $form.Controls.Add($title)
$sub = [System.Windows.Forms.Label]@{Text='麦克风 → 云端识别 → Hermes 执行 → 云端语音回复'; Location=[System.Drawing.Point]::new(28,58); AutoSize=$true}; $form.Controls.Add($sub)
function Add-Input($caption,$value,$y,$password=$false) {
    $label=[System.Windows.Forms.Label]@{Text=$caption; Location=[System.Drawing.Point]::new(28,$y+5); Size=[System.Drawing.Size]::new(155,25)}; $form.Controls.Add($label)
    $box=[System.Windows.Forms.TextBox]@{Text=$value; Location=[System.Drawing.Point]::new(185,$y); Size=[System.Drawing.Size]::new(435,30); UseSystemPasswordChar=$password}; $form.Controls.Add($box); $box
}
$hermesUrl=Add-Input 'Hermes 服务地址' $settings.HermesBaseUrl 98
$hermesKey=Add-Input 'Hermes API 密钥' $settings.HermesKey 143 $true
$audioUrl=Add-Input '云端语音网关' $settings.AudioBaseUrl 188
$keyFile=Add-Input '云端语音密钥文件' $settings.KeyFile 233
$status=[System.Windows.Forms.Label]@{Location=[System.Drawing.Point]::new(28,284); Size=[System.Drawing.Size]::new(590,52); ForeColor=[System.Drawing.Color]::DimGray}; $form.Controls.Add($status)
function Read-Settings { @{ HermesBaseUrl=$hermesUrl.Text.Trim(); HermesKey=$hermesKey.Text.Trim(); AudioBaseUrl=$audioUrl.Text.Trim(); KeyFile=$keyFile.Text.Trim() } }
function Refresh-Status { $p=Get-AgentProcess; if($p){$status.Text="状态：运行中（进程 $($p.Id)）。关闭本窗口不会停止服务。";$status.ForeColor=[System.Drawing.Color]::ForestGreen}else{$status.Text='状态：未启动。请先确认 Hermes API 服务已运行。';$status.ForeColor=[System.Drawing.Color]::DimGray} }
function Add-Button($text,$x,$width,$action) { $b=[System.Windows.Forms.Button]@{Text=$text;Location=[System.Drawing.Point]::new($x,355);Size=[System.Drawing.Size]::new($width,42)};$b.Add_Click($action);$form.Controls.Add($b);$b }
Add-Button '保存配置' 28 100 { Save-Settings (Read-Settings); $status.Text='配置已保存。Hermes 密钥已用当前 Windows 用户加密。';$status.ForeColor=[System.Drawing.Color]::RoyalBlue } | Out-Null
Add-Button '自动获取 Hermes' 133 125 {
    try {
        $detected=Get-HermesApiSettings
        $hermesUrl.Text=$detected.BaseUrl
        $hermesKey.Text=$detected.Key
        $status.Text='已从本机 Hermes 配置读取服务地址和 API 密钥。'
        $status.ForeColor=[System.Drawing.Color]::ForestGreen
    } catch {[System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'自动获取失败','OK','Error')|Out-Null}
} | Out-Null
Add-Button '一键启动语音助手' 263 165 {
    try {
        $v=Read-Settings
        if(!$v.HermesKey){throw '请填写 Hermes API 密钥。'}
        if(!(Test-Path $v.KeyFile)){throw "找不到云端语音密钥文件：$($v.KeyFile)"}
        if(Get-AgentProcess){throw '语音助手已经在运行。'}
        Save-Settings $v
        $env:HERMES_API_KEY=$v.HermesKey
        $env:HERMES_BASE_URL=$v.HermesBaseUrl
        $p=Start-Process powershell.exe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-NoExit','-File',"$projectRoot\scripts\start_hermes_cloud_audio.ps1",'-KeyFile',$v.KeyFile,'-AudioBaseUrl',$v.AudioBaseUrl) -WorkingDirectory $projectRoot -PassThru
        New-Item -ItemType Directory -Force $stateDir|Out-Null
        Set-Content $pidPath $p.Id -Encoding ascii
        Start-Sleep -Milliseconds 500
        Refresh-Status
    } catch {[System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'无法启动','OK','Error')|Out-Null}
} | Out-Null
Add-Button '停止服务' 433 90 { $p=Get-AgentProcess;if($p){Stop-Process -Id $p.Id -Force};Remove-Item $pidPath -Force -ErrorAction SilentlyContinue;Refresh-Status } | Out-Null
Add-Button '语音自检' 528 92 {
    try {$v=Read-Settings;if(!(Test-Path $v.KeyFile)){throw "找不到云端语音密钥文件：$($v.KeyFile)"};$env:SUB2API_AUDIO_KEY_FILE=$v.KeyFile;$env:SUB2API_AUDIO_BASE_URL=$v.AudioBaseUrl;$r=& uv run python "$projectRoot\scripts\sub2api_audio_smoke_test.py" 2>&1;if($LASTEXITCODE -ne 0){throw ($r|Out-String)};$status.Text="自检通过：$($r|Out-String)";$status.ForeColor=[System.Drawing.Color]::ForestGreen}catch{[System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'自检失败','OK','Error')|Out-Null}
} | Out-Null
$form.Add_Shown({
    try {
        $detected=Get-HermesApiSettings
        if (-not $hermesKey.Text) { $hermesKey.Text=$detected.Key }
        if (-not $hermesUrl.Text -or $hermesUrl.Text -eq 'http://127.0.0.1:8642/v1') { $hermesUrl.Text=$detected.BaseUrl }
    } catch { }
    Refresh-Status
})
[void]$form.ShowDialog()



