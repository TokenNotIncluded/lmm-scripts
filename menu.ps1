# PowerShell 5.1+. Generated with UTF-8 BOM.
[CmdletBinding()]
param([switch]$Help,[switch]$List)
$ErrorActionPreference='Stop'
$tools=@(
  @{Name='pi';Label='Pi + LMM';Kind='managed'},
  @{Name='dsh';Label='DSH + LMM';Kind='managed'},
  @{Name='lmm';Label='LMM CLI (preview)';Kind='managed'},
  @{Name='codex';Label='Codex CLI';Kind='external'},
  @{Name='claude-code';Label='Claude Code';Kind='external'},
  @{Name='cc-switch';Label='CC Switch';Kind='desktop'},
  @{Name='clash-verge-rev';Label='Clash Verge Rev';Kind='desktop'}
)
function Show-Tools { for ($i=0; $i -lt $tools.Count; $i++) { Write-Output "$($i+1)  $($tools[$i].Label)" } }
if ($Help) { Write-Output 'LMM menu: .\menu.ps1 [-List]'; exit 0 }
if ($List) { Show-Tools; exit 0 }
$hashes=@{
  'pi.ps1' = 'e64cfb40182d8edbf80c17a28c5ce3cc5e22c1179b52e94a8ea140996ab3de9b'
  'dsh.ps1' = 'a0c9ff55a3445bcacf35b64e6a1b96e65a28aebf45fd1c3c221a464efa0dedf7'
  'lmm.ps1' = '6df5d2ffe8ad8b65a1bcf60570f4eb086dbbd8c22f1f5dbc5e99359d97b61c0e'
  'codex.ps1' = '79ee4587b25a4e8b45bcf035a9bed1b8abee6d2f98552eb4defc11c183e642ab'
  'claude-code.ps1' = 'ecf5df65c96ba8c4f6265264d2ba381e942eb09fe262d769ab607d4c1d592ec6'
  'cc-switch.ps1' = '2f0270b3261d22f20d8f01fb4fde8c5d588aaa61499f5b3a89916727c7e742cc'
  'clash-verge-rev.ps1' = '0a3b5a66631082e96eeabdc8c9b242302e9bc1a42438f2517e2658d87fb814bf'
  'lmm-use.ps1' = 'ac137e30b6609580cb6ee4fbb60ed77ed01ec6153b733140540d5bc38d9179c1'
}
$network='auto'; $root=$env:LMM_INSTALL_ROOT
if (!$root) { $root=Join-Path $env:LOCALAPPDATA 'lmm-tools' }
$work=Join-Path ([IO.Path]::GetTempPath()) ('lmm-menu-'+[Guid]::NewGuid().ToString('N'))
$engine=(Get-Process -Id $PID).Path
$oldProtocol=[Net.ServicePointManager]::SecurityProtocol
function Ask([string]$Prompt) { $value=Read-Host $Prompt; if ($null -eq $value) { throw '需要交互终端。' }; return $value.Trim() }
function Fetch-Script([string]$Name) {
  if (!$hashes.ContainsKey($Name)) { throw 'Unknown script' }
  $path=Join-Path $work $Name
  if ((Test-Path -LiteralPath $path) -and (Get-FileHash -LiteralPath $path).Hash -eq $hashes[$Name]) { return $path }
  foreach ($url in @("https://api.lmm.best/scripts/$Name","https://raw.githubusercontent.com/TokenNotIncluded/lmm-scripts/1d2fb99abe87d8af2cd3a17489cadd32cabcc189/$Name")) {
    for ($attempt=1; $attempt -le 3; $attempt++) {
      try {
        Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $path -TimeoutSec 120
        if ((Get-FileHash -LiteralPath $path).Hash -ne $hashes[$Name]) { throw '版本不匹配' }
        return $path
      } catch { if ($attempt -lt 3) { Start-Sleep -Seconds 1 } }
    }
  }
  throw "下载失败或版本不匹配：$Name"
}
function Run-Script([string]$Name,[string[]]$Arguments) {
  try {
    $path=Fetch-Script $Name
    & $engine -NoProfile -ExecutionPolicy Bypass -File $path @Arguments
    if ($LASTEXITCODE -ne 0) { Write-Host "退出码 $LASTEXITCODE，请查看上方错误。" }
  } catch { Write-Host $_.Exception.Message }
}
function Show-Help([string]$Name) {
  switch ($Name) {
    pi { Write-Host 'pi → /login → LMM → /model。' }
    dsh { Write-Host 'dsh web → Settings → Models → LMM。' }
    lmm { Write-Host 'LMM CLI 为预览版，setup 只生成计划。' }
    codex { Write-Host '运行 codex，按官方提示登录；使用上游安装位置与更新策略。' }
    claude-code { Write-Host '运行 claude，按官方提示登录；使用上游安装位置与更新策略。' }
    default { Write-Host '桌面应用按系统安装，不自动配置账号、订阅或启用代理。' }
  }
}
try {
  if ([Console]::IsInputRedirected) { throw '需要交互终端；自动化请直接执行工具脚本。' }
  [Net.ServicePointManager]::SecurityProtocol=$oldProtocol -bor [Net.SecurityProtocolType]::Tls12
  New-Item -ItemType Directory -Path $work | Out-Null
  :main while ($true) {
    Write-Host "`nLMM 工具"; Show-Tools; Write-Host "n 下载网络（$network）`n0 退出"
    $choice=Ask '选择'
    if ($choice -eq '0') { break }
    if ($choice -eq 'n') {
      Write-Host '1 自动  2 官方  3 国内镜像'
      switch (Ask '选择') { '1' { $network='auto' }; '2' { $network='official' }; '3' { $network='china' } }
      continue
    }
    $index=0
    if (![int]::TryParse($choice,[ref]$index) -or $index -lt 1 -or $index -gt $tools.Count) { Write-Host '无效选择。'; continue }
    $item=$tools[$index-1]; $tool=$item.Name
    :actions while ($true) {
      Write-Host "`n$($item.Label)`n1 安装  2 更新  3 检查  4 启动  5 使用说明"
      if ($item.Kind -ne 'managed') { Write-Host '6 预览安装方案' }
      Write-Host '0 返回'
      switch (Ask '选择') {
        '0' { break actions }
        '1' { Run-Script "$tool.ps1" @('-Network',$network) }
        '2' { Run-Script "$tool.ps1" @('-Network',$network,'-Update') }
        '3' { Run-Script "$tool.ps1" @('-Check') }
        '5' { Show-Help $tool }
        '6' { if ($item.Kind -ne 'managed') { Run-Script "$tool.ps1" @('-DryRun') } }
        '4' {
          if ($tool -eq 'lmm') {
            Write-Host "1 目录  2 状态  3 诊断  4 安装计划`n5 登录  6 模型  7 退出登录  0 返回"
            $actions=@{'1'='catalog';'2'='status';'3'='doctor';'4'='plan';'5'='login';'6'='models';'7'='logout'}
            $action=Ask '选择'
            if ($actions.ContainsKey($action)) { Run-Script 'lmm-use.ps1' @('-Command',$actions[$action]) }
          } elseif ($item.Kind -ne 'managed') { Run-Script "$tool.ps1" @('-Network',$network,'-Launch') }
          else {
            $launcher=Join-Path $root "bin\$tool.cmd"
            if (Test-Path -LiteralPath $launcher) { if ($tool -eq 'dsh') { & $launcher --profile web } else { & $launcher } }
            else { Write-Host '请先安装。' }
          }
        }
        default { Write-Host '无效选择。' }
      }
    }
  }
} catch { Write-Host $_.Exception.Message; exit 1 }
finally {
  [Net.ServicePointManager]::SecurityProtocol=$oldProtocol
  if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
}
