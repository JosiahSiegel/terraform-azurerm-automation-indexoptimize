$RepoRoot = Split-Path -Parent $PSScriptRoot
$ScriptPath = Join-Path -Path $RepoRoot -ChildPath 'scripts/IndexOptimize.ps1'
$ScriptText = Get-Content -Path $ScriptPath -Raw
$ParseTokens = $null
$ParseErrors = $null
$ScriptAst = [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$ParseTokens, [ref]$ParseErrors)

function Convert-TestOptionalIndexOptimizeNumbers {
    param(
        [string]$MaxDOP = '',
        [string]$FillFactor = '',
        [string]$TimeLimitMinutes = ''
    )

    $ParsedTimeLimitMinutes = 0
    $EffectiveTimeLimitMinutes = ([int]::TryParse($TimeLimitMinutes, [ref]$ParsedTimeLimitMinutes) -and $ParsedTimeLimitMinutes -ge 0) ? $ParsedTimeLimitMinutes : 120
    $IndexOptimizeTimeLimitSeconds = $EffectiveTimeLimitMinutes * 60
    $SqlCommandTimeoutSeconds = $IndexOptimizeTimeLimitSeconds + 600

    $ParsedMaxDOP = 0
    $EffectiveMaxDOP = ([int]::TryParse($MaxDOP, [ref]$ParsedMaxDOP) -and $ParsedMaxDOP -ge 0) ? $ParsedMaxDOP : $null
    $ParsedFillFactor = 0
    $EffectiveFillFactor = ([int]::TryParse($FillFactor, [ref]$ParsedFillFactor) -and $ParsedFillFactor -ge 0) ? $ParsedFillFactor : $null

    [pscustomobject]@{
        EffectiveMaxDOP       = $EffectiveMaxDOP
        EffectiveFillFactor   = $EffectiveFillFactor
        EffectiveMinutes      = $EffectiveTimeLimitMinutes
        OlaSeconds            = $IndexOptimizeTimeLimitSeconds
        CommandTimeoutSeconds = $SqlCommandTimeoutSeconds
        OptMaxDOP             = ($null -ne $EffectiveMaxDOP) ? "@MaxDOP                          = $EffectiveMaxDOP," : ''
        OptFillFactor         = ($null -ne $EffectiveFillFactor) ? "@FillFactor                      = $EffectiveFillFactor," : ''
    }
}

Describe 'IndexOptimize.ps1 local verification' {
    Context 'PowerShell syntax and static production checks' {
        It 'parses with no syntax errors' {
            $ParseErrors.Count | Should Be 0
        }

        It 'declares optional numeric Automation parameters as strings' {
            foreach ($name in @('MaxDOP', 'FillFactor', 'TimeLimitMinutes')) {
                $paramAst = $ScriptAst.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq $name }
                $paramAst.StaticType.FullName | Should Be 'System.String'
            }
        }

        It 'passes converted seconds to Ola TimeLimit and parsed variables to MaxDOP and FillFactor' {
            $ScriptText | Should Match '\$IndexOptimizeTimeLimitSeconds\s*=\s*\$EffectiveTimeLimitMinutes \* 60'
            $ScriptText | Should Match '@TimeLimit\s+= \$IndexOptimizeTimeLimitSeconds,'
            $ScriptText | Should Match '@MaxDOP\s+= \$EffectiveMaxDOP,'
            $ScriptText | Should Match '@FillFactor\s+= \$EffectiveFillFactor,'
        }
    }

    Context 'Optional numeric parameter parsing' {
        It 'omits blank MaxDOP and FillFactor values' {
            $result = Convert-TestOptionalIndexOptimizeNumbers -MaxDOP '' -FillFactor ''
            $result.EffectiveMaxDOP | Should Be $null
            $result.EffectiveFillFactor | Should Be $null
            $result.OptMaxDOP | Should Be ''
            $result.OptFillFactor | Should Be ''
        }

        It 'omits invalid and negative MaxDOP and FillFactor values' {
            $invalid = Convert-TestOptionalIndexOptimizeNumbers -MaxDOP 'invalid' -FillFactor 'bad'
            $negative = Convert-TestOptionalIndexOptimizeNumbers -MaxDOP '-1' -FillFactor '-1'
            $invalid.EffectiveMaxDOP | Should Be $null
            $invalid.EffectiveFillFactor | Should Be $null
            $negative.EffectiveMaxDOP | Should Be $null
            $negative.EffectiveFillFactor | Should Be $null
        }

        It 'passes non-negative MaxDOP values including zero' {
            (Convert-TestOptionalIndexOptimizeNumbers -MaxDOP '0').OptMaxDOP | Should Be '@MaxDOP                          = 0,'
            (Convert-TestOptionalIndexOptimizeNumbers -MaxDOP '4').OptMaxDOP | Should Be '@MaxDOP                          = 4,'
        }

        It 'passes non-negative FillFactor values including explicit zero for Ola validation' {
            (Convert-TestOptionalIndexOptimizeNumbers -FillFactor '0').OptFillFactor | Should Be '@FillFactor                      = 0,'
            (Convert-TestOptionalIndexOptimizeNumbers -FillFactor '90').OptFillFactor | Should Be '@FillFactor                      = 90,'
        }

        It 'converts TimeLimitMinutes from minutes to Ola seconds' {
            $result = Convert-TestOptionalIndexOptimizeNumbers -TimeLimitMinutes '60'
            $result.EffectiveMinutes | Should Be 60
            $result.OlaSeconds | Should Be 3600
            $result.CommandTimeoutSeconds | Should Be 4200
        }

        It 'defaults blank, invalid, and negative TimeLimitMinutes to 120 minutes' {
            foreach ($value in @('', 'invalid', '-1')) {
                $result = Convert-TestOptionalIndexOptimizeNumbers -TimeLimitMinutes $value
                $result.EffectiveMinutes | Should Be 120
                $result.OlaSeconds | Should Be 7200
            }
        }
    }
}
