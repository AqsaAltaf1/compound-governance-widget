# Discourse Sandbox Setup Guide

## Why Use a Sandbox?

**✅ YES, you should use a sandbox account!** Testing on a live production site is risky and not recommended. A sandbox gives you:
- Safe testing environment
- No risk to production data
- Ability to experiment freely
- Easy reset if something breaks

## 🚀 Getting Started (No Sandbox Yet?)

**If you don't have a sandbox URL yet, here are your options:**

### ⚡ Fastest Option: Request Free Sandbox (5 minutes to request, 24-48 hours to receive)

1. **Create Meta Discourse Account** (if you don't have one):
   - Go to: https://meta.discourse.org
   - Click "Sign Up" and create an account
   - Verify your email

2. **Request Sandbox:**
   - Go to: https://meta.discourse.org/t/request-a-free-discourse-sandbox-for-theme-development/50872
   - Read the first post for requirements
   - Reply to the topic saying you need a sandbox for theme development
   - Wait for a private message (usually 24-48 hours)

3. **You'll Receive:**
   - Sandbox URL (e.g., `https://yoursandbox.discourse.group`)
   - Login credentials
   - The first account you create will be admin automatically!

### 🖥️ Alternative: Set Up Local Discourse (30-60 minutes, requires Docker)

If you want to test immediately without waiting, you can run Discourse locally:

**Quick Local Setup:**

```bash
# 1. Install Docker (if not installed)
# Ubuntu/Debian:
sudo apt-get update
sudo apt-get install docker.io docker-compose

# 2. Clone Discourse
git clone https://github.com/discourse/discourse.git
cd discourse

# 3. Run setup script
./discourse-setup
```

**Follow the prompts:**
- It will ask for hostname (use `localhost` or `127.0.0.1`)
- It will ask for email (for admin account)
- It will set up everything automatically

**Access your local Discourse:**
- URL: `http://localhost` (or the port it assigns)
- First account created = admin automatically!

**Note:** Local setup requires:
- Docker installed
- 4GB+ RAM
- Some disk space (~2-3GB)

---

## Option 1: Free Discourse Sandbox (Recommended)

Discourse provides **free sandbox instances** for theme developers:

### Step 1: Request a Sandbox
1. Go to: https://meta.discourse.org/t/request-a-free-discourse-sandbox-for-theme-development/50872
2. Create a Meta Discourse account if you don't have one
3. Reply to the topic requesting a sandbox
4. You'll receive credentials via private message (usually within 24-48 hours)

### Step 2: Access Your Sandbox
- You'll get a URL like: `https://yoursandbox.discourse.group`
- Login credentials will be provided
- **The first account created is automatically an admin account**

### Step 3: Create Additional Admin Accounts (Optional)
If you need more admin accounts:

#### Method 1: Via Admin Panel (Easiest)

**Step-by-step:**

1. **Login as Admin:**
   - Go to your sandbox URL (e.g., `https://yoursandbox.discourse.group`)
   - Login with your existing admin account

2. **Navigate to Admin Panel:**
   - Look for the **"Admin"** button in the top navigation bar (or click your profile picture → Admin)
   - If you don't see it, make sure you're logged in as an admin

3. **Go to Users:**
   - In the Admin panel, click **"Users"** in the left sidebar
   - This shows a list of all users on the site

4. **Find the User:**
   - Use the search box at the top to find the user by username or email
   - Or scroll through the list
   - Click on the **username** of the user you want to make admin

5. **Grant Admin:**
   - You'll see the user's profile page
   - Scroll down to find the **"Grant Admin"** section (usually near the bottom)
   - Click the **"Grant Admin"** button
   - Confirm the action if prompted

6. **Verify:**
   - The user should now have admin privileges
   - They'll see the "Admin" button in their navigation when they login

#### Method 2: Via Email Invitation (Create New Admin)

**Step-by-step:**

1. **Login as Admin:**
   - Go to your sandbox and login as admin

2. **Go to Invite:**
   - Click **Admin → Users**
   - Click the **"Invite"** button (usually at the top right)

3. **Fill in Details:**
   - Enter the **email address** of the person you want to invite
   - In the **"Group"** or **"Role"** dropdown, select **"Admin"** (or "Administrators")
   - Optionally add a custom message

4. **Send Invitation:**
   - Click **"Send Invitation"**
   - The person will receive an email with a link to create their account
   - When they create their account, they'll automatically be an admin

#### Method 3: Via Rails Console (Advanced - For Existing Users)

**Step-by-step:**

1. **Access Rails Console:**
   - Login as admin
   - Go to **Admin → Logs**
   - Click **"Rails Console"** tab
   - Or go directly to: `https://yoursandbox.discourse.group/admin/logs/rails_console`

2. **Run Command:**
   ```ruby
   # Find the user by email
   user = User.find_by_email("user@example.com")
   
   # Grant admin privileges
   user.grant_admin!
   
   # Verify it worked
   user.admin?
   # Should return: true
   ```

3. **Alternative - Find by Username:**
   ```ruby
   # Find by username instead
   user = User.find_by_username("username")
   user.grant_admin!
   ```

**Note:** Method 1 is the easiest and most user-friendly. Use Method 2 if you want to invite someone new. Method 3 is for advanced users or automation.

## Option 2: Local Development (Advanced)

If you want to run Discourse locally on your machine:

### Prerequisites Check:

**Check if Docker is installed:**
```bash
docker --version
docker-compose --version
```

**If not installed, install Docker:**

**On Ubuntu/Debian:**
```bash
# Update package index
sudo apt-get update

# Install Docker
sudo apt-get install -y docker.io docker-compose

# Add your user to docker group (so you don't need sudo)
sudo usermod -aG docker $USER

# Log out and log back in for group changes to take effect
```

**On other Linux distros:**
- Visit: https://docs.docker.com/engine/install/
- Follow instructions for your distribution

**On macOS:**
- Install Docker Desktop: https://www.docker.com/products/docker-desktop

**On Windows:**
- Install Docker Desktop: https://www.docker.com/products/docker-desktop

### Setup Steps:

1. **Clone Discourse:**
   ```bash
   git clone https://github.com/discourse/discourse.git
   cd discourse
   ```

2. **Run the setup script:**
   ```bash
   ./discourse-setup
   ```

3. **Answer the prompts:**
   - **Hostname:** Use `localhost` or `127.0.0.1` (for local testing)
   - **Email:** Your email address (for admin account)
   - **SMTP settings:** You can skip these for local testing
   - The script will download and set up everything automatically

4. **Wait for setup to complete:**
   - This can take 10-30 minutes depending on your internet speed
   - It downloads Docker images and sets up the database

5. **Access your local Discourse:**
   - Open browser: `http://localhost` (or the URL shown in the setup)
   - Create your first account (this will be admin automatically!)
   - You're ready to test!

### Using Your Local Instance:

**Start Discourse:**
```bash
cd discourse
./launcher start app
```

**Stop Discourse:**
```bash
./launcher stop app
```

**View logs:**
```bash
./launcher logs app
```

**Reset everything (if something breaks):**
```bash
./launcher destroy app
./discourse-setup  # Run setup again
```

### Connecting Theme CLI to Local Instance:

When using `discourse_theme watch .`, use:
- **URL:** `http://localhost` (or your local URL)
- **API Key:** Get from Admin → API → New API Key

**Note:** Local setup requires:
- Docker installed and running
- 4GB+ RAM minimum (8GB recommended)
- 5-10GB free disk space
- Good internet connection (for initial download)

**Pros of Local Setup:**
- ✅ Instant access (no waiting)
- ✅ Full control
- ✅ No internet needed after setup
- ✅ Can test offline

**Cons:**
- ❌ More complex setup
- ❌ Requires more resources
- ❌ Takes longer to set up initially

## Option 3: Use Discourse Theme CLI Watch Mode

You can use the `discourse_theme` CLI to sync your theme to any Discourse instance:

### Setup:
1. Install the CLI (if not already):
   ```bash
   gem install discourse_theme
   ```

2. Navigate to your theme directory:
   ```bash
   cd compound-governance-widget
   ```

3. Run watch mode:
   ```bash
   discourse_theme watch .
   ```

4. On first run, you'll be prompted for:
   - Discourse URL (e.g., `https://yoursandbox.discourse.group`)
   - API Key (get from: **Admin → API → New API Key**)
   - Theme ID (will be created automatically)

5. Now any changes you make will sync automatically!

## Installing Your Theme Component

Once you have admin access to a sandbox:

### Method 1: Via Admin UI (Easiest)
1. Go to: **Admin → Customize → Themes**
2. Click **"Components"** tab
3. Click **"Install"** button
4. Choose **"From GitHub"**
5. Paste: `https://github.com/AqsaAltaf1/compound-governance-widget`
6. Click **"Install"**

### Method 2: Via CLI (Recommended for Development)
```bash
cd compound-governance-widget
discourse_theme watch .
```

This will:
- Upload your theme component
- Watch for changes and auto-sync
- Much faster for development!

### Enable the Component:
1. Go to: **Admin → Customize → Themes**
2. Click **"Themes"** tab
3. Click on **"Foundation"** (or your active theme)
4. Scroll to **"Included components"**
5. Click **"Select..."** dropdown
6. ✅ Check **"compound-governance-widget"**
7. Click **"Save"**

## Testing Your Component

1. Create a new topic (or use existing one)
2. Paste a governance URL, for example:
   ```
   https://www.tally.xyz/gov/compound/proposal/510?govId=eip155:1:0x309a862bbC1A00e45506cB8A802D1ff10004c8C0
   ```
3. The widget should appear automatically!

## Quick Reference: Getting API Key

To use the CLI, you need an API key:

1. Login as admin
2. Go to: **Admin → API → New API Key**
3. Give it a description (e.g., "Theme Development")
4. Select permissions (at minimum: **Themes**)
5. Click **"Generate API Key"**
6. Copy the key (you'll only see it once!)

## Troubleshooting

### "I don't have admin access"
- Check if you're the first user created (auto-admin)
- Contact the sandbox provider
- Request admin access via Meta Discourse topic

### "Theme won't install"
- Make sure you have admin permissions
- Check that `about.json` is valid
- Verify GitHub URL is correct and public

### "Changes not appearing"
- Clear browser cache (Ctrl+Shift+R or Cmd+Shift+R)
- Check browser console for errors
- Verify component is enabled in theme settings
- Check Discourse logs: **Admin → Logs → Rails**

## Best Practices

1. **Always use a sandbox** for testing
2. **Use watch mode** during development for instant feedback
3. **Test in multiple browsers** (Chrome, Firefox, Safari)
4. **Test on mobile** (Discourse is responsive)
5. **Check console** for JavaScript errors
6. **Test with different user roles** (admin, moderator, regular user)

## Need Help?

- Discourse Meta: https://meta.discourse.org/c/dev
- Theme Development: https://meta.discourse.org/c/theme
- Sandbox Requests: https://meta.discourse.org/t/request-a-free-discourse-sandbox-for-theme-development/50872

