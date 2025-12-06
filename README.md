# TargetToolTip

A World of Warcraft addon that enhances unit tooltips with targeting information. Initially built over one week as a learning project to understand how addons work. After years of playing WoW, I figured "why not" create my own. Learning Lua while building something for a game I play so much made the process much more engaging. I've also aimed to keep it lightweight and performant as far as I could understand at this point in time.

## Features

### Tooltip Enhancement

- Shows what a unit is currently targeting
- Displays which party/raid members are targeting them
- Color-coded names by class and faction for quick recognition

### Realm Name Removal

- Automatically removes realm names from party frames
- Automatically removes realm names from raid frames
- Keeps your UI clean when playing with cross-realm players, without removing realm on tooltips.

## Installation

1. Download or clone this repository
2. Place the `TargetToolTip` folder in your `World of Warcraft\_retail_\Interface\AddOns\` directory
3. Restart WoW or reload UI (`/reload`)

## Usage

Simply hover over any unit to see the enhanced tooltip with targeting information. All features are enabled by default.

### Configuration

Access the options panel to toggle features on/off:

- Type `/tt` or `/targettooltip` in chat
- Or navigate to **ESC → Interface → AddOns → TargetToolTip**

Available options:

- **Show targeting information in tooltips** - Display who is targeting what
- **Remove realm names from raid frames** - Clean up raid frame names
- **Remove realm names from party frames** - Clean up party frame names

Changes require a UI reload (`/reload`) to take effect.

## Version

1.3.1

## Changelog

### 1.3.1 (Current)

- Added Cursor Highlight (Green Square)
- Added Toggle into UI

### 1.3.0 (23.11.2025)

- Added Item Level with Decimal functionality
- Added toggle into UI

### 1.2.0 (23.11.2025)

- Added options panel with toggleable features
- Added slash commands: `/tt` and `/targettooltip`
- Features can now be enabled/disabled independently
- Code refactored for better maintainability and organization
- Improved module structure with clear separation of concerns
- Better constants management and reduced code duplication

### 1.1.0 (23.11.2025)

- Added realm name removal for party and raid frames
- Merged functionality from RemoveRealmNames addon

### 1.0.0 (22.11.2025)

- Initial release with tooltip targeting information
