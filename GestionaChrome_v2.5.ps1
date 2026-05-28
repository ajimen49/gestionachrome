# ==============================================================================
# GestionaChrome v2.5
# ==============================================================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
} catch {}

# --- CONFIGURACIÓ GLOBAL ---
$script:chromePath  = Join-Path $env:LOCALAPPDATA "Google\Chrome\User Data"
$script:tempExport  = Join-Path $env:TEMP "GestionaChrome_Export"
$script:tempImport  = Join-Path $env:TEMP "GestionaChrome_Import"
$script:profileRegex = '^(Default|Profile \d+)$'
$script:metaFile     = "profiles_meta.json"

# Colors de la interfície
$colorVerd   = [System.Drawing.Color]::FromArgb(34,177,76)
$colorBlau   = [System.Drawing.Color]::FromArgb(0,123,255)
$colorVermell = [System.Drawing.Color]::FromArgb(192,57,43)

# ==============================================================================
# FUNCIONS UTILITÀRIES i DE SUPORT
# ==============================================================================

function Check-Chrome {
    if (Get-Process chrome -ErrorAction SilentlyContinue) {
        $res = [System.Windows.Forms.MessageBox]::Show(
            "Chrome està obert i per evitar errors en el procés cal tancar-lo. `n`nVols que el tanqui?",
            "GestionaChrome",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        if ($res -eq [System.Windows.Forms.DialogResult]::Yes) {
            Stop-Process -Name chrome -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
            return $true
        }
        return $false
    }
    return $true
}

function Ensure-Dir($path) {
    if (-not (Test-Path $path)) { New-Item -Path $path -ItemType Directory | Out-Null }
}

function Copy-Safe($src, $dst) {
    if (-not (Test-Path $src)) { return }
    Ensure-Dir $dst
    $item = Get-Item $src -ErrorAction SilentlyContinue
    if (-not $item) { return }

    for ($i = 0; $i -lt 3; $i++) {
        try {
            if ($item.PSIsContainer) {
                $target = Join-Path $dst $item.Name
                if (Test-Path $target) { Remove-Item $target -Recurse -Force -ErrorAction SilentlyContinue }
                Copy-Item -Path $src -Destination $target -Recurse -Force -ErrorAction Stop
            } else {
                Copy-Item -Path $src -Destination (Join-Path $dst $item.Name) -Force -ErrorAction Stop
            }
            return
        } catch {
            Start-Sleep -Milliseconds 300
        }
    }
}

function Copy-BookmarksSafe($srcProfile, $dstProfile) {
    $b    = Join-Path $srcProfile "Bookmarks"
    $bBak = Join-Path $srcProfile "Bookmarks.bak"

    if (Test-Path $b) {
        Copy-Safe $b    $dstProfile
        Copy-Safe $bBak $dstProfile
    } elseif (Test-Path $bBak) {
        Ensure-Dir $dstProfile
        Copy-Item -Path $bBak -Destination (Join-Path $dstProfile "Bookmarks") -Force
    }
}

function Get-ChromeProfileFolders($basePath) {
    if (-not (Test-Path $basePath)) { return @() }
    return @(
        Get-ChildItem -Path $basePath -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match $script:profileRegex } |
            Sort-Object Name
    )
}

