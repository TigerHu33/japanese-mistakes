# 云端部署文档(Supabase + Cloudflare Pages)

> 本文件是部署的"单一事实来源"。即使会话中断,按本文件勾选进度即可继续。

## 0. 架构与现状

```
浏览器 / 其他 App
   │
   ├─→ [前端 Vue 静态站点]  托管在 Cloudflare Pages   (*.pages.dev)
   │        │ axios 调用 REST
   │        ▼
   └─────→ [Supabase]      托管 Postgres + PostgREST + Auth  (*.supabase.co)
```

- 原 `docker-compose.yml` 的三块拆分上云:`db`→Supabase Postgres,`api`(PostgREST)→Supabase 内置,`frontend`→Cloudflare Pages。
- 前端 `api.js` 用的就是 PostgREST 语法,迁到 Supabase **业务逻辑零改动**,只改接入地址与鉴权头。

### 项目坐标

| 项 | 值 |
|---|---|
| Project Ref | `ljygzhvqpcnotuztfbfs` |
| API URL | `https://ljygzhvqpcnotuztfbfs.supabase.co` |
| REST Base | `https://ljygzhvqpcnotuztfbfs.supabase.co/rest/v1` |
| 凭据文件 | `supabase/config`(**已 gitignore,严禁提交;仓库是 public**) |

### 权限模型(已选定)

**全开放**:`anon` 可读写,前端无需登录。安全级别低,仅适合先跑起来 / 自己用。加固见第 5 节。

---

## 1. 进度清单

### 第一步:后端(Supabase)—— ✅ 已完成
- [x] 1.1 执行 `supabase/migrations/0001_schema.sql`(建表 / 序列 / 索引 / RPC)
- [x] 1.2 执行 `supabase/migrations/0002_grants_rls.sql`(RLS 全放行 + 授权)
- [x] 1.3 执行 `supabase/seed.sql`(导入 254 条错题 + 序列复位到 260)
- [x] 1.4 REST 验证:count=254、取样列对位正确、RPC 可调 ✓

### 第二步:前端(Cloudflare Pages)
- [ ] 2.1 改造 `frontend/src/api.js`(兼容 Supabase 接入)
- [ ] 2.2 建 `frontend/.env`(本地)与 `.env.example`(提交)
- [ ] 2.3 本地 `npm run build && npm run preview` 验证连通
- [ ] 2.4 Cloudflare Pages 连 GitHub 仓库 + 构建配置 + 环境变量
- [ ] 2.5 线上验证(打开 *.pages.dev,增删改查正常)

---

## 2. 第一步:部署后端到 Supabase

数据库迁移有两种执行方式,**任选其一**。

### 方式 A:Supabase SQL Editor(推荐,最稳)

1. 打开 Supabase 控制台 → 左侧 **SQL Editor** → New query。
2. 依次把下列文件内容**整段粘贴并 Run**(顺序不能错):
   1. `supabase/migrations/0001_schema.sql`
   2. `supabase/migrations/0002_grants_rls.sql`
   3. `supabase/seed.sql`
3. 每步 Run 成功后再进行下一步。`seed.sql` 末尾会把序列复位到 260。

> 注:`seed.sql` 已从 `db/data.sql` 清理掉 `\restrict`/`\unrestrict` 等 psql 专用命令,可直接在 SQL Editor 运行。

### 方式 B:psql 直连(命令行,可被自动化)

口令在 `supabase/config` 的 *Database password*。**本项目实测可用的 Session Pooler 连接串(东京 region)**:
```bash
PGPASSWORD='<Database password>' psql \
  "host=aws-1-ap-northeast-1.pooler.supabase.com port=5432 dbname=postgres user=postgres.ljygzhvqpcnotuztfbfs sslmode=require connect_timeout=10" \
  -v ON_ERROR_STOP=1 \
  -f supabase/migrations/0001_schema.sql \
  -f supabase/migrations/0002_grants_rls.sql \
  -f supabase/seed.sql \
  -c "notify pgrst, 'reload schema';"
```
> 新版项目关闭了直连(`db.<ref>.supabase.co` 不解析),必须走 Session Pooler。host 前缀是 `aws-1`(不是文档常见的 `aws-0`),region 东京 `ap-northeast-1`,user 为 `postgres.<ref>`。

### 1.4 后端验证

