# Add SSH Key to GitHub

## Step 1: Copy Your SSH Key

Your SSH key is:
```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOCFdTMo1ONES2+EVKOXFHE2cbRN3IQQVzfL49f3JTVR aqsa.altaf@bitandbytes.net
```

## Step 2: Add to GitHub

1. **Go to GitHub Settings:**
   - Visit: https://github.com/settings/keys
   - Or: GitHub → Your Profile → Settings → SSH and GPG keys

2. **Add New SSH Key:**
   - Click **"New SSH key"** button
   - **Title:** "My Computer" (or any name)
   - **Key type:** Authentication Key
   - **Key:** Paste the entire key above (starting with `ssh-ed25519`)
   - Click **"Add SSH key"**

3. **Verify it works:**
   ```bash
   ssh -T git@github.com
   ```
   You should see: "Hi AqsaAltaf1! You've successfully authenticated..."

## Step 3: Change Git Remote to SSH

After adding the key, run:
```bash
cd /home/bnb/Desktop/discourse_theme/compound-governance-widget
git remote set-url origin git@github.com:AqsaAltaf1/compound-governance-widget.git
```

## Step 4: Push Your Code

```bash
git push -u origin main
```

This should work without asking for a password!