function Get-ProfileMeta($basePath) {
    $meta   = @{}
    $lsPath = Join-Path $basePath "Local State"
    $localStateProfiles = @{}

    if (Test-Path $lsPath) {
        try {
            $ls = Get-Content $lsPath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($prop in $ls.profile.info_cache.PSObject.Properties) {
                $localStateProfiles[$prop.Name] = @{
                    name  = if ($prop.Value.name) { $prop.Value.name } else { $prop.Name }
                    email = if ($prop.Value.user_name) { $prop.Value.user_name } else { "" }
                }
            }
        } catch {}
    }

    $profiles = Get-ChromeProfileFolders $basePath
    foreach ($p in $profiles) {
        $id       = $p.Name
        $prefPath = Join-Path $p.FullName "Preferences"

        $meta[$id] = @{
            name                   = if ($localStateProfiles[$id]) { $localStateProfiles[$id].name } else { $id }
            email                  = if ($localStateProfiles[$id]) { $localStateProfiles[$id].email } else { "" }
            profile_name           = ""
            account_name           = ""
            avatar_index           = 0
            using_default_avatar   = $true
            using_gaia_avatar      = $false
            gaia_name              = ""
            gaia_given_name        = ""
            is_using_gaia_picture  = $false
            profile_color_seed     = 0
        }

        if (Test-Path $prefPath) {
            try {
                $pref = Get-Content $prefPath -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($pref.profile) {
                    if ($pref.profile.name) { $meta[$id].profile_name = $pref.profile.name }
                    if ($pref.profile.gaia_name) { $meta[$id].account_name = $pref.profile.gaia_name }
                    if ($null -ne $pref.profile.avatar_index) { $meta[$id].avatar_index = $pref.profile.avatar_index }
                    if ($null -ne $pref.profile.using_default_avatar) { $meta[$id].using_default_avatar = $pref.profile.using_default_avatar }
                    if ($null -ne $pref.profile.using_gaia_avatar) { $meta[$id].using_gaia_avatar = $pref.profile.using_gaia_avatar }
                    if ($pref.profile.gaia_name) { $meta[$id].gaia_name = $pref.profile.gaia_name }
                    if ($pref.profile.gaia_given_name) { $meta[$id].gaia_given_name = $pref.profile.gaia_given_name }
                    if ($null -ne $pref.profile.profile_color_seed) { $meta[$id].profile_color_seed = $pref.profile.profile_color_seed }
                    if ($null -ne $pref.profile.is_using_gaia_picture) { $meta[$id].is_using_gaia_picture = $pref.profile.is_using_gaia_picture }
                }
            } catch {}
        }
    }
    return $meta
}

function Get-DisplayProfileName($metaItem) {
    if ($metaItem.account_name) { return [string]$metaItem.account_name }
    if ($metaItem.gaia_name) { return [string]$metaItem.gaia_name }
    if ($metaItem.email) { return [string]$metaItem.email }
    if ($metaItem.profile_name) { return [string]$metaItem.profile_name }
    return "Perfil Chrome"
}

