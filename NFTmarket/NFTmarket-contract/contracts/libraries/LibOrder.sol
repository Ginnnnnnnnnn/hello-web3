// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Price} from "./RedBlackTreeLibrary.sol";

type OrderKey is bytes32;

library LibOrder {
    enum Side {
        List,
        Bid
    }

    enum SaleKind {
        FixedPriceForCollection,
        FixedPriceForItem
    }

    // NFT资产信息
    struct Asset {
        uint256 tokenId; // tokenId
        address collection; // NFT管理合约地址
        uint96 amount; // 数量
    }

    struct NFTInfo {
        address collection;
        uint256 tokenId;
    }

    // 订单信息
    struct Order {
        Side side; // 订单方 List-挂单 Bid-买单
        SaleKind saleKind; // 方式 FixedPriceForCollection-打包售卖 FixedPriceForItem-单个售卖
        address maker; // 创建用户地址
        Asset nft; // NFT资产信息
        Price price; // NFT价格
        uint64 expiry; // 过期事件
        uint64 salt; // 盐
    }

    struct DBOrder {
        Order order;
        OrderKey next;
    }

    // 订单队列：用于存储相同价格的订单
    struct OrderQueue {
        OrderKey head; // 头
        OrderKey tail; // 尾
    }

    struct EditDetail {
        OrderKey oldOrderKey; // old order key which need to be edit
        LibOrder.Order newOrder; // new order struct which need to be add
    }

    struct MatchDetail {
        LibOrder.Order sellOrder;
        LibOrder.Order buyOrder;
    }

    // 空ID
    OrderKey public constant ORDERKEY_SENTINEL = OrderKey.wrap(0x0);

    bytes32 public constant ASSET_TYPEHASH =
        keccak256("Asset(uint256 tokenId,address collection,uint96 amount)");

    bytes32 public constant ORDER_TYPEHASH =
        keccak256(
            "Order(uint8 side,uint8 saleKind,address maker,Asset nft,uint128 price,uint64 expiry,uint64 salt)Asset(uint256 tokenId,address collection,uint96 amount)"
        );

    function hash(Asset memory asset) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    ASSET_TYPEHASH,
                    asset.tokenId,
                    asset.collection,
                    asset.amount
                )
            );
    }

    function hash(Order memory order) internal pure returns (OrderKey) {
        return
            OrderKey.wrap(
                keccak256(
                    abi.encodePacked(
                        ORDER_TYPEHASH,
                        order.side,
                        order.saleKind,
                        order.maker,
                        hash(order.nft),
                        Price.unwrap(order.price),
                        order.expiry,
                        order.salt
                    )
                )
            );
    }

    function isSentinel(OrderKey orderKey) internal pure returns (bool) {
        return OrderKey.unwrap(orderKey) == OrderKey.unwrap(ORDERKEY_SENTINEL);
    }

    function isNotSentinel(OrderKey orderKey) internal pure returns (bool) {
        return OrderKey.unwrap(orderKey) != OrderKey.unwrap(ORDERKEY_SENTINEL);
    }
}
