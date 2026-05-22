# Workspaces

Workspaces are the top-level container for documents, conversations, and knowledge graphs. Workspaces can be **personal** (single user) or **team** (multi-user with roles).

## Create Workspace

```http
POST /workspaces
Authorization: Bearer <token>
Content-Type: application/json

{"name": "My Project", "description": "Research documents", "type": "personal"}
```

The `type` field accepts `"personal"` (default) or `"team"`. Team workspaces automatically generate an invite code.

## List Workspaces

```http
GET /workspaces
Authorization: Bearer <token>
```

Returns all workspaces owned by or shared with the authenticated user. Each response includes `ws_type` and `invite_code` fields.

## Get Workspace

```http
GET /workspaces/{ws_id}
Authorization: Bearer <token>
```

## Update Workspace

```http
PUT /workspaces/{ws_id}
Authorization: Bearer <token>
Content-Type: application/json

{"name": "Updated Name", "description": "Updated description"}
```

## Join Team Workspace

```http
POST /workspaces/join
Authorization: Bearer <token>
Content-Type: application/json

{"invite_code": "ABC123XYZ"}
```

Join a team workspace using an invite code. The user is added as a `viewer` by default.

## Regenerate Invite Code

```http
POST /workspaces/{ws_id}/regenerate-invite-code
Authorization: Bearer <token>
```

Generates a new invite code for the workspace. Only the owner can perform this action.

## Transfer Ownership

```http
PUT /workspaces/{ws_id}/transfer-ownership
Authorization: Bearer <token>
Content-Type: application/json

{"new_owner_id": "uuid-of-new-owner"}
```

Transfers workspace ownership to another member. Only the current owner can perform this action.

## Workspace Members

```http
GET /workspaces/{ws_id}/members
POST /workspaces/{ws_id}/members
PUT /workspaces/{ws_id}/members/{user_id}
DELETE /workspaces/{ws_id}/members/{user_id}
```

### Roles

| Role | Description |
|------|-------------|
| `owner` | Full control over workspace and members |
| `admin` | Manage members, LLM configs, and API keys |
| `editor` | Edit documents and conversations |
| `viewer` | Read-only access, can submit reviews |
