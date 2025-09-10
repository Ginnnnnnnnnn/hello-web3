# pledge-go

项目分为两部分，一部分为API，另一部分为Task。

## API

提供API接口，查询链下数据，主要对数据库进行操作。

```shell
cd api
go run pledge_api.go
```

### 接口分析

- 借贷池
  - /poolBaseInfo 查询借贷池基础信息。
  - /poolDataInfo 查询借贷池数据信息。
  - /token 查询代币列表。
  - /pool/debtTokenList 债务代币列表。
  - /pool/search 检索借贷池。
- 价格
  - NewPrice 获取最新价格（建立websocket链接）。
- 多签名钱包
  - /pool/setMultiSign 设置多签名钱包（创建一个新的）。
  - /pool/getMultiSign 查询多签名钱包。
- 用户
  - /user/login 登录。
  - /user/logout 登出。

## Task

同步链上数据到链下，查询链上信息，添加到数据库中。

```shell
cd task
go run pledge_task.go
```

### 任务分析

- UpdateAllPoolInfo 更新借贷池信息，读取链上借贷池信息，同步到redis与mysql中，MD5对比借贷池是否发生变化。
- UpdateContractPrice 更新合约价格，读取链上语言机价格信息，同步到redis与mysql中。
- UpdateContractSymbol 更新代币名称，读取链上代币合约名称信息，同步到redis与mysql中。
- UpdateTokenLogo 更新代币Logo，读取远程文件和本地信息，同步到redis与mysql中。
- Monitor 监控合约余额，邮件告警。
- SavePlgrPriceTestNet 保存plgr价格-测试网。
