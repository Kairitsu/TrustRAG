# Team Collaboration

TrustRAG supports both personal and team workspaces, allowing organizations to share knowledge bases, conversations, and review workflows.

## Workspace Types

| Type | Description |
|------|-------------|
| **Personal** | Private workspace for individual use. Created by default for each user. |
| **Team** | Shared workspace with role-based access control. Supports multiple members. |

## Creating a Team

1. Open the **Workspaces** view from the sidebar
2. Click **Create Team**
3. Enter a team name and optional description
4. An invite code is automatically generated

## Joining a Team

1. Open the **Workspaces** view from the sidebar
2. Click **Join Team**
3. Enter the invite code provided by the team owner
4. You'll be added as a **viewer** by default

## Role System

| Role | Permissions |
|------|-------------|
| **Owner** | Full control — manage members, settings, API configs, transfer ownership, disband team |
| **Admin** | Manage members, LLM configs, and API keys |
| **Editor** | Edit documents and conversations |
| **Viewer** | View documents, conversations, and submit reviews |

## Workspace Switching

The sidebar includes a workspace switcher at the top. Click it to switch between your personal space and any team spaces you belong to. When switching workspaces:

- Conversations reload for the selected workspace
- Documents and knowledge bases update accordingly
- Review records filter to the current workspace

## Team Management

Team owners can access the **Team Settings** panel from the Settings page:

- **Invite Code** — Copy, regenerate, or share the team invite code
- **Members** — View and manage team members, change roles
- **Transfer Ownership** — Hand over the owner role to another member
- **Disband Team** — Permanently delete the team workspace (requires confirmation)

## Data Isolation

Each workspace maintains independent:
- Conversations and chat history
- Uploaded documents and knowledge bases
- Review records and audit trails
- Model configurations (team admins control shared LLM settings)
