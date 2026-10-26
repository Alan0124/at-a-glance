# 常在待办

<!-- impeccable:product-schema 1 -->

## Platform
macOS native desktop utility

## Stack
SwiftUI + AppKit, built with the installed Swift toolchain. Implementation choice made for a true floating Mac window, local storage, and no external runtime.

## Users
Alan, using this Mac while working in other applications.

## Product Purpose
Keep tasks visible on the desktop without opening a separate productivity app. Recreate the supplied Xiaohongshu video as closely as the observable evidence allows.

## Operating Context
Small floating window, available across desktop spaces; menu bar access and no Dock icon. All files for this independent deliverable live under `/Users/alan/Desktop/GitHub项目/桌面待办/`.

## Capabilities and Constraints
Four task states (To-do, Pending, Completed, Cancelled), collapsible work/life/content/study groups, quick entry, completion, editing, due dates, local persistence. Hover makes the window legible; leaving it makes it translucent. Optional compact mode is an enhancement, pending verification against the video. Login startup is optional and remains off until the user enables it.

## Evidence on Hand
The user's 15-second video: Xiaohongshu item `6ad82106000000002b01e4be`. A separate observation record distinguishes video evidence from comments. No access to the original app's code or binary.

## Product Principles
- Keep the list present without competing with the user's work.
- Store tasks locally and preserve them through restart.
- Make task entry and completion immediate.
- Respect the reference's compact, translucent, restrained interface.

## Open Decisions
App name is an implementation assumption: 常在待办 / At a Glance. No cloud sync, system Reminders integration, or notifications are implied by the video.
