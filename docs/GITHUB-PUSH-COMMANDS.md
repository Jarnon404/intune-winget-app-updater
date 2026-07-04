# GitHub push -komennot

Aja projektikansion juuressa:

```powershell
git init
git add .
git commit -m "Initial release: Intune Winget App Updater v10.3"

git remote add origin https://github.com/<username>/intune-winget-app-updater.git
git branch -M main
git push -u origin main
```

Jos repo on jo olemassa ja siinä on sisältöä:

```powershell
git pull origin main --allow-unrelated-histories
git push -u origin main
```
