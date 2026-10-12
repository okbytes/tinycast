#!/bin/bash
# Upstream commits not yet harvested, minus those that change only what this fork cut.
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1

# What upstream has and this fork removed, as globs; each cut adds its own in the same commit.
cut=(
    'website/*' '.github/*' .coderabbit.yaml CONTRIBUTING.md
    CONTRIBUTOR_LICENSE_AND_FEEDBACK_AGREEMENT.md SECURITY.md docs/release.md
    docs/support-button.svg Scripts/release-notes.sh Scripts/upload-website-media.sh
    'Tinycast/Features/AI/*' 'Tinycast/Assets.xcassets/AIBrand*' 'Tests/ai-*' 'Tests/codex-*'
    Tests/installed-ai-test.swift Tests/apple-intelligence-test.swift
    Tests/chat-markdown-test.swift 'Tests/text-diff-*' Tests/redaction-test.swift
    'Tinycast/DesignSystem/Redacted*' Tinycast/Platform/ExecutableLocator.swift
    Tinycast/Platform/KeychainSecretStore.swift docs/features/ai.md
    'Tinycast/Features/MCP/*' 'Tests/mcp-*' docs/features/mcp.md
    'Tinycast/Features/QuickActions/*' Tests/quick-action-test.swift docs/features/quick-actions.md
    'Tinycast/Features/Support/*' Tests/support-test.swift docs/features/support.md
    'Tinycast/Features/Updates/*' 'Tests/update*-test.swift' docs/features/updates.md
    'Tinycast/Features/Extensions/*' 'Scripts/raycast-runtime/*' 'Tests/ext-*'
    Tests/symbols-test.swift Tinycast/Resources/RaycastRuntime.generated.js
    docs/features/extensions.md
    'Tinycast/Features/FileSearch/*' 'Tests/file-search-*' docs/features/file-search.md
    'Tinycast/Features/MenuSearch/*' Tests/menu-search-test.swift docs/features/menu-search.md
    'Tinycast/Features/Dictation/*' 'Tests/dictation-*' Scripts/benchmark-dictation.sh
    docs/features/dictation.md
    '*/Raycast*Import*' 'Tinycast/Features/Backup/*/Raycast*' Tinycast/Features/Backup/Service/Scrypt.swift
    Tinycast/Platform/Compression/Zlib.swift Tinycast/DesignSystem/RevealableSecureField.swift
    Tests/raycast-test.swift docs/features/raycast-import.md
    'Tinycast/Windows/About/*'
    'Tinycast/Features/WindowSwitcher/*' Tinycast/Features/Settings/Panes/NavigationSettingsView.swift
    Tests/window-switch-test.swift docs/features/navigation.md
    'Tinycast/Features/Notes/*' 'Tests/notes-*' docs/features/notes.md
    'Tinycast/Features/WindowManagement/*/Room*'
    'Tinycast/Features/WindowManagement/*/WindowLayout*'
    'Tinycast/Features/WindowManagement/*/CustomWindowSize*'
    Tinycast/Features/WindowManagement/Service/WindowInventory.swift
    Tinycast/DesignSystem/EntryIconView.swift
    Tinycast/Features/Settings/Model/SettingsFileIdentity.swift NOTICE.md
    Tests/window-layout-test.swift Tests/window-room-test.swift docs/features/window-layouts.md
    docs/features/window-rooms.md
    Tinycast/Features/Calendar/Model/AutoJoinPolicy.swift
    Tinycast/Features/Calendar/Model/EventDraft.swift
    Tinycast/Features/Calendar/Model/MeetingDetails.swift
    Tinycast/Features/Calendar/Service/MeetingLauncher.swift
    'Tinycast/Features/Calendar/UI/CameraPreview*' 'Tinycast/Features/Calendar/UI/MeetingDetails*'
    'Tinycast/Features/Calendar/UI/Schedule*' Tinycast/Features/Calendar/UI/EventDraftFields.swift
    Tinycast/Features/Calendar/UI/MeetingCardView.swift Tinycast/DesignSystem/ColorDot.swift
    Tinycast/Features/Calendar/UI/MeetingRowParts.swift
    'Tinycast/Features/Launcher/*/Fallback*' Tests/fallback-test.swift
    Tinycast/Features/Launcher/Service/SettingsPaneScanner.swift
    Tinycast/Features/Launcher/Settings/SystemSettingsSettingsView.swift
    'Tinycast/Features/Quicklinks/*' 'Tests/quicklink-*' docs/features/quicklinks.md
)
# Files any feature edits in passing; on their own they don't make a commit worth reading.
shared=(
    Scripts/run-tests.sh 'Tinycast.xcodeproj/*' project.yml README.md AGENTS.md
    docs/README.md docs/architecture.md docs/testing.md
)

matches() {
    local file=$1 glob
    shift
    for glob in "$@"; do [[ $file == $glob ]] && return 0; done
    return 1
}

hidden=0
for sha in $(git rev-list origin/upstream-reviewed..upstream/main); do
    touches_cut=0 touches_kept=0
    while IFS= read -r file; do
        if matches "$file" "${cut[@]}"; then
            touches_cut=1
        elif ! matches "$file" "${shared[@]}"; then
            touches_kept=1
            break
        fi
    done < <(git diff --name-only "$sha^" "$sha")
    if ((touches_kept || !touches_cut)); then
        git log -1 --format='%h %s' "$sha"
    else
        hidden=$((hidden + 1))
    fi
done
echo "($hidden touching only cut features not shown)" >&2