function Merge-LocalStateMinim($importedMetaMap, $selectedIds, $destChromePath, $importedLSPath) {
    $lsDest = Join-Path $destChromePath "Local State"
    $importedLS = $null
    if ($importedLSPath -and (Test-Path $importedLSPath)) {
        try { $importedLS = Get-Content $importedLSPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
    }

    if (Test-Path $lsDest) {
        try   { $ls = Get-Content $lsDest -Raw -Encoding UTF8 | ConvertFrom-Json }
        catch { $ls = [PSCustomObject]@{ profile = [PSCustomObject]@{ info_cache = [PSCustomObject]@{} } } }
    } else {
        $ls = [PSCustomObject]@{ profile = [PSCustomObject]@{ info_cache = [PSCustomObject]@{} } }
    }

    if (-not $ls.PSObject.Properties["profile"]) {
        $ls | Add-Member -MemberType NoteProperty -Name "profile" -Value ([PSCustomObject]@{ info_cache = [PSCustomObject]@{} })
    }
    if (-not $ls.profile.PSObject.Properties["info_cache"]) {
        $ls.profile | Add-Member -MemberType NoteProperty -Name "info_cache" -Value ([PSCustomObject]@{})
    }

    foreach ($id in $selectedIds) {
        if ($ls.profile.info_cache.PSObject.Properties[$id]) {
            $ls.profile.info_cache.PSObject.Properties.Remove($id)
        }

        $srcEntry = $null
        if ($importedLS -and $importedLS.profile.info_cache.PSObject.Properties[$id]) {
            $srcEntry = $importedLS.profile.info_cache.$id
        }

        if ($srcEntry) {
            $entryHash = [ordered]@{}
			foreach ($prop in $srcEntry.PSObject.Properties) {
			$entryHash[$prop.Name] = $prop.Value
			}
			$entryHash["last_used"] = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
			$ls.profile.info_cache | Add-Member -MemberType NoteProperty -Name $id -Value ([PSCustomObject]$entryHash)
        } else {
            $m = $importedMetaMap[$id]
            $entry = [ordered]@{
                name                    = if ($m.name) { $m.name } else { $id }
                user_name               = if ($m.email) { $m.email } else { "" }
                last_used               = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
                avatar_icon             = "chrome://theme/IDR_PROFILE_AVATAR_$($m.avatar_index)"
                is_using_gaia_picture   = [bool]$m.is_using_gaia_picture
                using_default_avatar    = [bool]$m.using_default_avatar
                using_gaia_avatar       = [bool]$m.using_gaia_avatar
                gaia_name               = [string]$m.gaia_name
                gaia_given_name         = [string]$m.gaia_given_name
            }
            if ($m.profile_color_seed -and $m.profile_color_seed -ne 0) { $entry["profile_color_seed"] = $m.profile_color_seed }
            if ($m.is_using_gaia_picture) { $entry["gaia_picture_file_name"] = "Google Profile Picture.png" }

            $ls.profile.info_cache | Add-Member -MemberType NoteProperty -Name $id -Value ([PSCustomObject]$entry)
        }
    }

    try {
        Ensure-Dir (Split-Path $lsDest)
        $ls | ConvertTo-Json -Depth 100 | Set-Content $lsDest -Encoding UTF8
    } catch {}
}

function Test-ZipValid($zipPath, $tempDest) {
    try {
        if (Test-Path $tempDest) { Remove-Item $tempDest -Recurse -Force }
        Expand-Archive -Path $zipPath -DestinationPath $tempDest -Force

        $profiles = Get-ChromeProfileFolders $tempDest
        if ($profiles.Count -eq 0) { return $false }
        return $true
    }
    catch   { return $false }
}

$script:isBulkUpdate = $false

function Set-GridAll($grid, [bool]$checked) {
    $script:isBulkUpdate = $true
    try {
        $grid.SuspendLayout()
        foreach ($row in $grid.Rows) {
            if ($row.IsNewRow) { continue }
            if ($row.Cells["PERFIL"].ReadOnly) { continue }

            $row.Cells["PERFIL"].Value = $checked

            if ($checked) {
                if (-not $row.Cells["PREF"].ReadOnly) { $row.Cells["PREF"].Value = $true }
                if (-not $row.Cells["HIST"].ReadOnly) { $row.Cells["HIST"].Value = $true }
            } else {
                if (-not $row.Cells["PREF"].ReadOnly) { $row.Cells["PREF"].Value = $false }
                if (-not $row.Cells["HIST"].ReadOnly) { $row.Cells["HIST"].Value = $false }
            }
        }
        $grid.Refresh()
    } finally {
        $grid.ResumeLayout()
        $script:isBulkUpdate = $false
    }
}

function New-ProfileGrid {
    $g = New-Object System.Windows.Forms.DataGridView
    $g.Size                = New-Object System.Drawing.Size(800,280)
    $g.Location            = New-Object System.Drawing.Point(20,20)
    $g.AutoSizeColumnsMode = "Fill"
    $g.RowHeadersVisible   = $false
    $g.AllowUserToAddRows  = $false
    $g.SelectionMode       = "FullRowSelect"

    $g.Columns.Add("ID","ID") | Out-Null
    $g.Columns["ID"].Visible = $false

    $colP = New-Object System.Windows.Forms.DataGridViewCheckBoxColumn
    $colP.Name       = "PERFIL"
    $colP.HeaderText = "Perfil"
    $colP.Width      = 50
    $colP.AutoSizeMode = "None"
    $g.Columns.Add($colP) | Out-Null

    $g.Columns.Add("Name", "Nom perfil") | Out-Null
    $g.Columns.Add("Email","Correu")     | Out-Null

    $colPref = New-Object System.Windows.Forms.DataGridViewCheckBoxColumn
    $colPref.Name       = "PREF"
    $colPref.HeaderText = "Preferits"
    $g.Columns.Add($colPref) | Out-Null

    $colHist = New-Object System.Windows.Forms.DataGridViewCheckBoxColumn
    $colHist.Name       = "HIST"
    $colHist.HeaderText = "Historial"
    $g.Columns.Add($colHist) | Out-Null

    $g.Add_CurrentCellDirtyStateChanged({
        param($sender, $e)
        if ($sender.IsCurrentCellDirty) {
            $sender.CommitEdit([System.Windows.Forms.DataGridViewDataErrorContexts]::Commit)
        }
    })

    $g.Add_CellValueChanged({
        param($sender, $e)
        if ($script:isBulkUpdate) { return }
        if ($e.RowIndex -lt 0) { return }
        $row = $sender.Rows[$e.RowIndex]

        $iPERFIL = $sender.Columns["PERFIL"].Index
        $iPREF   = $sender.Columns["PREF"].Index
        $iHIST   = $sender.Columns["HIST"].Index

        if ($e.ColumnIndex -eq $iPREF -or $e.ColumnIndex -eq $iHIST) {
            if (([bool]$row.Cells["PREF"].Value -or [bool]$row.Cells["HIST"].Value) -and -not [bool]$row.Cells["PERFIL"].Value) {
                $row.Cells["PERFIL"].Value = $true
            }
        } elseif ($e.ColumnIndex -eq $iPERFIL) {
            if (-not [bool]$row.Cells["PERFIL"].Value) {
                $row.Cells["PREF"].Value = $false
                $row.Cells["HIST"].Value = $false
            }
        }
    })

    return $g
}

function New-ActionButton($text, $color) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text      = $text
    $b.Size      = New-Object System.Drawing.Size(200,50)
    $b.Font      = New-Object System.Drawing.Font("Segoe UI",11,[System.Drawing.FontStyle]::Bold)
    $b.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $b.BackColor = $color
    $b.ForeColor = [System.Drawing.Color]::White
    $b.FlatAppearance.BorderSize = 0
    return $b
}

