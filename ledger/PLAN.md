# Ledger 消费管理系统规划

> 状态：规划草案，暂不执行实现。
>
> 目标：基于 Beancount 管理个人消费账本，自动从招商银行信用卡邮件导入消费，支持 Fava 查看/手动编辑，并导出数据给本机已有 Grafana 实例搭建消费看板。

## 1. 需求摘要

- 账本以 Beancount 为唯一权威数据源。
- 每个月的消费记录存放在一个独立 Beancount 文件中。
- 自动监听邮件，从招商银行信用卡每日消费邮件中读取前一日消费。
- 邮件解析、商户理解、消费分类直接引入 LLM。
- 防重复导入只做邮件级去重。
- Docker Compose 部署，服务本身无状态。
- 支持通过 Fava 查看账本，并通过 GUI 手动追加或修改记账。
- 支持导出数据给 Grafana；Grafana 复用本机已有实例，不新增 Grafana 容器。

## 2. 总体架构

```text
招商银行信用卡邮件
        ↓
  mail-importer 容器
        ↓
  IMAP 拉取 / 监听
        ↓
  邮件级去重
        ↓
  LLM 解析 + LLM 分类
        ↓
  追加写入月度 Beancount 文件
        ↓
┌────────────────────┬────────────────────┐
│ Fava 查看 / 手动编辑 │ exporter 数据导出    │
│                    │ SQLite 或 Postgres  │
└────────────────────┴────────────────────┘
                              ↓
                     本机已有 Grafana 实例
```

核心原则：

1. **Beancount 是唯一权威账本**，自动导入、手工编辑、数据导出都围绕 Beancount 文件进行。
2. **容器无状态**，状态全部挂载到宿主机目录：账本、配置、处理过的邮件记录、导出数据库。
3. **每月一个消费文件**，便于 review、备份、版本管理和手动修正。
4. **邮件级去重即可**，不做交易级去重；同一封邮件只处理一次。
5. **LLM 负责非结构化理解**，包括招商邮件正文解析、商户清洗、消费分类、备注生成。

## 3. 推荐目录结构

建议在仓库内新增 `/home/skywt/homelab/ledger`：

```text
ledger/
  PLAN.md
  docker-compose.yml
  .env.example

  beancount/
    main.bean
    accounts.bean
    commodities.bean
    opening.bean
    journals/
      2026.bean
      2026/
        2026-06.bean
        2026-07.bean
    imports/
      errors.bean
      manual-review.bean

  config/
    mail.yaml
    llm.yaml
    classify.yaml
    cmb.yaml
    export.yaml

  importer/
    Dockerfile
    requirements.txt
    app/
      main.py
      mail_client.py
      cmb_mail.py
      llm_extract.py
      beancount_writer.py
      processed_store.py

  exporter/
    Dockerfile
    requirements.txt
    app/
      main.py
      beancount_export.py

  data/
    processed-mails.sqlite
    export.sqlite
```

说明：

- `beancount/`：账本目录，建议纳入 Git 管理。
- `config/`：非敏感配置，建议纳入 Git 管理。
- `data/`：运行时状态，例如已处理邮件数据库、导出 SQLite，建议不纳入 Git 管理。
- `.env`：邮箱密码、LLM API key 等敏感信息，不能纳入 Git。

## 4. Beancount 账本规划

### 4.1 入口文件

`beancount/main.bean`：

```beancount
option "title" "Personal Expense Ledger"
option "operating_currency" "CNY"

include "accounts.bean"
include "commodities.bean"
include "opening.bean"

include "journals/2026.bean"
```

`beancount/journals/2026.bean`：

```beancount
include "2026/2026-06.bean"
include "2026/2026-07.bean"
```

后续可以由脚本自动维护年度 include 文件，但第一版也可以手动维护。

### 4.2 账户设计

招商信用卡作为负债账户：

```beancount
1970-01-01 open Liabilities:CreditCard:CMB7273 CNY
```

常用消费账户示例：

```beancount
1970-01-01 open Expenses:Food:Restaurant CNY
1970-01-01 open Expenses:Food:Coffee CNY
1970-01-01 open Expenses:Food:Delivery CNY
1970-01-01 open Expenses:Shopping:General CNY
1970-01-01 open Expenses:Shopping:Digital CNY
1970-01-01 open Expenses:Transport CNY
1970-01-01 open Expenses:Health CNY
1970-01-01 open Expenses:Entertainment CNY
1970-01-01 open Expenses:Unknown CNY
```

### 4.3 自动导入记录格式

示例：

```beancount
2026-06-28 * "萨莉亚" "财付通-萨莉亚杭州景兴路店"
  source: "cmb_email"
  mail_message_id: "<example-message-id>"
  time: "13:27:39"
  card: "7273"
  raw_merchant: "财付通-萨莉亚杭州景兴路店"
  llm_category: "餐饮/正餐"
  Expenses:Food:Restaurant       45.00 CNY
  Liabilities:CreditCard:CMB7273
```

