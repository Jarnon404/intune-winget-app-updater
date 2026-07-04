# GitHub push commands

Run from the repository root:

```powershell
git init
git add .
git commit -m "Initial release: Intune Winget App Updater v10.3"

git remote add origin https://github.com/<username>/intune-winget-app-updater.git
git branch -M main
git push -u origin main
```

If the remote repository already exists and contains files:

```powershell
git pull origin main --allow-unrelated-histories
git push -u origin main
```