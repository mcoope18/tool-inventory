# Builds assets/web3d/viewer.html: the app's 3D viewer as ONE self-contained page.
# The page's own modules (web3d/*.js) are embedded as data: URLs in its import map, so the app
# can load it with WebViewController.loadHtmlString(). three.js still loads from the jsDelivr CDN.
#
# Run from the project folder after editing anything in web3d/:
#   powershell -ExecutionPolicy Bypass -File tool\build_web3d.ps1

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$src = Join-Path $root 'web3d'
$out = Join-Path $root 'assets\web3d'
New-Item -ItemType Directory -Force $out | Out-Null

function DataUrl($file) {
  $bytes = [IO.File]::ReadAllBytes((Join-Path $src $file))
  'data:text/javascript;base64,' + [Convert]::ToBase64String($bytes)
}

$map = [ordered]@{
  'three'         = 'https://cdn.jsdelivr.net/npm/three@0.169.0/build/three.module.js'
  'three/addons/' = 'https://cdn.jsdelivr.net/npm/three@0.169.0/examples/jsm/'
  'builder'       = DataUrl 'builder.js'
  'toolmodels'    = DataUrl 'toolmodels.js'
  'tools'         = DataUrl 'tools.js'
  'modelfinder'   = DataUrl 'modelfinder.js'
}
$json = '{ "imports": ' + ($map | ConvertTo-Json -Compress) + ' }'

$html = [IO.File]::ReadAllText((Join-Path $src 'viewer.src.html'))
$html = [regex]::Replace($html, '(?s)<script type="importmap">.*?</script>', "<script type=`"importmap`">$json</script>")
[IO.File]::WriteAllText((Join-Path $out 'viewer.html'), $html, (New-Object Text.UTF8Encoding $false))
"Wrote assets/web3d/viewer.html ($([math]::Round((Get-Item (Join-Path $out 'viewer.html')).Length / 1KB)) KB)"