注意：

- `mail_message_id` 用于追溯来源，但重复导入判定以 `processed-mails.sqlite` 为准。
- 不为每笔交易生成 `import_id`，因为本方案明确只做邮件级去重。
- 未能可靠分类时写入 `Expenses:Unknown`，后续通过 Fava 手动修正。

## 5. 招商银行邮件导入流程

### 5.1 邮件监听方式

第一版推荐 IMAP 定时拉取，而不是 webhook。

优点：

- 不需要公网入口。
- 部署简单，适合 homelab。
- 与 Docker Compose 配合自然。

`config/mail.yaml` 示例：

```yaml
imap:
  host: imap.example.com
  port: 993
  username: your@email.com
  password_env: MAIL_PASSWORD
  folder: INBOX
  poll_interval_seconds: 300

filter:
  from_contains:
    - cmbchina
    - 招商银行
  subject_contains:
    - 消费
    - 信用卡
```

### 5.2 处理流程

```text
启动 mail-importer
  ↓
连接 IMAP
  ↓
搜索候选邮件
  ↓
读取 Message-ID / UID
  ↓
检查 processed-mails.sqlite 是否已处理
  ↓
未处理则读取邮件正文
  ↓
调用 LLM 解析并分类
  ↓
校验 LLM 结构化输出
  ↓
追加写入对应月份 .bean 文件
  ↓
记录该邮件为已处理
```

### 5.3 邮件级去重

只记录邮件级处理状态，建议 SQLite 表：

```sql
create table processed_mails (
  id integer primary key autoincrement,
  account text not null,
  folder text not null,
  imap_uid text,
  message_id text,
  subject text,
  mail_date text,
  processed_at text not null,
  status text not null,
  error text,
  unique(account, folder, message_id)
);
```

如果某些邮件没有 `Message-ID`，可退化为：

```text
account + folder + imap_uid
```

处理策略：

- 成功写入 Beancount 后，记录 `status = 'processed'`。
- LLM 解析失败或账本写入失败，记录 `status = 'failed'` 和错误原因。
- 失败邮件是否重试需要单独配置，避免无限重复调用 LLM。

## 6. LLM 解析与分类规划

### 6.1 LLM 的职责

LLM 直接负责：

1. 从邮件正文中识别账单日期。
2. 识别每一笔消费的时间、币种、金额、卡尾号、交易类型、原始商户文本。
3. 清洗商户名，例如：
   - `财付通-萨莉亚杭州景兴路店` → payee: `萨莉亚`
   - `支付宝-上海拉扎斯信息科技有限公司` → payee: `饿了么`
4. 根据账户表和分类规则选择 Beancount expense account。
5. 输出结构化 JSON，供程序校验后写入 Beancount。

### 6.2 LLM 输出 JSON Schema

建议要求 LLM 只输出 JSON，例如：

```json
{
  "statement_date": "2026-06-28",
  "source": "cmb_email",
  "transactions": [
    {
      "time": "13:27:39",
      "currency": "CNY",
      "amount": "45.00",
      "card_last4": "7273",
      "transaction_type": "消费",
      "raw_merchant": "财付通-萨莉亚杭州景兴路店",
      "payee": "萨莉亚",
      "narration": "财付通-萨莉亚杭州景兴路店",
      "expense_account": "Expenses:Food:Restaurant",
      "confidence": 0.95,
      "reason": "商户包含萨莉亚，属于餐饮正餐"
    }
  ]
}
```

程序侧必须校验：

- `statement_date` 是否为合法日期。
- `amount` 是否为正数小数。
- `currency` 是否在允许列表中，第一版仅允许 `CNY`。
- `expense_account` 是否存在于允许账户列表。
- `card_last4` 是否能映射到负债账户。
- `confidence` 低于阈值时是否转入 `Expenses:Unknown` 或 `manual-review.bean`。

### 6.3 分类规则仍然保留

虽然引入 LLM，但建议保留 `config/classify.yaml` 作为分类偏好和硬规则输入给 LLM，而不是完全废弃。

示例：

```yaml
accounts:
  default: Expenses:Unknown
  allowed:
    - Expenses:Food:Restaurant
    - Expenses:Food:Coffee
    - Expenses:Food:Delivery
    - Expenses:Shopping:General
    - Expenses:Shopping:Digital
    - Expenses:Transport
    - Expenses:Health
    - Expenses:Entertainment
    - Expenses:Unknown

rules:
  - when_contains: ["萨莉亚"]
    prefer_account: Expenses:Food:Restaurant
    prefer_payee: 萨莉亚
  - when_contains: ["星巴克"]
    prefer_account: Expenses:Food:Coffee
    prefer_payee: 星巴克
  - when_contains: ["拉扎斯", "饿了么"]
    prefer_account: Expenses:Food:Delivery
    prefer_payee: 饿了么
  - when_contains: ["拼多多"]
    prefer_account: Expenses:Shopping:General
    prefer_payee: 拼多多
```

