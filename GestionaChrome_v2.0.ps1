# ==============================================================================
# GestionaChrome
# ------------------------------------------------------------------------------
# - Local State: merge MÍNIM a la importació (name, user_name, last_used)
#   perquè Chrome reconegui els perfils al PC de destí. Sense copiar
#   configuració d'extensions ni preferències.
# - Fix: CurrentCellDirtyStateChanged usa param($sender,$e)
# - Fix: Test-ZipValid neteja temporal al finally
# - Fix: Favicons sense duplicació
# - Fix: Copy-Safe avisa si no pot copiar després de 3 intents
# - Fix: Copy-BookmarksSafeExport simplificada
# ==============================================================================# ==============================================================================
# GestionaChrome
# ------------------------------------------------------------------------------
# - Local State: merge MÍNIM a la importació (name, user_name, last_used)
#   perquè Chrome reconegui els perfils al PC de destí. Sense copiar
#   configuració d'extensions ni preferències.
# - Fix: CurrentCellDirtyStateChanged usa param($sender,$e)
# - Fix: Test-ZipValid neteja temporal al finally
# - Fix: Favicons sense duplicació
# - Fix: Copy-Safe avisa si no pot copiar després de 3 intents
# - Fix: Copy-BookmarksSafeExport simplificada
# ==============================================================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
} catch {}

# --- CONFIG ---
$script:chromePath  = Join-Path $env:LOCALAPPDATA "Google\Chrome\User Data"
$script:tempExport  = Join-Path $env:TEMP "GestionaChrome_Export"
$script:tempImport  = Join-Path $env:TEMP "GestionaChrome_Import"
$script:profileRegex = '^(Default|Profile \d+)$'
$script:metaFile     = "profiles_meta.json"

# ==============================================================================
# FUNCIONS UTILITÀRIES
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

# Còpia segura amb reintents. Avisa si falla els 3 cops.
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
    Write-Warning "No s'ha pogut copiar: $src"
}

# Bookmarks amb fallback: si no hi ha Bookmarks però sí .bak, el restaura.
function Copy-BookmarksSafe($srcProfile, $dstProfile) {
    $b    = Join-Path $srcProfile "Bookmarks"
    $bBak = Join-Path $srcProfile "Bookmarks.bak"

    if (Test-Path $b) {
        Copy-Safe $b    $dstProfile
        Copy-Safe $bBak $dstProfile   # pot no existir; Copy-Safe ho gestiona
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

# Llegeix metadata visual i identificativa dels perfils.
# - Local State: nom i correu
# - Preferences: avatar, color i identitat visual
function Get-ProfileMeta($basePath) {

    $meta   = @{}
    $lsPath = Join-Path $basePath "Local State"

    # ------------------------------------------------------------
    # 1. LLEGIR LOCAL STATE
    # ------------------------------------------------------------
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

    # ------------------------------------------------------------
    # 2. LLEGIR PREFERENCES DE CADA PERFIL
    # ------------------------------------------------------------
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

					if ($pref.profile.name) {
						$meta[$id].profile_name = $pref.profile.name
					}

					if ($pref.profile.gaia_name) {
						$meta[$id].account_name = $pref.profile.gaia_name
					}

					if ($null -ne $pref.profile.avatar_index) {
						$meta[$id].avatar_index = $pref.profile.avatar_index
					}

					if ($null -ne $pref.profile.using_default_avatar) {
						$meta[$id].using_default_avatar = $pref.profile.using_default_avatar
					}

					if ($null -ne $pref.profile.using_gaia_avatar) {
						$meta[$id].using_gaia_avatar = $pref.profile.using_gaia_avatar
					}

					if ($pref.profile.gaia_name) {
						$meta[$id].gaia_name = $pref.profile.gaia_name
					}

					if ($pref.profile.gaia_given_name) {
						$meta[$id].gaia_given_name = $pref.profile.gaia_given_name
					}

					if ($null -ne $pref.profile.profile_color_seed) {
						$meta[$id].profile_color_seed = $pref.profile.profile_color_seed
					}
					
					if ($null -ne $pref.profile.is_using_gaia_picture) {
						$meta[$id].is_using_gaia_picture = $pref.profile.is_using_gaia_picture
					}

					# FALLBACK EXTRA
					# Alguns Chromes guarden millor el nom aquí
					if ($pref.account_info -and $pref.account_info.Count -gt 0) {

						$acc = $pref.account_info[0]

						if (-not $meta[$id].account_name -and $acc.full_name) {
							$meta[$id].account_name = $acc.full_name
						}
					}
				}

            } catch {}
        }
    }

    return $meta
}

function Get-DisplayProfileName($metaItem) {

    # Prioritat absoluta:
    # nom del compte Google

    if ($metaItem.account_name) {
        return [string]$metaItem.account_name
    }

    # Fallbacks

    if ($metaItem.gaia_name) {
        return [string]$metaItem.gaia_name
    }

    if ($metaItem.email) {
        return [string]$metaItem.email
    }

    if ($metaItem.profile_name) {
        return [string]$metaItem.profile_name
    }

    return "Perfil Chrome"
}

