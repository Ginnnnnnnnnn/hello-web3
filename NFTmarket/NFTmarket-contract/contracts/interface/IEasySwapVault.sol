// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {LibOrder, OrderKey} from "../libraries/LibOrder.sol";

interface IEasySwapVault {
    // function

    /**
     * @notice Get the balance info of the order.
     * @param orderKey The unique id of the order.
     * @return ETHAmount The amount of ETH in the order.
     * @return tokenId The tokenId of the NFT in the order.
     */
    function balanceOf(
        OrderKey orderKey
    ) external view returns (uint256 ETHAmount, uint256 tokenId);

    /**
     * @notice 创建竞价订单时，将ETH存入订单。
     * @param orderKey 订单ID
     * @param ETHAmount ETH金额
     */
    function depositETH(OrderKey orderKey, uint256 ETHAmount) external payable;

    /**
     * @notice 当订单被取消或部分匹配时，从订单中提取ETH。
     * @param orderKey 订单ID
     * @param ETHAmount ETH金额
     * @param to 退回地址
     */
    function withdrawETH(
        OrderKey orderKey,
        uint256 ETHAmount,
        address to
    ) external;

    /**
     * @notice 创建列表订单时，将NFT存入订单。
     * @param orderKey 订单ID
     * @param from NFT owner
     * @param collection NFT管理合约
     * @param tokenId tokenId
     */
    function depositNFT(
        OrderKey orderKey,
        address from,
        address collection,
        uint256 tokenId
    ) external;

    /**
     * @notice 当订单被取消时，从订单中退回NFT。
     * @param orderKey 订单ID
     * @param to 退回地址
     * @param collection NFT管理合约
     * @param tokenId tokenId
     */
    function withdrawNFT(
        OrderKey orderKey,
        address to,
        address collection,
        uint256 tokenId
    ) external;

    /**
     * @notice 编辑订单时编辑订单的NFT。
     * @param oldOrderKey 旧订单ID
     * @param newOrderKey 新订单ID
     */
    function editNFT(OrderKey oldOrderKey, OrderKey newOrderKey) external;

    /**
     * @notice 编辑订单时编辑订单的ETH。
     * @param oldOrderKey 旧订单ID
     * @param newOrderKey 新订单ID
     * @param oldETHAmount 旧订单ETH
     * @param newETHAmount 新订单ETH
     * @param to 回退ETH地址
     */
    function editETH(
        OrderKey oldOrderKey,
        OrderKey newOrderKey,
        uint256 oldETHAmount,
        uint256 newETHAmount,
        address to
    ) external payable;

    /**
     * @notice Batch transfer ERC721 NFTs.
     * @param to The address to receive the NFTs.
     * @param assets The array of NFT info.
     */
    function batchTransferERC721(
        address to,
        LibOrder.NFTInfo[] calldata assets
    ) external;

    /**
     * @dev 转账NFT
     * @param from from
     * @param from to
     * @param from NFT资产
     */
    function transferERC721(
        address from,
        address to,
        LibOrder.Asset calldata assets
    ) external;
}
