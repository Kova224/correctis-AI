# =============================================================
# Correctis - Script de mise en route automatique (Windows)
# Usage : ouvrir PowerShell dans correctis_app/ et lancer :
#   .\setup_and_run.ps1
# =============================================================

$ErrorActionPreference = "Stop"

Write-Host "==> Vérification de Flutter..." -ForegroundColor Cyan
$flutter = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $flutter) {
    Write-Host "❌ Flutter n'est pas installé ou pas dans le PATH." -ForegroundColor Red
    Write-Host "   Installe-le depuis https://docs.flutter.dev/get-started/install/windows" -ForegroundColor Yellow
    exit 1
}
flutter --version

# 1. Génère les dossiers natifs (android/, ios/) si absents
if (-not (Test-Path "android") -or -not (Test-Path "ios")) {
    Write-Host "==> Génération des dossiers natifs..." -ForegroundColor Cyan
    flutter create . --project-name correctis --org app.correctis
} else {
    Write-Host "==> Dossiers natifs déjà présents — skip flutter create" -ForegroundColor Green
}

# 2. Ajoute les permissions caméra dans AndroidManifest.xml
$manifest = "android\app\src\main\AndroidManifest.xml"
if (Test-Path $manifest) {
    $content = Get-Content $manifest -Raw
    if ($content -notmatch "android.permission.CAMERA") {
        Write-Host "==> Ajout des permissions Android..." -ForegroundColor Cyan
        $perms = @"
    <uses-permission android:name="android.permission.CAMERA"/>
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>
    <uses-permission android:name="android.permission.READ_MEDIA_IMAGES"/>
"@
        $content = $content -replace "(?=<application)", "$perms`n    "
        Set-Content -Path $manifest -Value $content -NoNewline
        Write-Host "    ✓ Permissions ajoutées dans AndroidManifest.xml" -ForegroundColor Green
    } else {
        Write-Host "==> Permissions Android déjà présentes" -ForegroundColor Green
    }
}

# 3. Ajoute les permissions iOS dans Info.plist
$plist = "ios\Runner\Info.plist"
if (Test-Path $plist) {
    $content = Get-Content $plist -Raw
    if ($content -notmatch "NSCameraUsageDescription") {
        Write-Host "==> Ajout des permissions iOS..." -ForegroundColor Cyan
        $perms = @"
	<key>NSCameraUsageDescription</key>
	<string>Correctis utilise l'appareil photo pour scanner les copies des élèves.</string>
	<key>NSPhotoLibraryUsageDescription</key>
	<string>Correctis a besoin d'accéder à vos photos pour importer des sujets ou des copies.</string>
"@
        $content = $content -replace "</dict>", "$perms`n</dict>"
        Set-Content -Path $plist -Value $content -NoNewline
        Write-Host "    ✓ Permissions ajoutées dans Info.plist" -ForegroundColor Green
    } else {
        Write-Host "==> Permissions iOS déjà présentes" -ForegroundColor Green
    }
}

# 4. Installe les dépendances
Write-Host "==> Installation des packages..." -ForegroundColor Cyan
flutter pub get

# 5. Vérifie la santé
Write-Host "==> flutter doctor (résumé)..." -ForegroundColor Cyan
flutter doctor

# 6. Lance l'app
Write-Host ""
Write-Host "==> Lancement de l'app sur le device disponible..." -ForegroundColor Cyan
Write-Host "    Compte démo : demo@correctis.app / demo1234" -ForegroundColor Yellow
Write-Host ""
flutter run