从 `supabase/config` 取 *anon public* 值,执行:
```bash
export SUPA_URL=https://ljygzhvqpcnotuztfbfs.supabase.co
export SUPA_ANON='<粘贴 anon public 值>'

# 查 3 条
curl -s "$SUPA_URL/rest/v1/mistakes?select=id,category,sub_category&limit=3" \
  -H "apikey: $SUPA_ANON" -H "Authorization: Bearer $SUPA_ANON"

# 计数(期望与导入条数一致)
curl -s -I "$SUPA_URL/rest/v1/mistakes?select=count" \
  -H "apikey: $SUPA_ANON" -H "Authorization: Bearer $SUPA_ANON" -H "Prefer: count=exact"

# RPC 自增(把 id=1 的 error_count +1,返回该行)
curl -s -X POST "$SUPA_URL/rest/v1/rpc/increment_error" \
  -H "apikey: $SUPA_ANON" -H "Authorization: Bearer $SUPA_ANON" \
  -H "Content-Type: application/json" -d '{"mistake_id": 1}'
```
返回 JSON 数据即后端 OK。

---

## 3. 第二步:部署前端到 Cloudflare Pages

### 3.1 改造 `frontend/src/api.js`

把开头的 axios 实例改为(其余 `listMistakes` 等函数**不动**,PostgREST 语法通用):

```js
import axios from 'axios'

// 有 Supabase 环境变量则走云端,否则回退本地 docker 的 /api(vite proxy),本地开发不受影响
const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL
const SUPABASE_KEY = import.meta.env.VITE_SUPABASE_ANON_KEY

const http = axios.create({
  baseURL: SUPABASE_URL ? `${SUPABASE_URL}/rest/v1` : '/api',
  headers: {
    'Content-Type': 'application/json',
    Accept: 'application/json',
    ...(SUPABASE_KEY ? { apikey: SUPABASE_KEY, Authorization: `Bearer ${SUPABASE_KEY}` } : {})
  }
})
```

> 这样改：本地仍可用 `docker compose` + `npm run dev`(走 `/api`);云端构建注入了 env 就走 Supabase。一套代码两用。

### 3.2 环境变量文件

`frontend/.env`(本地构建用,**已被 gitignore 的 `.env` 规则忽略**):
```
VITE_SUPABASE_URL=https://ljygzhvqpcnotuztfbfs.supabase.co
VITE_SUPABASE_ANON_KEY=<anon public 值>
```

`frontend/.env.example`(可提交,占位):
```
VITE_SUPABASE_URL=
VITE_SUPABASE_ANON_KEY=
```

### 3.3 本地验证
```bash
cd frontend
npm install
npm run build
npm run preview   # 打开提示的本地地址，确认列表/练习/新增都正常读写云端
```

### 3.4 Cloudflare Pages 配置

控制台 → Workers & Pages → Create → Pages → Connect to Git → 选 `TigerHu33/japanese-mistakes`。构建设置:

| 配置项 | 值 |
|---|---|
| Framework preset | None(或 Vue)|
| **Root directory** | `frontend`(前端在子目录,务必设置)|
| Build command | `npm run build` |
| Build output directory | `dist` |

环境变量(Settings → Environment variables,Production 与 Preview 都加):
```
VITE_SUPABASE_URL       = https://ljygzhvqpcnotuztfbfs.supabase.co
VITE_SUPABASE_ANON_KEY  = <anon public 值>
```
保存后 Deploy。完成后得到 `https://<名字>.pages.dev`。

> CORS:Supabase REST 默认允许任意来源携带 apikey 调用,无需额外配置。

### 3.5 线上验证
打开 `*.pages.dev`,验证错题列表加载、练习计数、新增/删除均写入 Supabase。

---

## 4. 回滚 / 重置后端

```sql
-- 在 SQL Editor 执行可清空重来
drop table if exists public.mistakes cascade;
drop function if exists public.increment_error(integer);
-- 然后重新执行第 2 节三个 SQL
```

---

## 5. 后续安全加固(当前为全开放,务必择机收紧)

当前任何人拿到公开的 anon key 即可改你的数据。加固路径:
1. **公开只读 + 写需登录**:改 `0002` 的 policy——`for select to anon using(true)`;`insert/update/delete` 限 `to authenticated`。前端接入 Supabase Auth 登录。
2. **全部需登录**:policy 全部限 `to authenticated`,anon 无权限。
3. 启用 Supabase Auth 后,前端建议改用 `@supabase/supabase-js`,自动管理 token。

---

## 6. 故障排查

| 现象 | 原因 / 处理 |
|---|---|
| `permission denied for table mistakes` | 漏跑 `0002_grants_rls.sql` |
| 查询返回 `[]` 但表里有数据 | RLS 已开但无放行 policy；确认 `0002` 执行成功 |
| 导入报主键冲突 | 表里已有数据;先按第 4 节 drop 重来 |
| psql `Network is unreachable` | 直连为 IPv6-only,改用 Session Pooler 连接串(IPv4) |
| 前端 401 / `No API key found` | 缺 `apikey` 头,或 env 未注入构建 |
| 前端跨域报错 | 检查 URL 是否带 `/rest/v1`;apikey 是否正确 |
