#!/usr/bin/env python3
import os
import json
import shutil
import subprocess
import re
from datetime import datetime

SKILLS_BAZAAR_DIR = "/root/bazaars/Skill-Bazaar"
TEMP_CLONE_DIR = "/root/bazaars/temp-skills-clone"
REPO_URL = "https://github.com/anthropics/skills.git"

CATEGORIES_MAPPING = {
    "webapp-testing": "testing-qa",
    "web-artifacts-builder": "coding-development",
    "skill-creator": "coding-development",
    "mcp-builder": "coding-development",
    "canvas-design": "design-creative",
    "frontend-design": "design-creative",
    "algorithmic-art": "design-creative",
    "docx": "writing-content",
    "doc-coauthoring": "writing-content",
    "xlsx": "data-analysis",
    "pptx": "business-finance",
    "internal-comms": "communication",
    "slack-gif-creator": "communication",
    "pdf": "data-analysis",
    "brand-guidelines": "marketing-seo",
    "claude-api": "ai-ml",
    "theme-factory": "design-creative",
}

def kebab_case(name):
    s = name.lower()
    s = re.sub(r"[^a-z0-9]+", "-", s)
    return s.strip("-")

def run_cmd(cmd):
    subprocess.run(cmd, shell=True, check=True)

def main():
    if os.path.exists(TEMP_CLONE_DIR):
        shutil.rmtree(TEMP_CLONE_DIR)

    print("Cloning anthropics/skills...")
    run_cmd(f"git clone {REPO_URL} {TEMP_CLONE_DIR}")

    skills_source = os.path.join(TEMP_CLONE_DIR, "skills")
    if not os.path.exists(skills_source):
        print("Error: skills folder not found in clone!")
        return

    skills_folders = [d for d in os.listdir(skills_source) if os.path.isdir(os.path.join(skills_source, d))]
    print(f"Found {len(skills_folders)} skills folders.")

    today_str = datetime.today().strftime("%Y-%m-%d")
    count_added = 0

    for skill in skills_folders:
        src_path = os.path.join(skills_source, skill)
        skill_file = os.path.join(src_path, "SKILL.md")
        if not os.path.exists(skill_file):
            continue

        # Determine category slug
        cat_slug = CATEGORIES_MAPPING.get(skill, "misc")
        
        # Target folder
        prov_slug = kebab_case(skill)
        target_dir = os.path.join(SKILLS_BAZAAR_DIR, cat_slug, prov_slug)
        os.makedirs(target_dir, exist_ok=True)

        # Copy all files
        for item in os.listdir(src_path):
            s_item = os.path.join(src_path, item)
            d_item = os.path.join(target_dir, item)
            if os.path.isdir(s_item):
                if os.path.exists(d_item):
                    shutil.rmtree(d_item)
                shutil.copytree(s_item, d_item)
            else:
                shutil.copy(s_item, d_item)

        # Let's write the required meta README.md in the folder
        meta_readme = f"""# {skill.replace('-', ' ').title()}

This skill provides specialized capability for `{skill}` within Claude and other agent environments.

> Part of **[Skill Bazaar](../../README.md)** · [Mega AI Bazaar](https://drvivek34.github.io/Mega-AI-Bazaar/)

## Details
- **Name**: {skill}
- **Source URL**: https://github.com/anthropics/skills/tree/main/skills/{skill}
- **Author**: Anthropic
- **License**: MIT
- **Date Added**: {today_str}

## Instructions
See [SKILL.md](SKILL.md) inside this folder for detailed instructions.
"""
        with open(os.path.join(target_dir, "README.md"), "w") as f:
            f.write(meta_readme)

        count_added += 1
        print(f"Imported {skill} -> {cat_slug}/{prov_slug}")

    # Clean up clone
    shutil.rmtree(TEMP_CLONE_DIR)
    print(f"Successfully imported {count_added} skills from anthropics/skills.")

if __name__ == "__main__":
    main()
