# pledge-go

项目分为两部分，一部分为API，另一部分为Task。

## API

提供API接口，对数据库进行操作。

```shell
cd api
go run pledge_api.go
```

### 接口分析

- 借贷池
  - /poolBaseInfo 查询借贷池基础信息
  - /poolDataInfo 查询借贷池数据信息
  - /token 查询代币列表
  - /pool/debtTokenList 债务代币列表
  - /pool/search 检索借贷池
- 价格
  - NewPrice 获取最新价格（建立websocket链接）
- 多签名钱包
  - /pool/setMultiSign 设置多签名钱包（创建一个新的）
  - /pool/getMultiSign 查询多签名钱包
- 用户
  - /user/login 登录
  - /user/logout 登出

## Task

```shell
cd task
go run pledge_task.go
```