# Merge mínim del Local State al PC de destí:
# afegeix NOMÉS els camps mínims (name, user_name, last_used) per a cada perfil seleccionat.
# NO copia extensions, preferences ni cap altra configuració.
function Merge-LocalStateMinim($importedMetaMap, $selectedIds, $destChromePath) {
    $lsDest = Join-Path $destChromePath "Local State"

    # Construïm o llegim el Local State de destí
    if (Test-Path $lsDest) {
        try   { $ls = Get-Content $lsDest -Raw -Encoding UTF8 | ConvertFrom-Json }
        catch { $ls = [PSCustomObject]@{ profile = [PSCustomObject]@{ info_cache = [PSCustomObject]@{} } } }
    } else {
        $ls = [PSCustomObject]@{ profile = [PSCustomObject]@{ info_cache = [PSCustomObject]@{} } }
    }

    # Assegurem que existeix profile.info_cache
    if (-not $ls.PSObject.Properties["profile"]) {
        $ls | Add-Member -MemberType NoteProperty -Name "profile" `
              -Value ([PSCustomObject]@{ info_cache = [PSCustomObject]@{} })
    }
    if (-not $ls.profile.PSObject.Properties["info_cache"]) {
        $ls.profile | Add-Member -MemberType NoteProperty -Name "info_cache" `
                      -Value ([PSCustomObject]@{})
    }

    foreach ($id in $selectedIds) {

    if (-not $ls.profile.info_cache.PSObject.Properties[$id]) {

        $entry = [PSCustomObject]@{

            name = if ($importedMetaMap[$id]) {
                $importedMetaMap[$id].name
            } else {
                $id
            }

            user_name = if ($importedMetaMap[$id]) {
                $importedMetaMap[$id].email
            } else {
                ""
            }

            last_used = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")

            gaia_name = if ($importedMetaMap[$id].gaia_name) {
                $importedMetaMap[$id].gaia_name
            } else {
                ""
            }

            gaia_given_name = if ($importedMetaMap[$id].gaia_given_name) {
                $importedMetaMap[$id].gaia_given_name
            } else {
                ""
            }

            avatar_icon = "chrome://theme/IDR_PROFILE_AVATAR_$($importedMetaMap[$id].avatar_index)"

            using_default_avatar = if ($null -ne $importedMetaMap[$id].using_default_avatar) {
                $importedMetaMap[$id].using_default_avatar
            } else {
                $true
            }

            using_gaia_avatar = if ($null -ne $importedMetaMap[$id].using_gaia_avatar) {
                $importedMetaMap[$id].using_gaia_avatar
            } else {
                $false
            }

            profile_color_seed = if ($null -ne $importedMetaMap[$id].profile_color_seed) {
                $importedMetaMap[$id].profile_color_seed
            } else {
                0
            }

            is_using_gaia_picture = if ($null -ne $importedMetaMap[$id].is_using_gaia_picture) {
                $importedMetaMap[$id].is_using_gaia_picture
            } else {
                $false
            }
        }

        $ls.profile.info_cache | Add-Member `
            -MemberType NoteProperty `
            -Name $id `
            -Value $entry
    }
}

    try {
        Ensure-Dir (Split-Path $lsDest)
        $ls | ConvertTo-Json -Depth 100 | Set-Content $lsDest -Encoding UTF8
    } catch {
        Write-Warning "No s'ha pogut actualitzar Local State: $($_.Exception.Message)"
    }
}

# Genera un Preferences mínim i segur
# sense extensions ni configuracions problemàtiques
function New-MinimalPreferences($meta, $destProfilePath) {

    $prefObj = @{
        profile = @{
            name                   = $meta.name
            avatar_index           = $meta.avatar_index
            using_default_avatar   = $meta.using_default_avatar
            using_gaia_avatar      = $meta.using_gaia_avatar
            gaia_name              = $meta.gaia_name
            gaia_given_name        = $meta.gaia_given_name
            profile_color_seed     = $meta.profile_color_seed
        }
    }

    $prefPath = Join-Path $destProfilePath "Preferences"

    try {

        $prefObj |
            ConvertTo-Json -Depth 10 |
            Set-Content $prefPath -Encoding UTF8

    } catch {

        Write-Warning "No s'ha pogut generar Preferences per: $destProfilePath"
    }
}

# Valida el ZIP: ha de tenir almenys un perfil amb dades reconegudes.
# El temporal es neteja SEMPRE al finally.
function Test-ZipValid($zipPath, $tempDest) {
    try {
        if (Test-Path $tempDest) { Remove-Item $tempDest -Recurse -Force }
        Expand-Archive -Path $zipPath -DestinationPath $tempDest -Force

        $profiles = Get-ChromeProfileFolders $tempDest
        if ($profiles.Count -eq 0) { return $false }

        foreach ($p in $profiles) {
            $pp = $p.FullName
            if (
                (Test-Path (Join-Path $pp "Bookmarks"))     -or
                (Test-Path (Join-Path $pp "Bookmarks.bak")) -or
                (Test-Path (Join-Path $pp "History"))       -or
                (Test-Path (Join-Path $pp "Visited Links")) -or
                (Test-Path (Join-Path $pp "Top Sites"))     -or
                (Test-Path (Join-Path $pp "Shortcuts"))
            ) { return $true }
        }
        return $false
    }
    catch   { return $false }
    finally {
        # Neteja SEMPRE, fins i tot si ha fallat l'expansió
        # (el caller torna a expandir si la validació passa)
        if (Test-Path $tempDest) {
            Remove-Item $tempDest -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# Flag per evitar lògiques d'events durant canvis massius
$script:isBulkUpdate = $false

function Set-GridAll($grid, [bool]$checked) {
    $script:isBulkUpdate = $true
    try {
        $grid.SuspendLayout()
        foreach ($row in $grid.Rows) {
            if ($row.IsNewRow) { continue }

            # Respecta files deshabilitades (PERFIL read-only)
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

# Graella compartida Export/Import
function New-ProfileGrid {
    $g = New-Object Windows.Forms.DataGridView
    $g.Size                = New-Object Drawing.Size(800,280)
    $g.Location            = New-Object Drawing.Point(20,20)
    $g.AutoSizeColumnsMode = "Fill"
    $g.RowHeadersVisible   = $false
    $g.AllowUserToAddRows  = $false
    $g.SelectionMode       = "FullRowSelect"

    # ID ocult
    $g.Columns.Add("ID","ID") | Out-Null
    $g.Columns["ID"].Visible = $false

    # PERFIL (master checkbox)
    $colP = New-Object Windows.Forms.DataGridViewCheckBoxColumn
    $colP.Name       = "PERFIL"
    $colP.HeaderText = "Perfil"
    $colP.Width      = 50
    $colP.AutoSizeMode = "None"
    $g.Columns.Add($colP) | Out-Null

    # Nom i correu
    $g.Columns.Add("Name", "Nom perfil") | Out-Null
    $g.Columns.Add("Email","Correu")     | Out-Null

    # PREF i HIST
    $colPref = New-Object Windows.Forms.DataGridViewCheckBoxColumn
    $colPref.Name       = "PREF"
    $colPref.HeaderText = "Preferits"
    $g.Columns.Add($colPref) | Out-Null

    $colHist = New-Object Windows.Forms.DataGridViewCheckBoxColumn
    $colHist.Name       = "HIST"
    $colHist.HeaderText = "Historial"
    $g.Columns.Add($colHist) | Out-Null

    # Commit immediat — fix: param($sender,$e)
    $g.Add_CurrentCellDirtyStateChanged({
        param($sender, $e)
        if ($sender.IsCurrentCellDirty) {
            $sender.CommitEdit([System.Windows.Forms.DataGridViewDataErrorContexts]::Commit)
        }
    })

    # Lògica master:
    #   PREF o HIST marcats  → PERFIL es marca automàticament
    #   PERFIL desmarcat     → PREF i HIST es desmarquen
    $g.Add_CellValueChanged({
        param($sender, $e)
        if ($script:isBulkUpdate) { return }
        if ($e.RowIndex -lt 0) { return }
        $row = $sender.Rows[$e.RowIndex]

        $iPERFIL = $sender.Columns["PERFIL"].Index
        $iPREF   = $sender.Columns["PREF"].Index
        $iHIST   = $sender.Columns["HIST"].Index

        if ($e.ColumnIndex -eq $iPREF -or $e.ColumnIndex -eq $iHIST) {
            if (([bool]$row.Cells["PREF"].Value -or [bool]$row.Cells["HIST"].Value) `
                -and -not [bool]$row.Cells["PERFIL"].Value) {
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

# Botó d'acció estilitzat (reutilitzable)
function New-ActionButton($text, $color) {
    $b = New-Object Windows.Forms.Button
    $b.Text      = $text
    $b.Size      = New-Object Drawing.Size(200,50)
    $b.Font      = New-Object System.Drawing.Font("Segoe UI",11,[System.Drawing.FontStyle]::Bold)
    $b.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $b.BackColor = $color
    $b.ForeColor = [System.Drawing.Color]::White
    $b.FlatAppearance.BorderSize = 0
    return $b
}

# ==============================================================================
# LLANÇADOR
# ==============================================================================

$script:mode = $null

$launcher = New-Object Windows.Forms.Form
$launcher.Text            = "GestionaChrome v2.0"
$launcher.Size            = New-Object Drawing.Size(460,390)
$launcher.StartPosition   = "CenterScreen"
$launcher.FormBorderStyle = "FixedDialog"
$launcher.MaximizeBox     = $false
$launcher.MinimizeBox     = $false
$launcher.Font            = New-Object System.Drawing.Font("Segoe UI",10)

$colorVerd   = [System.Drawing.Color]::FromArgb(34,177,76)
$colorBlau   = [System.Drawing.Color]::FromArgb(0,123,255)
$colorVermell = [System.Drawing.Color]::FromArgb(192,57,43)

$btnExp = New-ActionButton "EXPORTAR" $colorVerd
$btnExp.Size     = New-Object Drawing.Size(300,60)
$btnExp.Location = New-Object Drawing.Point(75,60)
$btnExp.Font     = New-Object System.Drawing.Font("Segoe UI",12,[System.Drawing.FontStyle]::Bold)

$btnImp = New-ActionButton "IMPORTAR" $colorBlau
$btnImp.Size     = New-Object Drawing.Size(300,60)
$btnImp.Location = New-Object Drawing.Point(75,150)
$btnImp.Font     = New-Object System.Drawing.Font("Segoe UI",12,[System.Drawing.FontStyle]::Bold)

$btnDel = New-ActionButton "ELIMINAR" $colorVermell
$btnDel.Size     = New-Object Drawing.Size(300,60)
$btnDel.Location = New-Object Drawing.Point(75,240)
$btnDel.Font     = New-Object System.Drawing.Font("Segoe UI",12,[System.Drawing.FontStyle]::Bold)

$btnExp.Add_Click({ $script:mode = "export"; $launcher.Close() })
$btnImp.Add_Click({ $script:mode = "import"; $launcher.Close() })
$btnDel.Add_Click({ $script:mode = "delete"; $launcher.Close() })

$launcher.Controls.AddRange(@($btnExp,$btnImp,$btnDel))
$launcher.ShowDialog() | Out-Null

if (-not $script:mode) { exit }

# ==============================================================================
# EXPORTACIÓ
# ==============================================================================

if ($script:mode -eq "export") {

    if (-not (Check-Chrome)) { exit }

    if (-not (Test-Path $script:chromePath)) {
        [System.Windows.Forms.MessageBox]::Show("No s'han trobat dades de Chrome.","Error"); exit
    }

    $profileFolders = Get-ChromeProfileFolders $script:chromePath
    if ($profileFolders.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("No s'han trobat perfils de Chrome.","Error"); exit
    }

    $meta = Get-ProfileMeta $script:chromePath

    $form = New-Object Windows.Forms.Form
    $form.Text          = "Exportació — Selecciona perfils i dades"
    $form.Size          = New-Object Drawing.Size(880,580)
    $form.StartPosition = "CenterScreen"
    $form.Font          = New-Object System.Drawing.Font("Segoe UI",10)

    $grid = New-ProfileGrid

    foreach ($p in $profileFolders) {
        $id    = $p.Name
        $name = if ($meta[$id]) {
		Get-DisplayProfileName $meta[$id]
		} else {
			$id
		}
		
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

    $progress          = New-Object Windows.Forms.ProgressBar
    $progress.Location = New-Object Drawing.Point(20,370)
    $progress.Size     = New-Object Drawing.Size(820,20)

    $lbl          = New-Object Windows.Forms.Label
    $lbl.Location = New-Object Drawing.Point(20,400)
    $lbl.Size     = New-Object Drawing.Size(820,20)

    $btn          = New-ActionButton "EXPORTAR" $colorVerd
    $btn.Location = New-Object Drawing.Point(340,450)

    $btn.Add_Click({
        $grid.EndEdit()

        $rows = @($grid.Rows | Where-Object { [bool]$_.Cells["PERFIL"].Value })
        if ($rows.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("Selecciona almenys un perfil."); return
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

            # Metadata lleugera per a la UI d'import (nom + correu)
            $metaExport = @{}
            foreach ($row in $rows) {
                $id = [string]$row.Cells["ID"].Value
                $metaExport[$id] = @{
                    name           = [string]$row.Cells["Name"].Value
					email          = [string]$row.Cells["Email"].Value

					profile_name   = $meta[$id].profile_name
					account_name   = $meta[$id].account_name
                
                    avatar_index            = $meta[$id].avatar_index
					using_default_avatar    = $meta[$id].using_default_avatar
					using_gaia_avatar       = $meta[$id].using_gaia_avatar
					is_using_gaia_picture   = $meta[$id].is_using_gaia_picture
					profile_color_seed      = $meta[$id].profile_color_seed
					gaia_name               = $meta[$id].gaia_name
					gaia_given_name         = $meta[$id].gaia_given_name
                }
            }
            $metaExport | ConvertTo-Json -Depth 5 |
                Set-Content (Join-Path $script:tempExport $script:metaFile) -Encoding UTF8

            $progress.Maximum = $rows.Count
            $progress.Value   = 0

            foreach ($row in $rows) {
                $id   = [string]$row.Cells["ID"].Value
                $name = [string]$row.Cells["Name"].Value
                $lbl.Text = "Exportant: $name"
                $form.Refresh()

                $src = Join-Path $script:chromePath $id
                $dst = Join-Path $script:tempExport $id
                Ensure-Dir $dst

                # Avatar (no porta extensions)
                Copy-Safe (Join-Path $src "Avatars")                    $dst
                Copy-Safe (Join-Path $src "Google Profile Picture.png") $dst

                if ([bool]$row.Cells["PREF"].Value) {
                    Copy-BookmarksSafe $src $dst
                    Copy-Safe (Join-Path $src "Favicons")         $dst
                    Copy-Safe (Join-Path $src "Favicons-journal") $dst
                    Copy-Safe (Join-Path $src "Favicons-wal")     $dst
                    Copy-Safe (Join-Path $src "Favicons-shm")     $dst
                }

                if ([bool]$row.Cells["HIST"].Value) {
                    Copy-Safe (Join-Path $src "History")          $dst
                    Copy-Safe (Join-Path $src "History-journal")  $dst
                    Copy-Safe (Join-Path $src "History-wal")      $dst
                    Copy-Safe (Join-Path $src "History-shm")      $dst
                    Copy-Safe (Join-Path $src "Visited Links")    $dst
                    Copy-Safe (Join-Path $src "Top Sites")        $dst
                    Copy-Safe (Join-Path $src "Shortcuts")        $dst
                    # Favicons per historial visual (si no s'han copiat ja per PREF)
                    if (-not [bool]$row.Cells["PREF"].Value) {
                        Copy-Safe (Join-Path $src "Favicons")         $dst
                        Copy-Safe (Join-Path $src "Favicons-journal") $dst
                        Copy-Safe (Join-Path $src "Favicons-wal")     $dst
                        Copy-Safe (Join-Path $src "Favicons-shm")     $dst
                    }
                }

                $progress.Value++
            }

            $lbl.Text = "Comprimint..."
            $form.Refresh()

            if (Test-Path $sfd.FileName) { Remove-Item $sfd.FileName -Force }
            Compress-Archive -Path (Join-Path $script:tempExport "*") `
                             -DestinationPath $sfd.FileName -Force

            [System.Windows.Forms.MessageBox]::Show(
                "Exportació completada!`n`n$($sfd.FileName)",
                "GestionaChrome")
            $form.Close()
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show(
                "Error durant l'exportació:`n$($_.Exception.Message)","Error")
        }
        finally {
            if (Test-Path $script:tempExport) { Remove-Item $script:tempExport -Recurse -Force }
            $btn.Enabled = $true
            $lbl.Text    = ""
        }
    })

    $form.Controls.AddRange(@($grid,$btnAll,$btnNone,$progress,$lbl,$btn))
    $form.ShowDialog() | Out-Null
}

# ==============================================================================
# IMPORTACIÓ
# ==============================================================================

elseif ($script:mode -eq "import") {

    if (-not (Check-Chrome)) { exit }

    $ofd = New-Object System.Windows.Forms.OpenFileDialog
    $ofd.Filter = "Zip (*.zip)|*.zip"
    if ($ofd.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { exit }

    # Validació (neteja el temp al finally intern)
    if (-not (Test-ZipValid $ofd.FileName $script:tempImport)) {
        [System.Windows.Forms.MessageBox]::Show(
            "El fitxer seleccionat no és un arxiu vàlid de GestionaChrome.",
            "Arxiu no vàlid")
        exit
    }

    # Tornem a expandir perquè Test-ZipValid neteja el temp al finally
    try {
        Expand-Archive -Path $ofd.FileName -DestinationPath $script:tempImport -Force
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Error en descomprimir el fitxer.","Error"); exit
    }

    # Llegim metadata del ZIP
    $importMeta = @{}
    $metaPath = Join-Path $script:tempImport $script:metaFile
    if (Test-Path $metaPath) {
        try {
            $raw = Get-Content $metaPath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($prop in $raw.PSObject.Properties) {
               $importMeta[$prop.Name] = @{
					name                   = if ($prop.Value.name) { $prop.Value.name } else { $prop.Name }
					email                  = if ($prop.Value.email) { $prop.Value.email } else { "" }

					profile_name           = if ($prop.Value.profile_name) { $prop.Value.profile_name } else { "" }
					account_name           = if ($prop.Value.account_name) { $prop.Value.account_name } else { "" }                
                    avatar_index           = if ($null -ne $prop.Value.avatar_index) { $prop.Value.avatar_index } else { 0 }
                    using_default_avatar   = if ($null -ne $prop.Value.using_default_avatar) { $prop.Value.using_default_avatar } else { $true }
                    using_gaia_avatar      = if ($null -ne $prop.Value.using_gaia_avatar) { $prop.Value.using_gaia_avatar } else { $false }
                
                    gaia_name              = if ($prop.Value.gaia_name) { $prop.Value.gaia_name } else { "" }
                    gaia_given_name        = if ($prop.Value.gaia_given_name) { $prop.Value.gaia_given_name } else { "" }
                
                    profile_color_seed     = if ($null -ne $prop.Value.profile_color_seed) { $prop.Value.profile_color_seed } else { 0 }
                }
            }
        } catch {}
    }

    $importProfiles = Get-ChromeProfileFolders $script:tempImport
    if ($importProfiles.Count -eq 0) {
        if (Test-Path $script:tempImport) { Remove-Item $script:tempImport -Recurse -Force }
        [System.Windows.Forms.MessageBox]::Show("No s'han trobat perfils al ZIP.","Error"); exit
    }

    $form = New-Object Windows.Forms.Form
    $form.Text          = "Importació — Selecciona què importar"
    $form.Size          = New-Object Drawing.Size(880,580)
    $form.StartPosition = "CenterScreen"
    $form.Font          = New-Object System.Drawing.Font("Segoe UI",10)

    $grid = New-ProfileGrid

    foreach ($p in $importProfiles) {
        $id         = $p.Name
        $folderPath = $p.FullName
		$name = if ($importMeta[$id]) {
			Get-DisplayProfileName $importMeta[$id]
		} else {
			$id
		}
		
        $email      = if ($importMeta[$id]) { $importMeta[$id].email } else { "" }

        $hasPref = (Test-Path (Join-Path $folderPath "Bookmarks"))     -or
                   (Test-Path (Join-Path $folderPath "Bookmarks.bak")) -or
                   (Test-Path (Join-Path $folderPath "Favicons"))

        $hasHist = (Test-Path (Join-Path $folderPath "History"))        -or
                   (Test-Path (Join-Path $folderPath "History-journal")) -or
                   (Test-Path (Join-Path $folderPath "Visited Links"))   -or
                   (Test-Path (Join-Path $folderPath "Top Sites"))       -or
                   (Test-Path (Join-Path $folderPath "Shortcuts"))

        $rowIdx  = $grid.Rows.Add($id, ($hasPref -or $hasHist), $name, $email, $hasPref, $hasHist)

        if (-not $hasPref) {
            $grid.Rows[$rowIdx].Cells["PREF"].ReadOnly  = $true
            $grid.Rows[$rowIdx].Cells["PREF"].Style.BackColor = [Drawing.Color]::LightGray
        }
        if (-not $hasHist) {
            $grid.Rows[$rowIdx].Cells["HIST"].ReadOnly  = $true
            $grid.Rows[$rowIdx].Cells["HIST"].Style.BackColor = [Drawing.Color]::LightGray
        }
        if (-not $hasPref -and -not $hasHist) {
            $grid.Rows[$rowIdx].Cells["PERFIL"].ReadOnly  = $true
            $grid.Rows[$rowIdx].Cells["PERFIL"].Value     = $false
            $grid.Rows[$rowIdx].Cells["PERFIL"].Style.BackColor = [Drawing.Color]::LightGray
        }
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

    $progress          = New-Object Windows.Forms.ProgressBar
    $progress.Location = New-Object Drawing.Point(20,370)
    $progress.Size     = New-Object Drawing.Size(820,20)

    $lbl          = New-Object Windows.Forms.Label
    $lbl.Location = New-Object Drawing.Point(20,400)
    $lbl.Size     = New-Object Drawing.Size(820,20)

    $btn          = New-ActionButton "IMPORTAR" $colorBlau
    $btn.Location = New-Object Drawing.Point(340,450)

    $btn.Add_Click({
        $grid.EndEdit()

        $rows = @($grid.Rows | Where-Object { [bool]$_.Cells["PERFIL"].Value })
        if ($rows.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("Selecciona almenys un perfil."); return
        }

        $btn.Enabled = $false
        try {
            Ensure-Dir $script:chromePath

            # ---------------------------------------------------------------
            # Merge mínim del Local State:
            # Afegeix name, user_name i last_used per a cada perfil seleccionat.
            # Chrome necessita aquesta entrada per reconèixer el perfil.
            # NO copia configuració d'extensions ni preferències.
            # ---------------------------------------------------------------
            $selectedIds = $rows | ForEach-Object { [string]$_.Cells["ID"].Value }
            Merge-LocalStateMinim $importMeta $selectedIds $script:chromePath

            $progress.Maximum = $rows.Count
            $progress.Value   = 0

            foreach ($row in $rows) {
                $id   = [string]$row.Cells["ID"].Value
                $name = [string]$row.Cells["Name"].Value
                $lbl.Text = "Important: $name"
                $form.Refresh()

                $src = Join-Path $script:tempImport $id
                $dst = Join-Path $script:chromePath $id
                Ensure-Dir $dst

                # Generem un Preferences mínim per restaurar
                # nom, avatar i identitat visual del perfil
                if ($importMeta[$id]) {
                    New-MinimalPreferences $importMeta[$id] $dst
                }
                
                # Avatar
                Copy-Safe (Join-Path $src "Avatars")                    $dst
                Copy-Safe (Join-Path $src "Google Profile Picture.png") $dst

                if ([bool]$row.Cells["PREF"].Value) {
                    Copy-Safe (Join-Path $src "Bookmarks")        $dst
                    Copy-Safe (Join-Path $src "Bookmarks.bak")    $dst
                    Copy-Safe (Join-Path $src "Favicons")         $dst
                    Copy-Safe (Join-Path $src "Favicons-journal") $dst
                    Copy-Safe (Join-Path $src "Favicons-wal")     $dst
                    Copy-Safe (Join-Path $src "Favicons-shm")     $dst
                }

                if ([bool]$row.Cells["HIST"].Value) {
                    Copy-Safe (Join-Path $src "History")          $dst
                    Copy-Safe (Join-Path $src "History-journal")  $dst
                    Copy-Safe (Join-Path $src "History-wal")      $dst
                    Copy-Safe (Join-Path $src "History-shm")      $dst
                    Copy-Safe (Join-Path $src "Visited Links")    $dst
                    Copy-Safe (Join-Path $src "Top Sites")        $dst
                    Copy-Safe (Join-Path $src "Shortcuts")        $dst
                    if (-not [bool]$row.Cells["PREF"].Value) {
                        Copy-Safe (Join-Path $src "Favicons")         $dst
                        Copy-Safe (Join-Path $src "Favicons-journal") $dst
                        Copy-Safe (Join-Path $src "Favicons-wal")     $dst
                        Copy-Safe (Join-Path $src "Favicons-shm")     $dst
                    }
                }

                $progress.Value++
            }

            [System.Windows.Forms.MessageBox]::Show(
                "Importació completada!`n`nJa pots obrir Google Chrome.",
                "GestionaChrome")
            $form.Close()
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show(
                "Error durant la importació:`n$($_.Exception.Message)","Error")
        }
        finally {
            if (Test-Path $script:tempImport) { Remove-Item $script:tempImport -Recurse -Force }
            $btn.Enabled = $true
            $lbl.Text    = ""
        }
    })

      $form.Add_FormClosed({
        if (Test-Path $script:tempImport) { Remove-Item $script:tempImport -Recurse -Force }
    })

    $form.Controls.AddRange(@($grid,$btnAll,$btnNone,$progress,$lbl,$btn))
    $form.ShowDialog() | Out-Null
}



# ==============================================================================
# ELIMINACIÓ DE PERFILS
# ==============================================================================

elseif ($script:mode -eq "delete") {

    if (-not (Check-Chrome)) { exit }

    $profileFolders = Get-ChromeProfileFolders $script:chromePath

    if ($profileFolders.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show(
            "No s'han trobat perfils de Chrome.",
            "GestionaChrome"
        )
        exit
    }

    $meta = Get-ProfileMeta $script:chromePath

    $form = New-Object Windows.Forms.Form
    $form.Text          = "Eliminar perfils"
    $form.Size          = New-Object Drawing.Size(880,580)
    $form.StartPosition = "CenterScreen"
    $form.Font          = New-Object System.Drawing.Font("Segoe UI",10)

    $grid = New-ProfileGrid

    foreach ($p in $profileFolders) {

        $id = $p.Name

        $name = if ($meta[$id]) {
            Get-DisplayProfileName $meta[$id]
        } else {
            $id
        }

        $email = if ($meta[$id]) {
            $meta[$id].email
        } else {
            ""
        }

        # Per eliminar:
        # PERFIL = false inicialment
        # PREF/HIST només visuals
        $grid.Rows.Add($id, $false, $name, $email, $true, $true) | Out-Null
    }

# ------------------------------------------------------------
# BOTONS MARCAR / DESMARCAR
# ------------------------------------------------------------

$btnAll = New-Object Windows.Forms.Button
$btnAll.Text = "MARCA-HO TOT"
$btnAll.Size = New-Object Drawing.Size(140,35)
$btnAll.Location = New-Object Drawing.Point(20,320)

# ESTIL
$btnAll.FlatStyle = "Flat"
$btnAll.BackColor = [Drawing.Color]::WhiteSmoke

$btnAll.Add_Click({

    foreach ($r in $grid.Rows) {

        if (-not $r.Cells["PERFIL"].ReadOnly) {
            $r.Cells["PERFIL"].Value = $true
        }
    }
})

$btnNone = New-Object Windows.Forms.Button
$btnNone.Text = "DESMARCA-HO TOT"
$btnNone.Size = New-Object Drawing.Size(140,35)
$btnNone.Location = New-Object Drawing.Point(170,320)

# ESTIL
$btnNone.FlatStyle = "Flat"
$btnNone.BackColor = [Drawing.Color]::WhiteSmoke

$btnNone.Add_Click({

    foreach ($r in $grid.Rows) {
        $r.Cells["PERFIL"].Value = $false
    }
})

    $progress = New-Object Windows.Forms.ProgressBar
    $progress.Location = New-Object Drawing.Point(20,370)
    $progress.Size     = New-Object Drawing.Size(820,20)

    $lbl = New-Object Windows.Forms.Label
    $lbl.Location = New-Object Drawing.Point(20,400)
    $lbl.Size     = New-Object Drawing.Size(820,20)

    $btn = New-ActionButton "ELIMINAR" $colorVermell
    $btn.Location = New-Object Drawing.Point(340,450)

    $btn.Add_Click({

        $grid.EndEdit()

        $rows = @($grid.Rows | Where-Object {
            [bool]$_.Cells["PERFIL"].Value
        })

        if ($rows.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show(
                "Selecciona almenys un perfil."
            )
            return
        }

        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "S'eliminaran els perfils seleccionats.`n`nAquesta acció no es pot desfer.`n`nVols continuar?",
            "Confirmar eliminació",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )

        if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) {
            return
        }

        $btn.Enabled = $false

        try {

            $progress.Maximum = $rows.Count
            $progress.Value   = 0

            $lsPath = Join-Path $script:chromePath "Local State"

            $ls = $null

            if (Test-Path $lsPath) {
                try {
                    $ls = Get-Content $lsPath -Raw -Encoding UTF8 | ConvertFrom-Json
                } catch {}
            }

            foreach ($row in $rows) {

                $id   = [string]$row.Cells["ID"].Value
                $name = [string]$row.Cells["Name"].Value

                $lbl.Text = "Eliminant: $name"
                $form.Refresh()

                $profilePath = Join-Path $script:chromePath $id

                if (Test-Path $profilePath) {
                    Remove-Item $profilePath -Recurse -Force -ErrorAction SilentlyContinue
                }

                # Eliminar entrada Local State
                if ($ls -and $ls.profile.info_cache.PSObject.Properties[$id]) {

                    $newCache = [ordered]@{}

                    foreach ($prop in $ls.profile.info_cache.PSObject.Properties) {

                        if ($prop.Name -ne $id) {
                            $newCache[$prop.Name] = $prop.Value
                        }
                    }

                    $ls.profile.info_cache = [PSCustomObject]$newCache
                }

                $progress.Value++
            }

            # Guardar Local State net
            if ($ls) {
                $ls | ConvertTo-Json -Depth 20 | Set-Content $lsPath -Encoding UTF8
            }

            [System.Windows.Forms.MessageBox]::Show(
                "Perfils eliminats correctament.",
                "GestionaChrome"
            )

            $form.Close()

        } catch {

            [System.Windows.Forms.MessageBox]::Show(
                "Error durant l'eliminació:`n$($_.Exception.Message)",
                "Error"
            )

        } finally {

            $btn.Enabled = $true
            $lbl.Text = ""
        }
    })

    $form.Controls.AddRange(@(
    $grid,
    $btnAll,
    $btnNone,
    $progress,
    $lbl,
    $btn
))
    $form.ShowDialog() | Out-Null
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
} catch {}

# --- CONFIG ---
$script:chromePath  = Join-Path $env:LOCALAPPDATA "Google\Chrome\User Data"
$script:tempExport  = Join-Path $env:TEMP "GestionaChrome_Export"
$script:tempImport  = Join-Path $env:TEMP "GestionaChrome_Import"
$script:profileRegex = '^(Default|Profile \d+)$'
$script:metaFile     = "profiles_meta.json"

# ==============================================================================
# FUNCIONS UTILITÀRIES
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

# Còpia segura amb reintents. Avisa si falla els 3 cops.
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
    Write-Warning "No s'ha pogut copiar: $src"
}

# Bookmarks amb fallback: si no hi ha Bookmarks però sí .bak, el restaura.
function Copy-BookmarksSafe($srcProfile, $dstProfile) {
    $b    = Join-Path $srcProfile "Bookmarks"
    $bBak = Join-Path $srcProfile "Bookmarks.bak"

    if (Test-Path $b) {
        Copy-Safe $b    $dstProfile
        Copy-Safe $bBak $dstProfile   # pot no existir; Copy-Safe ho gestiona
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

# Llegeix metadata visual i identificativa dels perfils.
# - Local State: nom i correu
# - Preferences: avatar, color i identitat visual
function Get-ProfileMeta($basePath) {

    $meta   = @{}
    $lsPath = Join-Path $basePath "Local State"

    # ------------------------------------------------------------
    # 1. LLEGIR LOCAL STATE
    # ------------------------------------------------------------
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

    # ------------------------------------------------------------
    # 2. LLEGIR PREFERENCES DE CADA PERFIL
    # ------------------------------------------------------------
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
			profile_color_seed     = 0
		}

        if (Test-Path $prefPath) {

            try {

                $pref = Get-Content $prefPath -Raw -Encoding UTF8 | ConvertFrom-Json

				if ($pref.profile) {

					if ($pref.profile.name) {
						$meta[$id].profile_name = $pref.profile.name
					}

					if ($pref.profile.gaia_name) {
						$meta[$id].account_name = $pref.profile.gaia_name
					}

					if ($null -ne $pref.profile.avatar_index) {
						$meta[$id].avatar_index = $pref.profile.avatar_index
					}

					if ($null -ne $pref.profile.using_default_avatar) {
						$meta[$id].using_default_avatar = $pref.profile.using_default_avatar
					}

					if ($null -ne $pref.profile.using_gaia_avatar) {
						$meta[$id].using_gaia_avatar = $pref.profile.using_gaia_avatar
					}

					if ($pref.profile.gaia_name) {
						$meta[$id].gaia_name = $pref.profile.gaia_name
					}

					if ($pref.profile.gaia_given_name) {
						$meta[$id].gaia_given_name = $pref.profile.gaia_given_name
					}

					if ($null -ne $pref.profile.profile_color_seed) {
						$meta[$id].profile_color_seed = $pref.profile.profile_color_seed
					}

					# FALLBACK EXTRA
					# Alguns Chromes guarden millor el nom aquí
					if ($pref.account_info -and $pref.account_info.Count -gt 0) {

						$acc = $pref.account_info[0]

						if (-not $meta[$id].account_name -and $acc.full_name) {
							$meta[$id].account_name = $acc.full_name
						}
					}
				}

            } catch {}
        }
    }

    return $meta
}

function Get-DisplayProfileName($metaItem) {

    # Prioritat absoluta:
    # nom del compte Google

    if ($metaItem.account_name) {
        return [string]$metaItem.account_name
    }

    # Fallbacks

    if ($metaItem.gaia_name) {
        return [string]$metaItem.gaia_name
    }

    if ($metaItem.email) {
        return [string]$metaItem.email
    }

    if ($metaItem.profile_name) {
        return [string]$metaItem.profile_name
    }

    return "Perfil Chrome"
}

# Merge mínim del Local State al PC de destí:
# afegeix NOMÉS els camps mínims (name, user_name, last_used) per a cada perfil seleccionat.
# NO copia extensions, preferences ni cap altra configuració.
function Merge-LocalStateMinim($importedMetaMap, $selectedIds, $destChromePath) {
    $lsDest = Join-Path $destChromePath "Local State"

    # Construïm o llegim el Local State de destí
    if (Test-Path $lsDest) {
        try   { $ls = Get-Content $lsDest -Raw -Encoding UTF8 | ConvertFrom-Json }
        catch { $ls = [PSCustomObject]@{ profile = [PSCustomObject]@{ info_cache = [PSCustomObject]@{} } } }
    } else {
        $ls = [PSCustomObject]@{ profile = [PSCustomObject]@{ info_cache = [PSCustomObject]@{} } }
    }

    # Assegurem que existeix profile.info_cache
    if (-not $ls.PSObject.Properties["profile"]) {
        $ls | Add-Member -MemberType NoteProperty -Name "profile" `
              -Value ([PSCustomObject]@{ info_cache = [PSCustomObject]@{} })
    }
    if (-not $ls.profile.PSObject.Properties["info_cache"]) {
        $ls.profile | Add-Member -MemberType NoteProperty -Name "info_cache" `
                      -Value ([PSCustomObject]@{})
    }

    foreach ($id in $selectedIds) {
        if (-not $ls.profile.info_cache.PSObject.Properties[$id]) {
            $entry = [PSCustomObject]@{

				name       = if ($importedMetaMap[$id]) { $importedMetaMap[$id].name } else { $id }

				user_name  = if ($importedMetaMap[$id]) { $importedMetaMap[$id].email } else { "" }

				last_used  = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")

				gaia_name = if ($importedMetaMap[$id].gaia_name) {
					$importedMetaMap[$id].gaia_name
				} else {
					""
				}

				gaia_given_name = if ($importedMetaMap[$id].gaia_given_name) {
					$importedMetaMap[$id].gaia_given_name
				} else {
					""
				}

				avatar_icon = "chrome://theme/IDR_PROFILE_AVATAR_$($importedMetaMap[$id].avatar_index)"

				using_default_avatar = if ($null -ne $importedMetaMap[$id].using_default_avatar) {
					$importedMetaMap[$id].using_default_avatar
				} else {
					$true
				}

				using_gaia_avatar = if ($null -ne $importedMetaMap[$id].using_gaia_avatar) {
					$importedMetaMap[$id].using_gaia_avatar
				} else {
					$false
				}

				profile_color_seed = if ($null -ne $importedMetaMap[$id].profile_color_seed) {
					$importedMetaMap[$id].profile_color_seed
				} else {
					0
				}
			}
            $ls.profile.info_cache | Add-Member -MemberType NoteProperty -Name $id -Value $entry
        }
    }

    try {
        Ensure-Dir (Split-Path $lsDest)
        $ls | ConvertTo-Json -Depth 100 | Set-Content $lsDest -Encoding UTF8
    } catch {
        Write-Warning "No s'ha pogut actualitzar Local State: $($_.Exception.Message)"
    }
}

# Genera un Preferences mínim i segur
# sense extensions ni configuracions problemàtiques
function New-MinimalPreferences($meta, $destProfilePath) {

    $prefObj = @{
        profile = @{
            name                   = $meta.name
            avatar_index           = $meta.avatar_index
            using_default_avatar   = $meta.using_default_avatar
            using_gaia_avatar      = $meta.using_gaia_avatar
            gaia_name              = $meta.gaia_name
            gaia_given_name        = $meta.gaia_given_name
            profile_color_seed     = $meta.profile_color_seed
        }
    }

    $prefPath = Join-Path $destProfilePath "Preferences"

    try {

        $prefObj |
            ConvertTo-Json -Depth 10 |
            Set-Content $prefPath -Encoding UTF8

    } catch {

        Write-Warning "No s'ha pogut generar Preferences per: $destProfilePath"
    }
}

# Valida el ZIP: ha de tenir almenys un perfil amb dades reconegudes.
# El temporal es neteja SEMPRE al finally.
function Test-ZipValid($zipPath, $tempDest) {
    try {
        if (Test-Path $tempDest) { Remove-Item $tempDest -Recurse -Force }
        Expand-Archive -Path $zipPath -DestinationPath $tempDest -Force

        $profiles = Get-ChromeProfileFolders $tempDest
        if ($profiles.Count -eq 0) { return $false }

        foreach ($p in $profiles) {
            $pp = $p.FullName
            if (
                (Test-Path (Join-Path $pp "Bookmarks"))     -or
                (Test-Path (Join-Path $pp "Bookmarks.bak")) -or
                (Test-Path (Join-Path $pp "History"))       -or
                (Test-Path (Join-Path $pp "Visited Links")) -or
                (Test-Path (Join-Path $pp "Top Sites"))     -or
                (Test-Path (Join-Path $pp "Shortcuts"))
            ) { return $true }
        }
        return $false
    }
    catch   { return $false }
    finally {
        # Neteja SEMPRE, fins i tot si ha fallat l'expansió
        # (el caller torna a expandir si la validació passa)
        if (Test-Path $tempDest) {
            Remove-Item $tempDest -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# Flag per evitar lògiques d'events durant canvis massius
$script:isBulkUpdate = $false

function Set-GridAll($grid, [bool]$checked) {
    $script:isBulkUpdate = $true
    try {
        $grid.SuspendLayout()
        foreach ($row in $grid.Rows) {
            if ($row.IsNewRow) { continue }

            # Respecta files deshabilitades (PERFIL read-only)
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

# Graella compartida Export/Import
function New-ProfileGrid {
    $g = New-Object Windows.Forms.DataGridView
    $g.Size                = New-Object Drawing.Size(800,280)
    $g.Location            = New-Object Drawing.Point(20,20)
    $g.AutoSizeColumnsMode = "Fill"
    $g.RowHeadersVisible   = $false
    $g.AllowUserToAddRows  = $false
    $g.SelectionMode       = "FullRowSelect"

    # ID ocult
    $g.Columns.Add("ID","ID") | Out-Null
    $g.Columns["ID"].Visible = $false

    # PERFIL (master checkbox)
    $colP = New-Object Windows.Forms.DataGridViewCheckBoxColumn
    $colP.Name       = "PERFIL"
    $colP.HeaderText = "Perfil"
    $colP.Width      = 50
    $colP.AutoSizeMode = "None"
    $g.Columns.Add($colP) | Out-Null

    # Nom i correu
    $g.Columns.Add("Name", "Nom perfil") | Out-Null
    $g.Columns.Add("Email","Correu")     | Out-Null

    # PREF i HIST
    $colPref = New-Object Windows.Forms.DataGridViewCheckBoxColumn
    $colPref.Name       = "PREF"
    $colPref.HeaderText = "Preferits"
    $g.Columns.Add($colPref) | Out-Null

    $colHist = New-Object Windows.Forms.DataGridViewCheckBoxColumn
    $colHist.Name       = "HIST"
    $colHist.HeaderText = "Historial"
    $g.Columns.Add($colHist) | Out-Null

    # Commit immediat — fix: param($sender,$e)
    $g.Add_CurrentCellDirtyStateChanged({
        param($sender, $e)
        if ($sender.IsCurrentCellDirty) {
            $sender.CommitEdit([System.Windows.Forms.DataGridViewDataErrorContexts]::Commit)
        }
    })

    # Lògica master:
    #   PREF o HIST marcats  → PERFIL es marca automàticament
    #   PERFIL desmarcat     → PREF i HIST es desmarquen
    $g.Add_CellValueChanged({
        param($sender, $e)
        if ($script:isBulkUpdate) { return }
        if ($e.RowIndex -lt 0) { return }
        $row = $sender.Rows[$e.RowIndex]

        $iPERFIL = $sender.Columns["PERFIL"].Index
        $iPREF   = $sender.Columns["PREF"].Index
        $iHIST   = $sender.Columns["HIST"].Index

        if ($e.ColumnIndex -eq $iPREF -or $e.ColumnIndex -eq $iHIST) {
            if (([bool]$row.Cells["PREF"].Value -or [bool]$row.Cells["HIST"].Value) `
                -and -not [bool]$row.Cells["PERFIL"].Value) {
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

# Botó d'acció estilitzat (reutilitzable)
function New-ActionButton($text, $color) {
    $b = New-Object Windows.Forms.Button
    $b.Text      = $text
    $b.Size      = New-Object Drawing.Size(200,50)
    $b.Font      = New-Object System.Drawing.Font("Segoe UI",11,[System.Drawing.FontStyle]::Bold)
    $b.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $b.BackColor = $color
    $b.ForeColor = [System.Drawing.Color]::White
    $b.FlatAppearance.BorderSize = 0
    return $b
}

# ==============================================================================
# LLANÇADOR
# ==============================================================================

$script:mode = $null

$launcher = New-Object Windows.Forms.Form
$launcher.Text            = "GestionaChrome v2.0"
$launcher.Size            = New-Object Drawing.Size(460,390)
$launcher.StartPosition   = "CenterScreen"
$launcher.FormBorderStyle = "FixedDialog"
$launcher.MaximizeBox     = $false
$launcher.MinimizeBox     = $false
$launcher.Font            = New-Object System.Drawing.Font("Segoe UI",10)

$colorVerd   = [System.Drawing.Color]::FromArgb(34,177,76)
$colorBlau   = [System.Drawing.Color]::FromArgb(0,123,255)
$colorVermell = [System.Drawing.Color]::FromArgb(192,57,43)

$btnExp = New-ActionButton "EXPORTAR" $colorVerd
$btnExp.Size     = New-Object Drawing.Size(300,60)
$btnExp.Location = New-Object Drawing.Point(75,60)
$btnExp.Font     = New-Object System.Drawing.Font("Segoe UI",12,[System.Drawing.FontStyle]::Bold)

$btnImp = New-ActionButton "IMPORTAR" $colorBlau
$btnImp.Size     = New-Object Drawing.Size(300,60)
$btnImp.Location = New-Object Drawing.Point(75,150)
$btnImp.Font     = New-Object System.Drawing.Font("Segoe UI",12,[System.Drawing.FontStyle]::Bold)

$btnDel = New-ActionButton "ELIMINAR" $colorVermell
$btnDel.Size     = New-Object Drawing.Size(300,60)
$btnDel.Location = New-Object Drawing.Point(75,240)
$btnDel.Font     = New-Object System.Drawing.Font("Segoe UI",12,[System.Drawing.FontStyle]::Bold)

$btnExp.Add_Click({ $script:mode = "export"; $launcher.Close() })
$btnImp.Add_Click({ $script:mode = "import"; $launcher.Close() })
$btnDel.Add_Click({ $script:mode = "delete"; $launcher.Close() })

$launcher.Controls.AddRange(@($btnExp,$btnImp,$btnDel))
$launcher.ShowDialog() | Out-Null

if (-not $script:mode) { exit }

# ==============================================================================
# EXPORTACIÓ
# ==============================================================================

if ($script:mode -eq "export") {

    if (-not (Check-Chrome)) { exit }

    if (-not (Test-Path $script:chromePath)) {
        [System.Windows.Forms.MessageBox]::Show("No s'han trobat dades de Chrome.","Error"); exit
    }

    $profileFolders = Get-ChromeProfileFolders $script:chromePath
    if ($profileFolders.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("No s'han trobat perfils de Chrome.","Error"); exit
    }

    $meta = Get-ProfileMeta $script:chromePath

    $form = New-Object Windows.Forms.Form
    $form.Text          = "Exportació — Selecciona perfils i dades"
    $form.Size          = New-Object Drawing.Size(880,580)
    $form.StartPosition = "CenterScreen"
    $form.Font          = New-Object System.Drawing.Font("Segoe UI",10)

    $grid = New-ProfileGrid

    foreach ($p in $profileFolders) {
        $id    = $p.Name
        $name = if ($meta[$id]) {
		Get-DisplayProfileName $meta[$id]
		} else {
			$id
		}
		
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

    $progress          = New-Object Windows.Forms.ProgressBar
    $progress.Location = New-Object Drawing.Point(20,370)
    $progress.Size     = New-Object Drawing.Size(820,20)

    $lbl          = New-Object Windows.Forms.Label
    $lbl.Location = New-Object Drawing.Point(20,400)
    $lbl.Size     = New-Object Drawing.Size(820,20)

    $btn          = New-ActionButton "EXPORTAR" $colorVerd
    $btn.Location = New-Object Drawing.Point(340,450)

    $btn.Add_Click({
        $grid.EndEdit()

        $rows = @($grid.Rows | Where-Object { [bool]$_.Cells["PERFIL"].Value })
        if ($rows.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("Selecciona almenys un perfil."); return
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

            # Metadata lleugera per a la UI d'import (nom + correu)
            $metaExport = @{}
            foreach ($row in $rows) {
                $id = [string]$row.Cells["ID"].Value
                $metaExport[$id] = @{
                    name           = [string]$row.Cells["Name"].Value
					email          = [string]$row.Cells["Email"].Value

					profile_name   = $meta[$id].profile_name
					account_name   = $meta[$id].account_name
                
                    avatar_index           = $meta[$id].avatar_index
                    using_default_avatar   = $meta[$id].using_default_avatar
                    using_gaia_avatar      = $meta[$id].using_gaia_avatar
                    gaia_name              = $meta[$id].gaia_name
                    gaia_given_name        = $meta[$id].gaia_given_name
                    profile_color_seed     = $meta[$id].profile_color_seed
                }
            }
            $metaExport | ConvertTo-Json -Depth 5 |
                Set-Content (Join-Path $script:tempExport $script:metaFile) -Encoding UTF8

            $progress.Maximum = $rows.Count
            $progress.Value   = 0

            foreach ($row in $rows) {
                $id   = [string]$row.Cells["ID"].Value
                $name = [string]$row.Cells["Name"].Value
                $lbl.Text = "Exportant: $name"
                $form.Refresh()

                $src = Join-Path $script:chromePath $id
                $dst = Join-Path $script:tempExport $id
                Ensure-Dir $dst

                # Avatar (no porta extensions)
                Copy-Safe (Join-Path $src "Avatars")                    $dst
                Copy-Safe (Join-Path $src "Google Profile Picture.png") $dst

                if ([bool]$row.Cells["PREF"].Value) {
                    Copy-BookmarksSafe $src $dst
                    Copy-Safe (Join-Path $src "Favicons")         $dst
                    Copy-Safe (Join-Path $src "Favicons-journal") $dst
                    Copy-Safe (Join-Path $src "Favicons-wal")     $dst
                    Copy-Safe (Join-Path $src "Favicons-shm")     $dst
                }

                if ([bool]$row.Cells["HIST"].Value) {
                    Copy-Safe (Join-Path $src "History")          $dst
                    Copy-Safe (Join-Path $src "History-journal")  $dst
                    Copy-Safe (Join-Path $src "History-wal")      $dst
                    Copy-Safe (Join-Path $src "History-shm")      $dst
                    Copy-Safe (Join-Path $src "Visited Links")    $dst
                    Copy-Safe (Join-Path $src "Top Sites")        $dst
                    Copy-Safe (Join-Path $src "Shortcuts")        $dst
                    # Favicons per historial visual (si no s'han copiat ja per PREF)
                    if (-not [bool]$row.Cells["PREF"].Value) {
                        Copy-Safe (Join-Path $src "Favicons")         $dst
                        Copy-Safe (Join-Path $src "Favicons-journal") $dst
                        Copy-Safe (Join-Path $src "Favicons-wal")     $dst
                        Copy-Safe (Join-Path $src "Favicons-shm")     $dst
                    }
                }

                $progress.Value++
            }

            $lbl.Text = "Comprimint..."
            $form.Refresh()

            if (Test-Path $sfd.FileName) { Remove-Item $sfd.FileName -Force }
            Compress-Archive -Path (Join-Path $script:tempExport "*") `
                             -DestinationPath $sfd.FileName -Force

            [System.Windows.Forms.MessageBox]::Show(
                "Exportació completada!`n`n$($sfd.FileName)",
                "GestionaChrome")
            $form.Close()
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show(
                "Error durant l'exportació:`n$($_.Exception.Message)","Error")
        }
        finally {
            if (Test-Path $script:tempExport) { Remove-Item $script:tempExport -Recurse -Force }
            $btn.Enabled = $true
            $lbl.Text    = ""
        }
    })

    $form.Controls.AddRange(@($grid,$btnAll,$btnNone,$progress,$lbl,$btn))
    $form.ShowDialog() | Out-Null
}

# ==============================================================================
# IMPORTACIÓ
# ==============================================================================

elseif ($script:mode -eq "import") {

    if (-not (Check-Chrome)) { exit }

    $ofd = New-Object System.Windows.Forms.OpenFileDialog
    $ofd.Filter = "Zip (*.zip)|*.zip"
    if ($ofd.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { exit }

    # Validació (neteja el temp al finally intern)
    if (-not (Test-ZipValid $ofd.FileName $script:tempImport)) {
        [System.Windows.Forms.MessageBox]::Show(
            "El fitxer seleccionat no és un arxiu vàlid de GestionaChrome.",
            "Arxiu no vàlid")
        exit
    }

    # Tornem a expandir perquè Test-ZipValid neteja el temp al finally
    try {
        Expand-Archive -Path $ofd.FileName -DestinationPath $script:tempImport -Force
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Error en descomprimir el fitxer.","Error"); exit
    }

    # Llegim metadata del ZIP
    $importMeta = @{}
    $metaPath = Join-Path $script:tempImport $script:metaFile
    if (Test-Path $metaPath) {
        try {
            $raw = Get-Content $metaPath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($prop in $raw.PSObject.Properties) {
               $importMeta[$prop.Name] = @{
					name                   = if ($prop.Value.name) { $prop.Value.name } else { $prop.Name }
					email                  = if ($prop.Value.email) { $prop.Value.email } else { "" }

					profile_name           = if ($prop.Value.profile_name) { $prop.Value.profile_name } else { "" }
					account_name           = if ($prop.Value.account_name) { $prop.Value.account_name } else { "" }                
                    avatar_index           = if ($null -ne $prop.Value.avatar_index) { $prop.Value.avatar_index } else { 0 }
                    using_default_avatar   = if ($null -ne $prop.Value.using_default_avatar) { $prop.Value.using_default_avatar } else { $true }
                    using_gaia_avatar      = if ($null -ne $prop.Value.using_gaia_avatar) { $prop.Value.using_gaia_avatar } else { $false }
                
                    gaia_name              = if ($prop.Value.gaia_name) { $prop.Value.gaia_name } else { "" }
                    gaia_given_name        = if ($prop.Value.gaia_given_name) { $prop.Value.gaia_given_name } else { "" }
                
                    profile_color_seed     = if ($null -ne $prop.Value.profile_color_seed) { $prop.Value.profile_color_seed } else { 0 }
                }
            }
        } catch {}
    }

    $importProfiles = Get-ChromeProfileFolders $script:tempImport
    if ($importProfiles.Count -eq 0) {
        if (Test-Path $script:tempImport) { Remove-Item $script:tempImport -Recurse -Force }
        [System.Windows.Forms.MessageBox]::Show("No s'han trobat perfils al ZIP.","Error"); exit
    }

    $form = New-Object Windows.Forms.Form
    $form.Text          = "Importació — Selecciona què importar"
    $form.Size          = New-Object Drawing.Size(880,580)
    $form.StartPosition = "CenterScreen"
    $form.Font          = New-Object System.Drawing.Font("Segoe UI",10)

    $grid = New-ProfileGrid

    foreach ($p in $importProfiles) {
        $id         = $p.Name
        $folderPath = $p.FullName
		$name = if ($importMeta[$id]) {
			Get-DisplayProfileName $importMeta[$id]
		} else {
			$id
		}
		
        $email      = if ($importMeta[$id]) { $importMeta[$id].email } else { "" }

        $hasPref = (Test-Path (Join-Path $folderPath "Bookmarks"))     -or
                   (Test-Path (Join-Path $folderPath "Bookmarks.bak")) -or
                   (Test-Path (Join-Path $folderPath "Favicons"))

        $hasHist = (Test-Path (Join-Path $folderPath "History"))        -or
                   (Test-Path (Join-Path $folderPath "History-journal")) -or
                   (Test-Path (Join-Path $folderPath "Visited Links"))   -or
                   (Test-Path (Join-Path $folderPath "Top Sites"))       -or
                   (Test-Path (Join-Path $folderPath "Shortcuts"))

        $rowIdx  = $grid.Rows.Add($id, ($hasPref -or $hasHist), $name, $email, $hasPref, $hasHist)

        if (-not $hasPref) {
            $grid.Rows[$rowIdx].Cells["PREF"].ReadOnly  = $true
            $grid.Rows[$rowIdx].Cells["PREF"].Style.BackColor = [Drawing.Color]::LightGray
        }
        if (-not $hasHist) {
            $grid.Rows[$rowIdx].Cells["HIST"].ReadOnly  = $true
            $grid.Rows[$rowIdx].Cells["HIST"].Style.BackColor = [Drawing.Color]::LightGray
        }
        if (-not $hasPref -and -not $hasHist) {
            $grid.Rows[$rowIdx].Cells["PERFIL"].ReadOnly  = $true
            $grid.Rows[$rowIdx].Cells["PERFIL"].Value     = $false
            $grid.Rows[$rowIdx].Cells["PERFIL"].Style.BackColor = [Drawing.Color]::LightGray
        }
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

    $progress          = New-Object Windows.Forms.ProgressBar
    $progress.Location = New-Object Drawing.Point(20,370)
    $progress.Size     = New-Object Drawing.Size(820,20)

    $lbl          = New-Object Windows.Forms.Label
    $lbl.Location = New-Object Drawing.Point(20,400)
    $lbl.Size     = New-Object Drawing.Size(820,20)

    $btn          = New-ActionButton "IMPORTAR" $colorBlau
    $btn.Location = New-Object Drawing.Point(340,450)

    $btn.Add_Click({
        $grid.EndEdit()

        $rows = @($grid.Rows | Where-Object { [bool]$_.Cells["PERFIL"].Value })
        if ($rows.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("Selecciona almenys un perfil."); return
        }

        $btn.Enabled = $false
        try {
            Ensure-Dir $script:chromePath

            # ---------------------------------------------------------------
            # Merge mínim del Local State:
            # Afegeix name, user_name i last_used per a cada perfil seleccionat.
            # Chrome necessita aquesta entrada per reconèixer el perfil.
            # NO copia configuració d'extensions ni preferències.
            # ---------------------------------------------------------------
            $selectedIds = $rows | ForEach-Object { [string]$_.Cells["ID"].Value }
            Merge-LocalStateMinim $importMeta $selectedIds $script:chromePath

            $progress.Maximum = $rows.Count
            $progress.Value   = 0

            foreach ($row in $rows) {
                $id   = [string]$row.Cells["ID"].Value
                $name = [string]$row.Cells["Name"].Value
                $lbl.Text = "Important: $name"
                $form.Refresh()

                $src = Join-Path $script:tempImport $id
                $dst = Join-Path $script:chromePath $id
                Ensure-Dir $dst

                # Generem un Preferences mínim per restaurar
                # nom, avatar i identitat visual del perfil
                if ($importMeta[$id]) {
                    New-MinimalPreferences $importMeta[$id] $dst
                }
                
                # Avatar
                Copy-Safe (Join-Path $src "Avatars")                    $dst
                Copy-Safe (Join-Path $src "Google Profile Picture.png") $dst

                if ([bool]$row.Cells["PREF"].Value) {
                    Copy-Safe (Join-Path $src "Bookmarks")        $dst
                    Copy-Safe (Join-Path $src "Bookmarks.bak")    $dst
                    Copy-Safe (Join-Path $src "Favicons")         $dst
                    Copy-Safe (Join-Path $src "Favicons-journal") $dst
                    Copy-Safe (Join-Path $src "Favicons-wal")     $dst
                    Copy-Safe (Join-Path $src "Favicons-shm")     $dst
                }

                if ([bool]$row.Cells["HIST"].Value) {
                    Copy-Safe (Join-Path $src "History")          $dst
                    Copy-Safe (Join-Path $src "History-journal")  $dst
                    Copy-Safe (Join-Path $src "History-wal")      $dst
                    Copy-Safe (Join-Path $src "History-shm")      $dst
                    Copy-Safe (Join-Path $src "Visited Links")    $dst
                    Copy-Safe (Join-Path $src "Top Sites")        $dst
                    Copy-Safe (Join-Path $src "Shortcuts")        $dst
                    if (-not [bool]$row.Cells["PREF"].Value) {
                        Copy-Safe (Join-Path $src "Favicons")         $dst
                        Copy-Safe (Join-Path $src "Favicons-journal") $dst
                        Copy-Safe (Join-Path $src "Favicons-wal")     $dst
                        Copy-Safe (Join-Path $src "Favicons-shm")     $dst
                    }
                }

                $progress.Value++
            }

            [System.Windows.Forms.MessageBox]::Show(
                "Importació completada!`n`nJa pots obrir Google Chrome.",
                "GestionaChrome")
            $form.Close()
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show(
                "Error durant la importació:`n$($_.Exception.Message)","Error")
        }
        finally {
            if (Test-Path $script:tempImport) { Remove-Item $script:tempImport -Recurse -Force }
            $btn.Enabled = $true
            $lbl.Text    = ""
        }
    })

      $form.Add_FormClosed({
        if (Test-Path $script:tempImport) { Remove-Item $script:tempImport -Recurse -Force }
    })

    $form.Controls.AddRange(@($grid,$btnAll,$btnNone,$progress,$lbl,$btn))
    $form.ShowDialog() | Out-Null
}



# ==============================================================================
# ELIMINACIÓ DE PERFILS
# ==============================================================================

elseif ($script:mode -eq "delete") {

    if (-not (Check-Chrome)) { exit }

    $profileFolders = Get-ChromeProfileFolders $script:chromePath

    if ($profileFolders.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show(
            "No s'han trobat perfils de Chrome.",
            "GestionaChrome"
        )
        exit
    }

    $meta = Get-ProfileMeta $script:chromePath

    $form = New-Object Windows.Forms.Form
    $form.Text          = "Eliminar perfils"
    $form.Size          = New-Object Drawing.Size(880,580)
    $form.StartPosition = "CenterScreen"
    $form.Font          = New-Object System.Drawing.Font("Segoe UI",10)

    $grid = New-ProfileGrid

    foreach ($p in $profileFolders) {

        $id = $p.Name

        $name = if ($meta[$id]) {
            Get-DisplayProfileName $meta[$id]
        } else {
            $id
        }

        $email = if ($meta[$id]) {
            $meta[$id].email
        } else {
            ""
        }

        # Per eliminar:
        # PERFIL = false inicialment
        # PREF/HIST només visuals
        $grid.Rows.Add($id, $false, $name, $email, $true, $true) | Out-Null
    }

# ------------------------------------------------------------
# BOTONS MARCAR / DESMARCAR
# ------------------------------------------------------------

$btnAll = New-Object Windows.Forms.Button
$btnAll.Text = "MARCA-HO TOT"
$btnAll.Size = New-Object Drawing.Size(140,35)
$btnAll.Location = New-Object Drawing.Point(20,320)

# ESTIL
$btnAll.FlatStyle = "Flat"
$btnAll.BackColor = [Drawing.Color]::WhiteSmoke

$btnAll.Add_Click({

    foreach ($r in $grid.Rows) {

        if (-not $r.Cells["PERFIL"].ReadOnly) {
            $r.Cells["PERFIL"].Value = $true
        }
    }
})

$btnNone = New-Object Windows.Forms.Button
$btnNone.Text = "DESMARCA-HO TOT"
$btnNone.Size = New-Object Drawing.Size(140,35)
$btnNone.Location = New-Object Drawing.Point(170,320)

# ESTIL
$btnNone.FlatStyle = "Flat"
$btnNone.BackColor = [Drawing.Color]::WhiteSmoke

$btnNone.Add_Click({

    foreach ($r in $grid.Rows) {
        $r.Cells["PERFIL"].Value = $false
    }
})

    $progress = New-Object Windows.Forms.ProgressBar
    $progress.Location = New-Object Drawing.Point(20,370)
    $progress.Size     = New-Object Drawing.Size(820,20)

    $lbl = New-Object Windows.Forms.Label
    $lbl.Location = New-Object Drawing.Point(20,400)
    $lbl.Size     = New-Object Drawing.Size(820,20)

    $btn = New-ActionButton "ELIMINAR" $colorVermell
    $btn.Location = New-Object Drawing.Point(340,450)

    $btn.Add_Click({

        $grid.EndEdit()

        $rows = @($grid.Rows | Where-Object {
            [bool]$_.Cells["PERFIL"].Value
        })

        if ($rows.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show(
                "Selecciona almenys un perfil."
            )
            return
        }

        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "S'eliminaran els perfils seleccionats.`n`nAquesta acció no es pot desfer.`n`nVols continuar?",
            "Confirmar eliminació",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )

        if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) {
            return
        }

        $btn.Enabled = $false

        try {

            $progress.Maximum = $rows.Count
            $progress.Value   = 0

            $lsPath = Join-Path $script:chromePath "Local State"

            $ls = $null

            if (Test-Path $lsPath) {
                try {
                    $ls = Get-Content $lsPath -Raw -Encoding UTF8 | ConvertFrom-Json
                } catch {}
            }

            foreach ($row in $rows) {

                $id   = [string]$row.Cells["ID"].Value
                $name = [string]$row.Cells["Name"].Value

                $lbl.Text = "Eliminant: $name"
                $form.Refresh()

                $profilePath = Join-Path $script:chromePath $id

                if (Test-Path $profilePath) {
                    Remove-Item $profilePath -Recurse -Force -ErrorAction SilentlyContinue
                }

                # Eliminar entrada Local State
                if ($ls -and $ls.profile.info_cache.PSObject.Properties[$id]) {

                    $newCache = [ordered]@{}

                    foreach ($prop in $ls.profile.info_cache.PSObject.Properties) {

                        if ($prop.Name -ne $id) {
                            $newCache[$prop.Name] = $prop.Value
                        }
                    }

                    $ls.profile.info_cache = [PSCustomObject]$newCache
                }

                $progress.Value++
            }

            # Guardar Local State net
            if ($ls) {
                $ls | ConvertTo-Json -Depth 20 | Set-Content $lsPath -Encoding UTF8
            }

            [System.Windows.Forms.MessageBox]::Show(
                "Perfils eliminats correctament.",
                "GestionaChrome"
            )

            $form.Close()

        } catch {

            [System.Windows.Forms.MessageBox]::Show(
                "Error durant l'eliminació:`n$($_.Exception.Message)",
                "Error"
            )

        } finally {

            $btn.Enabled = $true
            $lbl.Text = ""
        }
    })

    $form.Controls.AddRange(@(
    $grid,
    $btnAll,
    $btnNone,
    $progress,
    $lbl,
    $btn
))
    $form.ShowDialog() | Out-Null
}
