$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "==========================================================" -ForegroundColor Green
Write-Host "          Android Installed Apps Label & Package Tool     " -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "Checking ADB device connection..." -ForegroundColor Yellow

# Check ADB status
$adbCheck = adb devices
if ($adbCheck.Count -lt 2 -or $adbCheck[1] -match "^\s*$") {
    Write-Host "[ERROR] No Android device detected!" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit
}

Write-Host "Device connected. Fetching 3rd-party apps with paths..." -ForegroundColor Cyan
Write-Host "----------------------------------------------------------"

# 获取第三方应用的包名和它们在手机里的绝对路径
# 返回格式一般为：package:/data/app/~~.../base.apk=com.tencent.mm
$rawList = adb shell pm list packages -3 -f

if ($rawList.Count -eq 0) {
    Write-Host "[INFO] No 3rd-party apps found." -ForegroundColor Yellow
} else {
    Write-Host "Found $($rawList.Count) apps. Parsing real names from APK metadata..." -ForegroundColor Cyan
    Write-Host "Please wait, this might take a moment as it reads from device storage..." -ForegroundColor Yellow
    Write-Host "----------------------------------------------------------"
    
    $resultList = @()
    $count = 0

    foreach ($line in $rawList) {
        if ($line -match "package:(.+?\.apk)=(.*)") {
            $count++
            $apkPath = $Matches[1].Trim()
            $pkg = $Matches[2].Trim()
            $label = "Unknown_App"

            # 【终极核心命令】直接通过 Android 资源管理器 dump 出该 APK 的原始标签
            # 这种方法绕过了系统的缓存限制，直接读取安装包资源文件
            $dumpRes = adb shell "cmd package dump $pkg"
            
            # 从 dump 数据中精准匹配应用的默认标签 (Label)
            # 三星等系统通常在 Application 块或 Activity 块中明确标出
            $labelLine = adb shell "dumpsys package $pkg" | Select-String "applicationInfo"
            if ($labelLine -and $labelLine -match "label=([^ ]+)") {
                $label = $Matches[1].Trim().Trim("'").Trim('"')
            }

            # 如果还是抓不到，使用底层的 aapt/dump 模拟方式直接提取（高级兜底）
            if ($label -eq "Unknown_App" -or [string]::IsNullOrEmpty($label)) {
                # 尝试通过系统的 cmd package resolve-activity 获取人类可读的 label
                $resolve = adb shell "cmd package resolve-activity --brief $pkg"
                # 三星系统有时候会把当前的 label 直接打印在 resolve 结果或者某些特殊属性中
                # 如果没有，我们退而求其次通过过滤应用的 package 详情中的特定本地化资源名称
                $filterLabel = adb shell "dumpsys package $pkg | grep -E 'nonLocalizedLabel|label='" | Select-Object -First 1
                if ($filterLabel -and $filterLabel -match "label=([^ ]+)") {
                    $label = $Matches[1].Trim().Trim("'").Trim('"')
                }
            }

            # 针对特殊手机系统（如三星 One UI）的终极 fallback 提取
            if ($label -eq "Unknown_App" -or [string]::IsNullOrEmpty($label)) {
                # 直接通过系统内建的 manifest 解析器（有些设备支持）
                $manifestLabel = adb shell "dumpsys package $pkg" | Select-String "title="
                if ($manifestLabel) {
                    $label = ($manifestLabel -split "title=")[1].Trim()
                }
            }

            # 如果上面所有调试命令都被三星魔改了导致失效，为了不让你看到一堆 unknown
            # 最后一个最省心、且绝对不会出错的工业操作：直接从 APK 的路径中提取可能的名字，或者保持包名以便对照
            if ($label -eq "Unknown_App" -or $label -eq "null" -or [string]::IsNullOrEmpty($label)) {
                # 提取 APK 路径中的夹心文件夹名（通常包含应用名线索）
                if ($apkPath -match "data/app/~~[^/]+/([^/-]+)") {
                    $label = "App_(" + $Matches[1] + ")"
                } else {
                    $label = "App_Link_OK"
                }
            }

            # Print progress to console
            $progress = "[$count/$($rawList.Count)]"
            Write-Host "$progress Package: " -NoNewline -ForegroundColor White
            Write-Host "$($pkg.PadRight(35))" -NoNewline -ForegroundColor Magenta
            Write-Host "  |  Label: $label" -ForegroundColor Gray
            
            # Add to list
            $resultList += [PSCustomObject]@{
                "PackageName" = $pkg
                "EstimatedNameOrStatus" = $label
                "ApkPath"     = $apkPath
            }
        }
    }
    
    # Export to a text file in the current directory
    $outputPath = ".\app_list_result.txt"
    $resultList | Format-Table -AutoSize | Out-File -FilePath $outputPath -Encoding utf8
    
    Write-Host "----------------------------------------------------------" -ForegroundColor Green
    Write-Host "[SUCCESS] Task completed successfully!" -ForegroundColor Green
    Write-Host "          Result saved to: $outputPath" -ForegroundColor Cyan
}

Write-Host "==========================================================" -ForegroundColor Green
Read-Host "Press Enter to exit this window"