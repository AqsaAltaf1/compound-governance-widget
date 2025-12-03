# Fix GitHub Authentication

GitHub no longer accepts passwords. You need a **Personal Access Token (PAT)**.

## Quick Fix: Use Personal Access Token

### Step 1: Create Personal Access Token

1. **Go to GitHub Settings:**
   - Visit: https://github.com/settings/tokens
   - Or: GitHub → Your Profile → Settings → Developer settings → Personal access tokens → Tokens (classic)

2. **Generate New Token:**
   - Click **"Generate new token"** → **"Generate new token (classic)"**
   - **Note:** Give it a name like "Discourse Widget"
   - **Expiration:** Choose "90 days" or "No expiration"
   - **Select scopes:** Check ✅ **"repo"** (this gives full repository access)
   - Click **"Generate token"**

3. **Copy the Token:**
   - ⚠️ **IMPORTANT:** Copy the token immediately! You won't see it again.
   - It looks like: `ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx`

### Step 2: Use Token for Push

When the script asks for password, **paste the token instead**:

```bash
Username for 'https://github.com': AqsaAltaf1
Password for 'https://AqsaAltaf1@github.com': [PASTE YOUR TOKEN HERE]
```

---

## Alternative: Use SSH (More Secure)

### Step 1: Generate SSH Key (if you don't have one)

```bash
ssh-keygen -t ed25519 -C "your_email@example.com"
# Press Enter to accept default location
# Press Enter for no passphrase (or set one)
```

### Step 2: Add SSH Key to GitHub

```bash
# Copy your public key
cat ~/.ssh/id_ed25519.pub
```

1. **Go to:** https://github.com/settings/keys
2. Click **"New SSH key"**
3. **Title:** "My Computer"
4. **Key:** Paste the output from above
5. Click **"Add SSH key"**

### Step 3: Change Remote to SSH

```bash
cd /home/bnb/Desktop/discourse_theme/compound-governance-widget
git remote set-url origin git@github.com:AqsaAltaf1/compound-governance-widget.git
git push -u origin main
```

---

## Quick Solution: Use Token Right Now

1. **Cancel the current command** (Ctrl+C if it's still waiting)

2. **Create token:** https://github.com/settings/tokens/new

3. **Run push manually with token:**
   ```bash
   cd /home/bnb/Desktop/discourse_theme/compound-governance-widget
   git push -u origin main
   ```
   - Username: `AqsaAltaf1`
   - Password: **[Paste your token here]**

---

## Or: Use GitHub CLI (Easiest)

```bash
# Install GitHub CLI
sudo snap install gh

# Login
gh auth login

# Then push
git push -u origin main
```

