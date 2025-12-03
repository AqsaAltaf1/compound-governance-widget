#!/bin/bash

# Script to prepare and push component to GitHub for Discourse installation

echo "🚀 Setting up Compound Governance Widget for GitHub deployment..."
echo ""

# Check if git is initialized
if [ ! -d ".git" ]; then
    echo "📦 Initializing git repository..."
    git init
fi

# Update .gitignore
echo "📝 Updating .gitignore..."
cat >> .gitignore << EOF

# Additional ignores
.DS_Store
*.log
.env
*.swp
*.swo
*~
EOF

# Check if remote exists
if ! git remote get-url origin &> /dev/null; then
    echo ""
    echo "⚠️  No GitHub remote found!"
    echo ""
    read -p "Enter your GitHub username: " GITHUB_USER
    read -p "Enter repository name (default: compound-governance-widget): " REPO_NAME
    REPO_NAME=${REPO_NAME:-compound-governance-widget}
    
    echo ""
    echo "📡 Adding GitHub remote..."
    git remote add origin "https://github.com/${GITHUB_USER}/${REPO_NAME}.git"
    
    echo ""
    echo "✅ Remote added: https://github.com/${GITHUB_USER}/${REPO_NAME}"
    echo ""
    echo "⚠️  IMPORTANT: Create the repository on GitHub first:"
    echo "   1. Go to: https://github.com/new"
    echo "   2. Repository name: ${REPO_NAME}"
    echo "   3. Make it PUBLIC (required for Discourse)"
    echo "   4. Don't initialize with README"
    echo ""
    read -p "Press Enter after you've created the repository on GitHub..."
fi

# Add all files
echo "📦 Adding files..."
git add .

# Check if there are changes
if git diff --staged --quiet; then
    echo "✅ No changes to commit"
else
    echo "💾 Committing changes..."
    git commit -m "Update Compound Governance Widget"
fi

# Push to GitHub
echo ""
echo "🚀 Pushing to GitHub..."
git branch -M main
git push -u origin main

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Successfully pushed to GitHub!"
    echo ""
    REMOTE_URL=$(git remote get-url origin)
    echo "📋 Your GitHub URL: ${REMOTE_URL}"
    echo ""
    echo "📝 Next steps:"
    echo "   1. Go to your Discourse admin panel"
    echo "   2. Navigate: Customize → Themes → Components"
    echo "   3. Click 'Install'"
    echo "   4. Paste this URL: ${REMOTE_URL}"
    echo "   5. Click 'Install'"
    echo "   6. Enable the component in your theme"
    echo ""
else
    echo ""
    echo "❌ Failed to push. Check your GitHub repository exists and is accessible."
fi

