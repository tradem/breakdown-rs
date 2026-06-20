#!/bin/bash

# Stelle sicher, dass du eingeloggt bist:
# gh auth login

echo "Erstelle Labels für Epics..."
gh label create "Epic: Project & Script" --color "1D76DB" --description "Project and script management" --force
gh label create "Epic: Characters & Extras" --color "0E8A16" --description "Managing roles, actors and measurements" --force
gh label create "Epic: Scenes & Schedule" --color "D93F0B" --description "Scene management and shooting schedule" --force
gh label create "Epic: Costumes & Photos" --color "5319E7" --description "Costumes, details and photo uploads" --force
gh label create "Epic: Budget & Calculation" --color "B60205" --description "Cost calculation for costumes" --force

echo "Erstelle User Stories als Issues..."

# Epic 1: Project & Script Management
gh issue create \
  --title "US-1.1: Create a new project workspace" \
  --body "**As a user**, I want to create a new script/project so that I have a blank, isolated workspace for a new film." \
  --label "Epic: Project & Script"

gh issue create \
  --title "US-1.2: Update project details" \
  --body "**As a user**, I want to update the project title and general details to keep the project metadata current." \
  --label "Epic: Project & Script"

# Epic 2: Characters & Extras
gh issue create \
  --title "US-2.1: Create characters and extras" \
  --body "**As a user**, I want to create new characters (lead/supporting) and extras to build the foundation for the casting." \
  --label "Epic: Characters & Extras"

gh issue create \
  --title "US-2.2: Manage actor measurements" \
  --body "**As a user**, I want to store detailed measurements for an actor (shoe size, collar size, etc.) so that costume designers can organize fitting clothes." \
  --label "Epic: Characters & Extras"

gh issue create \
  --title "US-2.3: Query character flat list" \
  --body "**As a frontend app**, I want to fetch a flat list (Read Model) of all characters and extras for UI selection." \
  --label "Epic: Characters & Extras"

# Epic 3: Scenes & Schedule
gh issue create \
  --title "US-3.1: Create and define scenes" \
  --body "**As a user**, I want to create a scene and assign basic data (shooting day, motive, mood, content summary) to organize the script." \
  --label "Epic: Scenes & Schedule"

gh issue create \
  --title "US-3.2: Assign characters to scenes" \
  --body "**As a user**, I want to assign and remove characters and extras to/from a scene so it is clear who needs to be on set." \
  --label "Epic: Scenes & Schedule"

gh issue create \
  --title "US-3.3: Assign scenes to shooting days" \
  --body "**As a user**, I want to assign scenes to specific shooting days to generate a chronological shooting schedule." \
  --label "Epic: Scenes & Schedule"

# Epic 4: Costumes & Photos
gh issue create \
  --title "US-4.1: Create base costumes" \
  --body "**As a user**, I want to create costumes and fundamentally assign them to a character or extra." \
  --label "Epic: Costumes & Photos"

gh issue create \
  --title "US-4.2: Add costume details" \
  --body "**As a user**, I want to add specific components (e.g., shirt, tie) as text details to a costume." \
  --label "Epic: Costumes & Photos"

gh issue create \
  --title "US-4.3: Assign costume to specific scene" \
  --body "**As a user**, I want to assign a specific costume to a character for a specific scene (e.g., 'Character wears Costume A in Scene 1')." \
  --label "Epic: Costumes & Photos"

gh issue create \
  --title "US-4.4: Upload and link costume photos" \
  --body "**As a user**, I want to upload photos (multipart upload) and link them to a costume for visual reference." \
  --label "Epic: Costumes & Photos"

# Epic 5: Budget & Calculations
gh issue create \
  --title "US-5.1: Create cost calculation" \
  --body "**As a user**, I want to create a new cost calculation for the project." \
  --label "Epic: Budget & Calculation"

gh issue create \
  --title "US-5.2: Add calculation items" \
  --body "**As a user**, I want to add individual cost items (buy, rent, consume) for costumes to monitor the budget." \
  --label "Epic: Budget & Calculation"

echo "Alle Epics und User Stories wurden erfolgreich in GitHub angelegt!"
