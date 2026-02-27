# Claude-ChromeDevTools-Final.ps1 — 後方互換ラッパー
# v1.3.0 以降は Claude-DevTools.ps1 を使用してください
Write-Warning "⚠️ このスクリプトは非推奨です。Claude-DevTools.ps1 -Browser chrome を使用してください。"
Write-Host ""

# パラメータを転送して統合スクリプトを実行
& "$PSScriptRoot\Claude-DevTools.ps1" -Browser chrome
