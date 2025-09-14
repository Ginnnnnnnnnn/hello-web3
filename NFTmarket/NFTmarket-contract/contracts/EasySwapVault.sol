// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {LibTransferSafeUpgradeable, IERC721} from "./libraries/LibTransferSafeUpgradeable.sol";
import {LibOrder, OrderKey} from "./libraries/LibOrder.sol";

import {IEasySwapVault} from "./interface/IEasySwapVault.sol";

// 资产管理合约
// IEasySwapVault 资产管理合约-接口
// OwnableUpgradeable 可升级合约-owner
contract EasySwapVault is IEasySwapVault, OwnableUpgradeable {
    using LibTransferSafeUpgradeable for address;
    using LibTransferSafeUpgradeable for IERC721;

    // 订单薄合约地址
    address public orderBook;
    // 订单ETH
    mapping(OrderKey => uint256) public ETHBalance;
    // 订单NFT
    mapping(OrderKey => uint256) public NFTBalance;

    modifier onlyEasySwapOrderBook() {
        require(msg.sender == orderBook, "HV: only EasySwap OrderBook");
        _;
    }

    function initialize() public initializer {
        __Ownable_init(_msgSender());
    }

    function setOrderBook(address newOrderBook) public onlyOwner {
        require(newOrderBook != address(0), "HV: zero address");
        orderBook = newOrderBook;
    }

    function balanceOf(
        OrderKey orderKey
    ) external view returns (uint256 ETHAmount, uint256 tokenId) {
        ETHAmount = ETHBalance[orderKey];
        tokenId = NFTBalance[orderKey];
    }

    /**
     * @notice 创建竞价订单时，将ETH存入订单。
     * @param orderKey 订单ID
     * @param ETHAmount ETH金额
     */
    function depositETH(
        OrderKey orderKey,
        uint256 ETHAmount
    ) external payable onlyEasySwapOrderBook {
        require(msg.value >= ETHAmount, "HV: not match ETHAmount");
        ETHBalance[orderKey] += msg.value;
    }

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
    ) external onlyEasySwapOrderBook {
        ETHBalance[orderKey] -= ETHAmount;
        to.safeTransferETH(ETHAmount);
    }

    /**
     * @notice 创建列表订单时，将NFT存入订单。
     * @param orderKey 订单ID
     * @param from NFT owner
     * @param collection NFT collection
     * @param tokenId tokenId
     */
    function depositNFT(
        OrderKey orderKey,
        address from,
        address collection,
        uint256 tokenId
    ) external onlyEasySwapOrderBook {
        IERC721(collection).safeTransferNFT(from, address(this), tokenId);
        NFTBalance[orderKey] = tokenId;
    }

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
    ) external onlyEasySwapOrderBook {
        require(NFTBalance[orderKey] == tokenId, "HV: not match tokenId");
        delete NFTBalance[orderKey];

        IERC721(collection).safeTransferNFT(address(this), to, tokenId);
    }

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
    ) external payable onlyEasySwapOrderBook {
        ETHBalance[oldOrderKey] = 0;
        if (oldETHAmount > newETHAmount) {
            ETHBalance[newOrderKey] = newETHAmount;
            to.safeTransferETH(oldETHAmount - newETHAmount);
        } else if (oldETHAmount < newETHAmount) {
            require(
                msg.value >= newETHAmount - oldETHAmount,
                "HV: not match newETHAmount"
            );
            ETHBalance[newOrderKey] = msg.value + oldETHAmount;
        } else {
            ETHBalance[newOrderKey] = oldETHAmount;
        }
    }

    /**
     * @notice 编辑订单时编辑订单的NFT。
     * @param oldOrderKey 旧订单ID
     * @param newOrderKey 新订单ID
     */
    function editNFT(
        OrderKey oldOrderKey,
        OrderKey newOrderKey
    ) external onlyEasySwapOrderBook {
        NFTBalance[newOrderKey] = NFTBalance[oldOrderKey];
        delete NFTBalance[oldOrderKey];
    }

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
    ) external onlyEasySwapOrderBook {
        IERC721(assets.collection).safeTransferNFT(from, to, assets.tokenId);
    }

    function batchTransferERC721(
        address to,
        LibOrder.NFTInfo[] calldata assets
    ) external {
        for (uint256 i = 0; i < assets.length; ++i) {
            IERC721(assets[i].collection).safeTransferNFT(
                _msgSender(),
                to,
                assets[i].tokenId
            );
        }
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public virtual returns (bytes4) {
        return this.onERC721Received.selector;
    }

    receive() external payable {}

    uint256[50] private __gap;
}