使用方式：

- 把可用账户、硬规则、历史修正样例放入 LLM prompt。
- LLM 输出后程序再做强校验。
- 如果 LLM 输出不在 allowed accounts 中，则替换为 `Expenses:Unknown`。

### 6.4 示例邮件的目标解析结果

输入邮件：

```text
2026/06/28 您的消费明细如下：
13:27:39
 
CNY 45.00
尾号7273 消费 财付通-萨莉亚杭州景兴路店
14:22:43
 
CNY 23.80
尾号7273 消费 财付通-星巴克
20:30:28
 
CNY 36.30
尾号7273 消费 支付宝-上海拉扎斯信息科技有限公司
20:46:22
 
CNY 245.00
尾号7273 消费 拼多多平台商户-Apple Pay:1423
```

目标 Beancount 输出：

```beancount
2026-06-28 * "萨莉亚" "财付通-萨莉亚杭州景兴路店"
  source: "cmb_email"
  time: "13:27:39"
  card: "7273"
  raw_merchant: "财付通-萨莉亚杭州景兴路店"
  Expenses:Food:Restaurant       45.00 CNY
  Liabilities:CreditCard:CMB7273

2026-06-28 * "星巴克" "财付通-星巴克"
  source: "cmb_email"
  time: "14:22:43"
  card: "7273"
  raw_merchant: "财付通-星巴克"
  Expenses:Food:Coffee           23.80 CNY
  Liabilities:CreditCard:CMB7273

2026-06-28 * "饿了么" "支付宝-上海拉扎斯信息科技有限公司"
  source: "cmb_email"
  time: "20:30:28"
  card: "7273"
  raw_merchant: "支付宝-上海拉扎斯信息科技有限公司"
  Expenses:Food:Delivery         36.30 CNY
  Liabilities:CreditCard:CMB7273

2026-06-28 * "拼多多" "拼多多平台商户-Apple Pay:1423"
  source: "cmb_email"
  time: "20:46:22"
  card: "7273"
  raw_merchant: "拼多多平台商户-Apple Pay:1423"
  Expenses:Shopping:General     245.00 CNY
  Liabilities:CreditCard:CMB7273
```

## 7. 写入 Beancount 策略

- 自动导入只做追加写入，不自动重排历史文件。
- 按 `statement_date` 写入对应月份：
  - `2026-06-28` → `beancount/journals/2026/2026-06.bean`
- 如果月份文件不存在，自动创建。
- 如果年度 include 文件缺少该月份 include，可自动追加，或第一版先手动维护。
- 每封邮件的多笔交易建议作为一个连续块追加，块前加注释方便 review：

```beancount
; imported from cmb_email, message_id=<...>, processed_at=2026-07-02T12:00:00Z
```

错误处理：

- LLM 无法解析：不写入月度文件，记录失败状态。
- 部分字段低置信度：可以写入 `Expenses:Unknown`，同时保留 `llm_confidence` metadata。
- Beancount 校验失败：回滚本次写入，记录失败状态。

## 8. Fava 部署规划

Fava 服务用于查看、查询和手动修改账本。

Docker Compose 草案：

```yaml
services:
  fava:
    image: yegle/fava:latest
    volumes:
      - ./beancount:/bean
    command: /bean/main.bean
    ports:
      - "5000:5000"
    restart: unless-stopped
```

注意：

- Fava 是轻量 GUI，不是完整的多人协作记账系统。
- 自动导入写文件和 Fava 手动编辑可能存在并发写入风险；第一版建议接受低并发使用，后续可引入文件锁。
- 如果需要更强的手动录入体验，可后续增加一个自定义 Web 表单服务，输出 Beancount entry。

## 9. Docker Compose 服务规划

建议三个服务：

1. `fava`：查看与手动编辑。
2. `mail-importer`：邮件拉取、LLM 解析分类、写入 Beancount。
3. `exporter`：定时从 Beancount 导出结构化数据给 Grafana。

Compose 草案：

```yaml
services:
  fava:
    image: yegle/fava:latest
    volumes:
      - ./beancount:/bean
    command: /bean/main.bean
    ports:
      - "5000:5000"
    restart: unless-stopped

  mail-importer:
    build: ./importer
    volumes:
      - ./beancount:/app/beancount
      - ./config:/app/config:ro
      - ./data:/app/data
    environment:
      - MAIL_PASSWORD=${MAIL_PASSWORD}
      - LLM_API_KEY=${LLM_API_KEY}
      - LLM_BASE_URL=${LLM_BASE_URL}
      - LLM_MODEL=${LLM_MODEL}
    restart: unless-stopped

  exporter:
    build: ./exporter
    volumes:
      - ./beancount:/app/beancount:ro
      - ./config:/app/config:ro
      - ./data:/app/data
    restart: unless-stopped
```

