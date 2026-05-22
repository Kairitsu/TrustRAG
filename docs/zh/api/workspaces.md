# 工作区

工作区是 TrustRAG 中的顶层组织单位，每个工作区包含独立的文档集和对话。工作区分为**个人空间**和**团队空间**两种类型。

## 列出工作区

```http
GET /api/workspaces
```

返回当前用户拥有的或加入的所有工作区，包含 `ws_type` 和 `invite_code` 字段。

## 创建工作区

```http
POST /api/workspaces
Content-Type: application/json

{
  "name": "技术文档",
  "description": "产品技术文档知识库",
  "type": "team"
}
```

`type` 字段接受 `"personal"`（默认）或 `"team"`。团队工作区创建时自动生成邀请码。

## 获取单个工作区

```http
GET /api/workspaces/:id
```

## 更新工作区

```http
PUT /api/workspaces/:id
Content-Type: application/json

{
  "name": "更新后的名称",
  "description": "更新后的描述"
}
```

## 加入团队

```http
POST /api/workspaces/join
Content-Type: application/json

{"invite_code": "ABC123XYZ"}
```

通过邀请码加入团队工作区。加入后默认角色为 `viewer`。

## 重新生成邀请码

```http
POST /api/workspaces/:id/regenerate-invite-code
```

为工作区生成新的邀请码。仅所有者可操作。

## 转让所有权

```http
PUT /api/workspaces/:id/transfer-ownership
Content-Type: application/json

{"new_owner_id": "新所有者的UUID"}
```

将工作区所有权转让给其他成员。仅当前所有者可操作。

## 工作区成员

```http
GET /api/workspaces/:id/members
POST /api/workspaces/:id/members
PUT /api/workspaces/:id/members/:user_id
DELETE /api/workspaces/:id/members/:user_id
```

### 角色权限

| 角色 | 说明 |
|------|------|
| `owner` | 完全控制工作区和成员 |
| `admin` | 管理成员、LLM 配置和 API Key |
| `editor` | 编辑文档和对话 |
| `viewer` | 只读访问，可提交审核 |

## 删除工作区

```http
DELETE /api/workspaces/:id
```

::: warning
删除工作区将同时删除该工作区下的所有文档、对话和引用数据。此操作不可撤销。
:::