# ==============================================================================
# LÒGICA PRINCIPAL ACCIONS
# ==============================================================================

function Show-ExportDialog {
    if (-not (Check-Chrome)) { return }

    if (-not (Test-Path $script:chromePath)) {
        [System.Windows.Forms.MessageBox]::Show("No s'han trobat dades de Chrome.","Error")
        return
    }

    $profileFolders = Get-ChromeProfileFolders $script:chromePath
    if ($profileFolders.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("No s'han trobat perfils de Chrome.","Error")
        return
    }

    $meta = Get-ProfileMeta $script:chromePath

    $form = New-Object System.Windows.Forms.Form
    $form.Text          = "Exportació — Selecciona perfils i dades"
    $form.Size          = New-Object System.Drawing.Size(880,580)
    $form.StartPosition = "CenterScreen"
    $form.Font          = New-Object System.Drawing.Font("Segoe UI",10)

    $grid = New-ProfileGrid

    foreach ($p in $profileFolders) {
        $id = $p.Name
        $name = if ($meta[$id]) { Get-DisplayProfileName $meta[$id] } else { $id }
        $email = if ($meta[$id]) { $meta[$id].email } else { "" }
        $grid.Rows.Add($id, $true, $name, $email, $true, $true) | Out-Null
    }

    $btnAll = New-Object System.Windows.Forms.Button
    $btnAll.Text = "MARCA-HO TOT"
    $btnAll.Size = New-Object System.Drawing.Size(160,35)
    $btnAll.Location = New-Object System.Drawing.Point(20,310)
    $btnAll.Add_Click({ Set-GridAll $grid $true })

    $btnNone = New-Object System.Windows.Forms.Button
    $btnNone.Text = "DESMARCA-HO TOT"
    $btnNone.Size = New-Object System.Drawing.Size(160,35)
    $btnNone.Location = New-Object System.Drawing.Point(190,310)
    $btnNone.Add_Click({ Set-GridAll $grid $false })

    $progress          = New-Object System.Windows.Forms.ProgressBar
    $progress.Location = New-Object System.Drawing.Point(20,370)
    $progress.Size     = New-Object System.Drawing.Size(820,20)

    $lbl          = New-Object System.Windows.Forms.Label
    $lbl.Location = New-Object System.Drawing.Point(20,400)
    $lbl.Size     = New-Object System.Drawing.Size(820,20)

    $btn          = New-ActionButton "EXPORTAR" $colorVerd
    $btn.Location = New-Object System.Drawing.Point(340,450)

    $btn.Add_Click({
        $grid.EndEdit()
        $rows = @($grid.Rows | Where-Object { [bool]$_.Cells["PERFIL"].Value })
        if ($rows.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("Selecciona almenys un perfil.")
            return
        }

        $sfd = New-Object System.Windows.Forms.SaveFileDialog
        $sfd.Filter           = "Zip (*.zip)|*.zip"
        $sfd.FileName         = "ChromeExport_$(Get-Date -Format 'dd_MM_yyyy').zip"
        $sfd.InitialDirectory = [Environment]::GetFolderPath("Desktop")
        if ($sfd.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }

        $btn.Enabled = $false
        try {
            if (Test-Path $script:tempExport) { Remove-Item $script:tempExport -Recurse -Force }
            Ensure-Dir $script:tempExport

            $metaExport = @{}
            foreach ($row in $rows) {
                $id = [string]$row.Cells["ID"].Value
                $metaExport[$id] = @{
                    name                  = [string]$row.Cells["Name"].Value
                    email                 = [string]$row.Cells["Email"].Value
                    profile_name          = $meta[$id].profile_name
                    account_name          = $meta[$id].account_name
                    avatar_index          = $meta[$id].avatar_index
                    using_default_avatar  = $meta[$id].using_default_avatar
                    using_gaia_avatar     = $meta[$id].using_gaia_avatar
                    is_using_gaia_picture = $meta[$id].is_using_gaia_picture
                    profile_color_seed    = $meta[$id].profile_color_seed
                    gaia_name             = $meta[$id].gaia_name
                    gaia_given_name       = $meta[$id].gaia_given_name
                }
            }
            $metaExport | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $script:tempExport $script:metaFile) -Encoding UTF8

            $progress.Maximum = $rows.Count
            $progress.Value = 0

            foreach ($row in $rows) {
                $id = [string]$row.Cells["ID"].Value
                $name = [string]$row.Cells["Name"].Value
                $lbl.Text = "Exportant: $name"
                $form.Refresh()

                $src = Join-Path $script:chromePath $id
                $dst = Join-Path $script:tempExport $id
                Ensure-Dir $dst

                # Còpia binària segura sense tocar res
                Copy-Safe (Join-Path $src "Preferences") $dst
                Copy-Safe (Join-Path $src "Avatars") $dst
                Copy-Safe (Join-Path $src "Google Profile Picture.png") $dst
                Copy-Safe (Join-Path $src "Profile Picture.png") $dst
                Copy-Safe (Join-Path $src "Profile Picture") $dst
                Copy-Safe (Join-Path $src "GAIA Profile Picture.png") $dst
                Copy-Safe (Join-Path $src "GAIA Picture.png") $dst

                if ([bool]$row.Cells["PREF"].Value) {
                    Copy-BookmarksSafe $src $dst
                    Copy-Safe (Join-Path $src "Favicons") $dst
                    Copy-Safe (Join-Path $src "Favicons-journal") $dst
                }

                if ([bool]$row.Cells["HIST"].Value) {
                    Copy-Safe (Join-Path $src "History") $dst
                    Copy-Safe (Join-Path $src "Visited Links") $dst
                    Copy-Safe (Join-Path $src "Top Sites") $dst
                    Copy-Safe (Join-Path $src "Shortcuts") $dst
                    if (-not [bool]$row.Cells["PREF"].Value) {
                        Copy-Safe (Join-Path $src "Favicons") $dst
                    }
                }
                $progress.Value++
            }

            if (Test-Path (Join-Path $script:chromePath "Local State")) {
                Copy-Safe (Join-Path $script:chromePath "Local State") $script:tempExport
            }

            $lbl.Text = "Comprimint..."
            $form.Refresh()

            if (Test-Path $sfd.FileName) { Remove-Item $sfd.FileName -Force }
            Compress-Archive -Path (Join-Path $script:tempExport "*") -DestinationPath $sfd.FileName -Force

            [System.Windows.Forms.MessageBox]::Show("Exportació completada!`n`n$($sfd.FileName)", "GestionaChrome")
            $form.Close()

        } catch {
            [System.Windows.Forms.MessageBox]::Show("Error durant l'exportació:`n$($_.Exception.Message)","Error")
        } finally {
            if (Test-Path $script:tempExport) { Remove-Item $script:tempExport -Recurse -Force }
            $btn.Enabled = $true
            $lbl.Text = ""
        }
    })

    $form.Controls.AddRange(@($grid,$btnAll,$btnNone,$progress,$lbl,$btn))
    $form.ShowDialog() | Out-Null
}

