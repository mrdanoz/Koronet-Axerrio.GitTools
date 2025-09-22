function _GetUserConfigPath {
        if ($IsWindows) {
            $base = Join-Path $env:APPDATA 'KXGT'
        } else {
            $thishome = $env:HOME
            $base = Join-Path (Join-Path $thishome '.config') 'kxgt'
        }
        if (-not (Test-Path $base)) { New-Item -ItemType Directory -Path $base -ErrorAction SilentlyContinue | Out-Null }
        return (Join-Path $base 'kxgt.config.json')
    }