## 10. 数据导出与 Grafana

Grafana 复用本机已有实例，不在本 Compose 中创建。

### 10.1 推荐导出目标

优先级：

1. 如果本机已有 Postgres/MySQL 且 Grafana 已接入，导出到已有数据库。
2. 否则导出到 `data/export.sqlite`，让 Grafana 通过 SQLite 数据源插件读取。

### 10.2 SQLite 表结构草案

```sql
create table transactions (
  id text primary key,
  date text not null,
  year integer not null,
  month integer not null,
  day integer not null,
  payee text,
  narration text,
  account text not null,
  category_l1 text,
  category_l2 text,
  amount real not null,
  currency text not null,
  source text,
  card text,
  raw_merchant text,
  file_path text,
  line_no integer
);
```

`id` 可由导出器生成，例如基于：

```text
file_path + line_no + posting_account + amount
```

这里的 `id` 只用于导出表主键，不用于自动导入去重。

### 10.3 Grafana 看板建议

总览：

- 本月总消费。
- 本月日均消费。
- 本月餐饮消费。
- 本月购物消费。
- 招商信用卡当前负债。

趋势：

- 每日消费折线图。
- 每月消费柱状图。
- 分类月度趋势。

分类分析：

- 本月消费分类占比。
- 一级分类排行。
- 二级分类排行。
- 商户排行。

运营/维护：

- 最近 50 条消费。
- `Expenses:Unknown` 未分类消费。
- 大额消费列表，例如金额大于 500 CNY。
- LLM 低置信度分类列表。

## 11. 安全与隐私

由于邮件和账本包含高度敏感的个人消费数据，引入 LLM 时需要特别注意：

- 优先考虑自托管或可信 API endpoint。
- `.env` 中保存 LLM key，不能提交 Git。
- Prompt 中只发送必要邮件正文和必要账户信息。
- 不发送完整历史账本给 LLM；分类上下文只传账户列表、少量规则和必要样例。
- LLM 原始请求/响应日志默认关闭；如需 debug，应脱敏或短期保留。
- 邮箱密码建议使用应用专用密码，而不是主密码。

## 12. 风险与待确认问题

### 12.1 风险

- 招商银行邮件格式可能变化，需要 prompt 和校验逻辑有容错。
- LLM 可能误分类，必须通过 allowed account 校验与低置信度兜底。
- 只做邮件级去重意味着：如果同一笔交易出现在两封不同邮件中，系统不会自动识别重复。
- Fava 手动编辑和 importer 自动追加可能并发冲突，后续可加文件锁。
- Grafana 读取 SQLite 时需要确认现有 Grafana 是否安装 SQLite 数据源插件。

### 12.2 待确认

- 使用哪一个 LLM 服务：本地模型、OpenAI-compatible API、还是其他 provider。
- 是否已有 Postgres/MySQL 可供 Grafana 使用。
- Fava 对外访问是否需要放到现有 Caddy 后面，并加认证。
- 邮箱 IMAP 服务商、文件夹、招商邮件发件人与主题格式。
- 月度 Beancount include 文件是否由脚本自动维护。

## 13. 推荐实施阶段

### 阶段 1：账本与 Fava 骨架

- 创建 Beancount 目录结构。
- 定义账户表。
- 配置 Fava。
- 手写几条示例账目验证 Fava 可用。

### 阶段 2：邮件导入最小闭环

- 实现 IMAP 拉取。
- 实现邮件级去重。
- 接入 LLM 输出结构化 JSON。
- 校验并写入月度 Beancount 文件。

### 阶段 3：分类质量提升

- 建立 `classify.yaml` 账户和偏好规则。
- 增加低置信度处理。
- 增加失败邮件与人工 review 流程。

### 阶段 4：导出与 Grafana

- 实现 Beancount 到 SQLite 或已有数据库的导出。
- 在现有 Grafana 中配置数据源。
- 创建消费看板。

### 阶段 5：运维完善

- 增加健康检查和日志。
- 增加文件锁。
- 增加备份策略。
- 增加 LLM 成本与错误率监控。

## 14. 第一版建议技术选型

```text
账本格式：Beancount
账本 GUI：Fava
邮件拉取：Python IMAPClient / imaplib
邮件解析与分类：LLM JSON 输出 + Python schema 校验
配置：YAML + .env
去重：SQLite，仅邮件级
导出：SQLite 优先，已有数据库次优先按实际环境决定
部署：Docker Compose
```

第一版推荐目标：

```text
Beancount + Fava + Python mail-importer + LLM extraction/classification + SQLite export
```