function Show-ImportDialog {
    if (-not (Check-Chrome)) { return }

    $ofd = New-Object System.Windows.Forms.OpenFileDialog
    $ofd.Filter = "Zip (*.zip)|*.zip"
    $ofd.Title = "Selecciona l'arxiu ZIP a importar"
    
    if ($ofd.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }

    if (-not (Test-ZipValid $ofd.FileName $script:tempImport)) {
        [System.Windows.Forms.MessageBox]::Show("El fitxer seleccionat no és un arxiu vàlid de GestionaChrome.", "Arxiu no vàlid")
        return
    }

    $importMeta = @{}
    $metaPath = Join-Path $script:tempImport $script:metaFile
    if (Test-Path $metaPath) {
        try {
            $raw = Get-Content $metaPath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($prop in $raw.PSObject.Properties) {
                $importMeta[$prop.Name] = @{
                    name                  = if ($prop.Value.name) { $prop.Value.name } else { $prop.Name }
                    email                 = if ($prop.Value.email) { $prop.Value.email } else { "" }
                    profile_name          = if ($prop.Value.profile_name) { $prop.Value.profile_name } else { "" }
                    account_name          = if ($prop.Value.account_name) { $prop.Value.account_name } else { "" }
                    avatar_index          = if ($null -ne $prop.Value.avatar_index) { $prop.Value.avatar_index } else { 0 }
                    using_default_avatar  = if ($null -ne $prop.Value.using_default_avatar) { $prop.Value.using_default_avatar } else { $true }
                    using_gaia_avatar     = if ($null -ne $prop.Value.using_gaia_avatar) { $prop.Value.using_gaia_avatar } else { $false }
                    gaia_name             = if ($prop.Value.gaia_name) { $prop.Value.gaia_name } else { "" }
                    gaia_given_name       = if ($prop.Value.gaia_given_name) { $prop.Value.gaia_given_name } else { "" }
                    profile_color_seed    = if ($null -ne $prop.Value.profile_color_seed) { $prop.Value.profile_color_seed } else { 0 }
                    is_using_gaia_picture = if ($null -ne $prop.Value.is_using_gaia_picture) { $prop.Value.is_using_gaia_picture } else { $false }
                }
            }
        } catch {}
    }

    $importProfiles = Get-ChromeProfileFolders $script:tempImport
    if ($importProfiles.Count -eq 0) {
        if (Test-Path $script:tempImport) { Remove-Item $script:tempImport -Recurse -Force }
        [System.Windows.Forms.MessageBox]::Show("No s'han trobat perfils al ZIP.","Error")
        return
    }

    $form = New-Object System.Windows.Forms.Form
    $form.Text          = "Importació — Selecciona què importar"
    $form.Size          = New-Object System.Drawing.Size(880,580)
    $form.StartPosition = "CenterScreen"
    $form.Font          = New-Object System.Drawing.Font("Segoe UI",10)

    $grid = New-ProfileGrid

    foreach ($p in $importProfiles) {
        $id = $p.Name
        $name = if ($importMeta[$id]) { Get-DisplayProfileName $importMeta[$id] } else { $id }
        $email = if ($importMeta[$id]) { $importMeta[$id].email } else { "" }

        $hasPref = (Test-Path (Join-Path $p.FullName "Bookmarks")) -or (Test-Path (Join-Path $p.FullName "Bookmarks.bak"))
        $hasHist = (Test-Path (Join-Path $p.FullName "History"))

        $rowIdx = $grid.Rows.Add($id, $true, $name, $email, $hasPref, $hasHist)
        if (-not $hasPref) { $grid.Rows[$rowIdx].Cells["PREF"].ReadOnly = $true }
        if (-not $hasHist) { $grid.Rows[$rowIdx].Cells["HIST"].ReadOnly = $true }
    }

    $btnAll = New-Object System.Windows.Forms.Button
    $btnAll.Text = "MARCA-HO TOT"
    $btnAll.Size = New-Object System.Drawing.Size(160,35)
    $btnAll.Location = New-Object System.Drawing.Point(20,310)
    $btnAll.Add_Click({ Set-GridAll $grid $true })

    $btnNone = New-Object System.Windows.Forms.Button
    $btnNone.Text = "DESMARCA-HO TOT"
    $btnNone.Size = New-Object System.Drawing.Size(160,35)
    $btnNone.Location = New-Object System.Drawing.Point(190,310)
    $btnNone.Add_Click({ Set-GridAll $grid $false })

    $progress          = New-Object System.Windows.Forms.ProgressBar
    $progress.Location = New-Object System.Drawing.Point(20,370)
    $progress.Size     = New-Object System.Drawing.Size(820,20)

    $lbl          = New-Object System.Windows.Forms.Label
    $lbl.Location = New-Object System.Drawing.Point(20,400)
    $lbl.Size     = New-Object System.Drawing.Size(820,20)

    $btn          = New-ActionButton "IMPORTAR" $colorBlau
    $btn.Location = New-Object System.Drawing.Point(340,450)

    $btn.Add_Click({
        $grid.EndEdit()
        $rows = @($grid.Rows | Where-Object { [bool]$_.Cells["PERFIL"].Value })
        if ($rows.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("Selecciona almenys un perfil.")
            return
        }

        $btn.Enabled = $false
        try {
            Ensure-Dir $script:chromePath
            $progress.Maximum = $rows.Count
            $progress.Value = 0
            $selectedIds = @()

            foreach ($row in $rows) {
                $id = [string]$row.Cells["ID"].Value
                $name = [string]$row.Cells["Name"].Value
                $lbl.Text = "Important: $name"
                $form.Refresh()

                $selectedIds += $id

                $src = Join-Path $script:tempImport $id
                $dst = Join-Path $script:chromePath $id
                Ensure-Dir $dst

                # CLAU: Còpia directa de Preferences (Pura de veritat, preserva avatars intactes)
                Copy-Safe (Join-Path $src "Preferences") $dst

                Copy-Safe (Join-Path $src "Avatars") $dst
                Copy-Safe (Join-Path $src "Google Profile Picture.png") $dst
                Copy-Safe (Join-Path $src "Profile Picture.png") $dst
                Copy-Safe (Join-Path $src "Profile Picture") $dst
                Copy-Safe (Join-Path $src "GAIA Profile Picture.png") $dst
                Copy-Safe (Join-Path $src "GAIA Picture.png") $dst

                if ([bool]$row.Cells["PREF"].Value) {
                    Copy-BookmarksSafe $src $dst
                    Copy-Safe (Join-Path $src "Favicons") $dst
                }

                if ([bool]$row.Cells["HIST"].Value) {
                    Copy-Safe (Join-Path $src "History") $dst
                    Copy-Safe (Join-Path $src "Visited Links") $dst
                    Copy-Safe (Join-Path $src "Top Sites") $dst
                    Copy-Safe (Join-Path $src "Shortcuts") $dst
                    if (-not [bool]$row.Cells["PREF"].Value) {
                        Copy-Safe (Join-Path $src "Favicons") $dst
                    }
                }
                $progress.Value++
            }

            $lbl.Text = "Sincronitzant perfils..."
            $form.Refresh()

            Merge-LocalStateMinim $importMeta $selectedIds $script:chromePath (Join-Path $script:tempImport "Local State")

            [System.Windows.Forms.MessageBox]::Show("Importació completada correctament.", "GestionaChrome")
            $form.Close()

        } catch {
            [System.Windows.Forms.MessageBox]::Show("Error durant l'importació:`n$($_.Exception.Message)","Error")
        } finally {
            if (Test-Path $script:tempImport) { Remove-Item $script:tempImport -Recurse -Force -ErrorAction SilentlyContinue }
            $btn.Enabled = $true
            $lbl.Text = ""
        }
    })

    $form.Controls.AddRange(@($grid,$btnAll,$btnNone,$progress,$lbl,$btn))
    $form.ShowDialog() | Out-Null
}

