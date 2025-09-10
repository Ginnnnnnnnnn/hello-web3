# pledge-go

项目分为两部分，一部分为API，另一部分为Task。

## API

```shell
cd api
go run pledge_api.go
```

### 接口分析

#### Web

- 借贷池
  - /poolBaseInfo 查询借贷池基础信息
  - /poolDataInfo 查询借贷池数据信息
  - /token 查询代币列表
  - /pool/debtTokenList 债务代币列表
  - /pool/search 检索借贷池
- 价格

## Task

```shell
cd task
go run pledge_task.go
```
