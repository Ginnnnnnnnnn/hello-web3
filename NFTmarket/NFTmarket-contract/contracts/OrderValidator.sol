// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";

import {Price} from "./libraries/RedBlackTreeLibrary.sol";
import {LibOrder, OrderKey} from "./libraries/LibOrder.sol";

// 订单校验合约
// Initializable 可升级合约
// ContextUpgradeable 可升级合约-上下文
// EIP712Upgradeable 可升级合约-EIP-712
abstract contract OrderValidator is
    Initializable,
    ContextUpgradeable,
    EIP712Upgradeable
{
    bytes4 private constant EIP_1271_MAGIC_VALUE = 0x1626ba7e;

    uint256 private constant CANCELLED = type(uint256).max;

    // 记录订单状态
    // 订单ID => 成功数量
    // CANCELLED 为取消
    mapping(OrderKey => uint256) public filledAmount;

    function __OrderValidator_init(
        string memory EIP712Name,
        string memory EIP712Version
    ) internal onlyInitializing {
        __Context_init();
        __EIP712_init(EIP712Name, EIP712Version);
        __OrderValidator_init_unchained();
    }

    function __OrderValidator_init_unchained() internal onlyInitializing {}

    /**
     * @notice Validate order parameters.
     * @param order  Order to validate.
     * @param isSkipExpiry  Skip expiry check if true.
     */
    function _validateOrder(
        LibOrder.Order memory order,
        bool isSkipExpiry
    ) internal view {
        // Order must have a maker.
        require(order.maker != address(0), "OVa: miss maker");
        // Order must be started and not be expired.

        if (!isSkipExpiry) {
            // Skip expiry check if true.
            require(
                order.expiry == 0 || order.expiry > block.timestamp,
                "OVa: expired"
            );
        }
        // Order salt cannot be 0.
        require(order.salt != 0, "OVa: zero salt");

        if (order.side == LibOrder.Side.List) {
            require(
                order.nft.collection != address(0),
                "OVa: unsupported nft asset"
            );
        } else if (order.side == LibOrder.Side.Bid) {
            require(Price.unwrap(order.price) > 0, "OVa: zero price");
        }
    }

    /**
     * @notice Get filled amount of orders.
     * @param orderKey  The hash of the order.
     * @return orderFilledAmount Has completed fill amount of sell order (0 if order is unfilled).
     */
    function _getFilledAmount(
        OrderKey orderKey
    ) internal view returns (uint256 orderFilledAmount) {
        // Get has completed fill amount.
        orderFilledAmount = filledAmount[orderKey];
        // Cancelled order cannot be matched.
        require(orderFilledAmount != CANCELLED, "OVa: canceled");
    }

    /**
     * @notice Update filled amount of orders.
     * @param newAmount  New fill amount of order.
     * @param orderKey  The hash of the order.
     */
    function _updateFilledAmount(
        uint256 newAmount,
        OrderKey orderKey
    ) internal {
        require(newAmount != CANCELLED, "OVa: canceled");
        filledAmount[orderKey] = newAmount;
    }

    /**
     * @notice Cancel order.
     * @dev Cancelled orders cannot be reopened.
     * @param orderKey  The hash of the order.
     */
    function _cancelOrder(OrderKey orderKey) internal {
        filledAmount[orderKey] = CANCELLED;
    }

    uint256[50] private __gap;
}