function Show-DeleteDialog {
    if (-not (Check-Chrome)) { return }

    if (-not (Test-Path $script:chromePath)) {
        [System.Windows.Forms.MessageBox]::Show("No s'han trobat dades de Chrome.","Error")
        return
    }

    $profileFolders = Get-ChromeProfileFolders $script:chromePath
    if ($profileFolders.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("No s'han trobat perfils de Chrome.","Error")
        return
    }

    $meta = Get-ProfileMeta $script:chromePath

    $form = New-Object System.Windows.Forms.Form
    $form.Text          = "Eliminació — Selecciona perfils a esborrar"
    $form.Size          = New-Object System.Drawing.Size(880,580)
    $form.StartPosition = "CenterScreen"
    $form.Font          = New-Object System.Drawing.Font("Segoe UI",10)

    $grid = New-ProfileGrid

    foreach ($p in $profileFolders) {
        $id = $p.Name
        $name = if ($meta[$id]) { Get-DisplayProfileName $meta[$id] } else { $id }
        $email = if ($meta[$id]) { $meta[$id].email } else { "" }
        
        $grid.Rows.Add($id, $false, $name, $email, $false, $false) | Out-Null
        
        $rowIdx = $grid.Rows.Count - 1
        $grid.Rows[$rowIdx].Cells["PREF"].ReadOnly = $true
        $grid.Rows[$rowIdx].Cells["HIST"].ReadOnly = $true
    }

    $btnAll = New-Object System.Windows.Forms.Button
    $btnAll.Text = "MARCA-HO TOT"
    $btnAll.Size = New-Object System.Drawing.Size(160,35)
    $btnAll.Location = New-Object System.Drawing.Point(20,310)
    $btnAll.Add_Click({ Set-GridAll $grid $true })

    $btnNone = New-Object System.Windows.Forms.Button
    $btnNone.Text = "DESMARCA-HO TOT"
    $btnNone.Size = New-Object System.Drawing.Size(160,35)
    $btnNone.Location = New-Object System.Drawing.Point(190,310)
    $btnNone.Add_Click({ Set-GridAll $grid $false })

    $progress          = New-Object System.Windows.Forms.ProgressBar
    $progress.Location = New-Object System.Drawing.Point(20,370)
    $progress.Size     = New-Object System.Drawing.Size(820,20)

    $lbl          = New-Object System.Windows.Forms.Label
    $lbl.Location = New-Object System.Drawing.Point(20,400)
    $lbl.Size     = New-Object System.Drawing.Size(820,20)

    $btn          = New-ActionButton "ELIMINAR" $colorVermell
    $btn.Location = New-Object System.Drawing.Point(340,450)

    $btn.Add_Click({
        $grid.EndEdit()
        $rows = @($grid.Rows | Where-Object { [bool]$_.Cells["PERFIL"].Value })
        if ($rows.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("Selecciona almenys un perfil.")
            return
        }

        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "Estàs segur que vols eliminar els perfils seleccionats? Aquesta acció no es pot desfer.",
            "Confirmació",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }

        $btn.Enabled = $false
        try {
            $lsPath = Join-Path $script:chromePath "Local State"
            $ls = $null
            if (Test-Path $lsPath) {
                try { $ls = Get-Content $lsPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
            }

            $progress.Maximum = $rows.Count
            $progress.Value = 0

            foreach ($row in $rows) {
                $id = [string]$row.Cells["ID"].Value
                $name = [string]$row.Cells["Name"].Value
                $lbl.Text = "Eliminant: $name"
                $form.Refresh()

                $profilePath = Join-Path $script:chromePath $id
                if (Test-Path $profilePath) {
                    Remove-Item $profilePath -Recurse -Force -ErrorAction SilentlyContinue
                }

                if ($ls -and $ls.profile.info_cache.PSObject.Properties[$id]) {
                    $newCache = [ordered]@{}
                    foreach ($prop in $ls.profile.info_cache.PSObject.Properties) {
                        if ($prop.Name -ne $id) { $newCache[$prop.Name] = $prop.Value }
                    }
                    $ls.profile.info_cache = [PSCustomObject]$newCache
                }
                $progress.Value++
            }

            if ($ls) { $ls | ConvertTo-Json -Depth 20 | Set-Content $lsPath -Encoding UTF8 }

            [System.Windows.Forms.MessageBox]::Show("Perfils eliminats correctament.", "GestionaChrome")
            $form.Close()

        } catch {
            [System.Windows.Forms.MessageBox]::Show("Error durant l'eliminació:`n$($_.Exception.Message)", "Error")
        } finally {
            $btn.Enabled = $true
            $lbl.Text = ""
        }
    })

    $form.Controls.AddRange(@($grid,$btnAll,$btnNone,$progress,$lbl,$btn))
    $form.ShowDialog() | Out-Null
}

