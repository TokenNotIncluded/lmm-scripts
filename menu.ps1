# PowerShell 5.1+. Generated with UTF-8 BOM for Chinese text on Windows.
[CmdletBinding()]
param([switch]$Help)
$ErrorActionPreference = 'Stop'
if ($Help) { Write-Output 'LMM menu: .\menu.ps1 [-Help]. Interactive terminal required.'; exit 0 }
$hashes = @{
  'pi.ps1' = '64d39c29e77d7db50fb62ca306f998e24a1839640710c147ead900179c7f40ac'
  'dsh.ps1' = '163a5e60322869b5ad55dc9eb918f0acab25fdb8301bfbba026cdd13fd88f0f7'
  'lmm.ps1' = 'ce77455667245f02adbb25c4a9d36b1ba9c05e0fdc4b7466cd84e08d13397d69'
  'lmm-use.ps1' = 'ac137e30b6609580cb6ee4fbb60ed77ed01ec6153b733140540d5bc38d9179c1'
}
$network = 'auto'
$root = $env:LMM_INSTALL_ROOT
if (!$root) { $root = Join-Path $env:LOCALAPPDATA 'lmm-tools' }
$work = Join-Path ([IO.Path]::GetTempPath()) ('lmm-menu-' + [Guid]::NewGuid().ToString('N'))
$engine = (Get-Process -Id $PID).Path
$oldProtocol = [Net.ServicePointManager]::SecurityProtocol
function Ask([string]$Prompt) {
  $value = Read-Host $Prompt
  if ($null -eq $value) { throw '输入已关闭，请在交互终端运行。' }
  return $value.Trim()
}
function Fetch-Script([string]$Name) {
  if (!$hashes.ContainsKey($Name)) { throw 'Unknown script' }
  $path = Join-Path $work $Name
  if ((Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -eq $hashes[$Name])) { return $path }
  Write-Host '正在获取并校验安装程序（下载慢时会重试）…'
  foreach ($url in @("https://api.lmm.best/scripts/$Name", "https://raw.githubusercontent.com/TokenNotIncluded/lmm-scripts/95c162c2031ecba34942b2a91631c1ec1f6f3d05/$Name")) {
    for ($attempt = 1; $attempt -le 3; $attempt++) {
      try {
        Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $path -TimeoutSec 120 -ErrorAction Stop
        if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $hashes[$Name]) { throw '文件版本或校验不匹配' }
        return $path
      } catch { Write-Host ("下载未完成：{0}" -f $_.Exception.Message); if ($attempt -lt 3) { Start-Sleep -Seconds 2 } }
    }
  }
  throw '下载失败；未执行任何未校验的文件。请检查网络后重试。'
}
function Run-Script([string]$Name, [string[]]$Arguments) {
  try {
    $path = Fetch-Script $Name
    & $engine -NoProfile -ExecutionPolicy Bypass -File $path @Arguments
    if ($LASTEXITCODE -eq 0) { Write-Host '操作完成。' }
    else { Write-Host "操作退出，状态码 $LASTEXITCODE。请查看上方提示；可以切换网络后重试。" }
  } catch { Write-Host $_.Exception.Message -ForegroundColor Red }
}
function Show-Help([string]$Tool) {
  switch ($Tool) {
    pi { Write-Host 'Pi：启动后输入 /login，选择 LMM 并完成浏览器授权；再用 /model 选择模型。' }
    dsh { Write-Host 'DSH：打开启动时提示的网址，在 Settings -> Models 的 LMM 卡片选择 Sign in with LMM。' }
    lmm { Write-Host 'LMM CLI 是开发预览版。支持目录、状态、诊断、登录和模型列表；setup 目前只生成计划，不会安装应用。' }
  }
  Write-Host "安装位置：$root"
  Write-Host '默认不修改 PATH；以后可以重新运行菜单启动。'
}
try {
  if ([Console]::IsInputRedirected) { throw '需要交互终端。请下载菜单后用 PowerShell -File 执行，不要重定向输入。' }
  [Net.ServicePointManager]::SecurityProtocol = $oldProtocol -bor [Net.SecurityProtocolType]::Tls12
  [void](New-Item -ItemType Directory -Path $work)
  :main while ($true) {
    Write-Host "`n======== LMM 工具菜单 ========"
    Write-Host "1  Pi Coding Agent`n2  DSH + LMM 插件`n3  LMM CLI（开发预览）`n4  下载网络（当前：$network）`n0  退出"
    switch (Ask '输入数字') {
      '0' { break main }
      '4' {
        Write-Host '1 自动选择  2 官方源  3 国内镜像'
        switch (Ask '选择') { '1' { $network='auto' }; '2' { $network='official' }; '3' { $network='china' }; default { Write-Host '无效选择。' } }
        continue main
      }
      '1' { $tool='pi' }; '2' { $tool='dsh' }; '3' { $tool='lmm' }
      default { Write-Host '请输入菜单中的数字。'; continue main }
    }
    :actions while ($true) {
      Write-Host "`n-- $tool --`n1  安装 / 修复`n2  更新到菜单维护的版本`n3  检查安装环境`n4  启动 / 使用`n5  登录与使用说明`n0  返回"
      switch (Ask '输入数字') {
        '0' { break actions }
        '1' { Run-Script "$tool.ps1" @('-Network',$network) }
        '2' { Run-Script "$tool.ps1" @('-Network',$network,'-Update') }
        '3' { Run-Script "$tool.ps1" @('-Check') }
        '5' { Show-Help $tool }
        '4' {
          if ($tool -eq 'lmm') {
            Write-Host "1 应用目录  2 状态  3 诊断  4 安装计划（不执行）`n5 登录 LMM  6 模型列表  7 退出登录  0 返回"
            $actions = @{'1'='catalog';'2'='status';'3'='doctor';'4'='plan';'5'='login';'6'='models';'7'='logout'}
            $choice=Ask '选择'
            if ($actions.ContainsKey($choice)) { Run-Script 'lmm-use.ps1' @('-Command',$actions[$choice]) }
            elseif ($choice -ne '0') { Write-Host '无效选择。' }
          } else {
            $launcher = Join-Path $root "bin\$tool.cmd"
            if (Test-Path -LiteralPath $launcher) {
              Show-Help $tool
              if ($tool -eq 'dsh') { & $launcher --profile web } else { & $launcher }
              Write-Host '已返回菜单。'
            } else { Write-Host '尚未安装，请先选择 1。' }
          }
        }
        default { Write-Host '请输入菜单中的数字。' }
      }
    }
  }
} catch { Write-Host $_.Exception.Message -ForegroundColor Red; exit 1 }
finally {
  [Net.ServicePointManager]::SecurityProtocol = $oldProtocol
  if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
}
