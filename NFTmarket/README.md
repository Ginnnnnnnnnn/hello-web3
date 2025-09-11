# NFTMarket系统文档

- **NFTmarket-backend：** 后端代码
- **NFTmarket-base：** 后端代码
- **NFTmarket-sync：** 后端代码
- **NFTmarket-contract：** 合约代码
- **NFTmarket-web：** 前端代码

## 背景介绍

2020 年是 DeFi 元年

2021 年是 NFT 元年

...

1. **数字资产的兴起与需求**
2. **去中心化的市场需求**
3. **版权保护和二级市场**
4. **全球化市场的潜力**
5. **技术与金融的融合**

## 项目意义

当前的 NFT 交易市场不仅是一个**基于区块链的应用**，也是**链上技术与链下服务高度结合**的典型范例。通过项目的设计和开发，可以探索如何将区块链的去中心化、透明性、不可篡改等特点与传统的链下业务流程进行有机融合，创建一个灵活、可扩展的系统架构，不仅服务于 NFT 交易市场，**还能支持未来其他潜在的链上应用，如 Bitcoin 上的铭文、符文等新兴数字资产**。以下从几个关键角度说明项目的深远意义：

1. **技术架构的通用性和可扩展性**
2. **链上技术原理与链下服务的结合**
3. **去中心化应用的场景扩展**

## NFT 基本概念

![image](image/435733355-da3ba89a-382b-4003-99b0-286a938483b2.png)

## NFT 的核心操作

详见：[https://eips.ethereum.org/EIPS/eip-721 ] (<https://eips.ethereum.org/EIPS/eip-721>)

1. **transfer**

    - `safeTransferFrom(address _from, address _to, uint256 _tokenId)`
    - `transferFrom(address _from, address _to, uint256 _tokenId)`

2. **approve**

    - `approve(address _approved, uint256 _tokenId)`
    - `setApprovalForAll(address _operator, bool _approved)`

## NFT 数据模型

**Collection：** NFT 集合的实体</br>
**Item：** 代表交易系统中代表 NFT 的实体</br>
**Ownership：**  代表 NFT 的所有权，也就是 Item 的 Owner， 即 Item 和 Wallet 的关联关系</br>
**Order：** 代表出售或购买 NFT 意愿的实体。</br>
**Activity：** 代表 NFT 状态下发生的事件：mint, transfer, list, buy 等</br>

![image](image/435733753-58d6759f-b0ee-42bb-96f7-5ca528d05fd3.png)

## NFT 交易模式

- **NFT 订单在链下**: 非dex
- **NFT 订单在链上**: dex
- **订单簿 OrderBook**: Maker, Taker: 用户; 价格确定于订单
- **做市商 AMM**: ERC721——AMM: Maker, Taker: 一方是池子, 一方是用户; 价格是随池子变化的;