# ==============================================================================
# FINESTRA DISPARADORA PRINCIPAL (LAUNCHER)
# ==============================================================================

$launcher = New-Object System.Windows.Forms.Form
$launcher.Text            = "GestionaChrome v2.5"
$launcher.Size            = New-Object System.Drawing.Size(460,390)
$launcher.StartPosition   = "CenterScreen"
$launcher.FormBorderStyle = "FixedDialog"
$launcher.MaximizeBox     = $false
$launcher.MinimizeBox     = $false
$launcher.Font            = New-Object System.Drawing.Font("Segoe UI",10)

$btnExp = New-ActionButton "EXPORTAR" $colorVerd
$btnExp.Size     = New-Object System.Drawing.Size(300,60)
$btnExp.Location = New-Object System.Drawing.Point(75,60)
$btnExp.Font     = New-Object System.Drawing.Font("Segoe UI",12,[System.Drawing.FontStyle]::Bold)

$btnImp = New-ActionButton "IMPORTAR" $colorBlau
$btnImp.Size     = New-Object System.Drawing.Size(300,60)
$btnImp.Location = New-Object System.Drawing.Point(75,150)
$btnImp.Font     = New-Object System.Drawing.Font("Segoe UI",12,[System.Drawing.FontStyle]::Bold)

$btnDel = New-ActionButton "ELIMINAR" $colorVermell
$btnDel.Size     = New-Object System.Drawing.Size(300,60)
$btnDel.Location = New-Object System.Drawing.Point(75,240)
$btnDel.Font     = New-Object System.Drawing.Font("Segoe UI",12,[System.Drawing.FontStyle]::Bold)

# Control de fils 100% estable sense interrupcions d'instància
$btnExp.Add_Click({
    $launcher.Hide()
    Show-ExportDialog
    $launcher.Show()
})

$btnImp.Add_Click({
    $launcher.Hide()
    Show-ImportDialog
    $launcher.Show()
})

$btnDel.Add_Click({
    $launcher.Hide()
    Show-DeleteDialog
    $launcher.Show()
})

$launcher.Controls.AddRange(@($btnExp,$btnImp,$btnDel))
$launcher.ShowDialog() | Out-Null