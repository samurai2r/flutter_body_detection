# PowerShell script to fix the body_detection plugin
# This script updates the CameraSession.kt file to work with newer AndroidX Lifecycle versions

Write-Host "Fixing body_detection plugin..." -ForegroundColor Green
Write-Host ""

$cameraSessionPath = "C:\Users\rasha\Documents\GitHub\flutter_body_detection\android\src\main\kotlin\com\u0x48lab\body_detection\CameraSession.kt"

if (Test-Path $cameraSessionPath) {
    Write-Host "Processing CameraSession.kt..." -ForegroundColor Yellow
    
    # Create backup if it doesn't exist
    $backupPath = "$cameraSessionPath.bak"
    if (-not (Test-Path $backupPath)) {
        Copy-Item $cameraSessionPath $backupPath
    }
    
    # Read the file content
    $content = Get-Content $cameraSessionPath -Raw
    
    # Update the CustomLifecycle class to implement the new LifecycleOwner interface
    $updatedContent = $content -replace "class CustomLifecycle\s*:\s*LifecycleOwner\s*\{(?:[^{}]|(?<open>\{)|(?<close-open>\}))*\}", @"
class CustomLifecycle : LifecycleOwner {
    private val lifecycleRegistry = LifecycleRegistry(this)

    init {
        lifecycleRegistry.currentState = Lifecycle.State.CREATED
    }

    fun start() {
        lifecycleRegistry.currentState = Lifecycle.State.STARTED
    }

    fun stop() {
        lifecycleRegistry.currentState = Lifecycle.State.CREATED
    }

    fun destroy() {
        lifecycleRegistry.currentState = Lifecycle.State.DESTROYED
    }

    override val lifecycle: Lifecycle
        get() = lifecycleRegistry
}
"@
    
    # Write the updated content back to the file
    Set-Content -Path $cameraSessionPath -Value $updatedContent
    Write-Host "  - Updated CustomLifecycle class in CameraSession.kt" -ForegroundColor Green
} else {
    Write-Host "CameraSession.kt not found at the expected path!" -ForegroundColor Red
    Write-Host "Please provide the correct path to the file." -ForegroundColor Red
}

Write-Host ""
Write-Host "Now try building your Flutter app with:" -ForegroundColor Cyan
Write-Host "flutter build apk --debug --android-skip-build-dependency-validation" -ForegroundColor Yellow
Write-Host ""

Write-Host "Press any key to continue..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
