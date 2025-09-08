// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./SafeErc20.sol";

// 资产转移合约
contract SafeTransfer {
    using SafeERC20 for IERC20;
    event Redeem(
        address indexed recieptor,
        address indexed token,
        uint256 amount
    );

    /**
     * @dev 转账
     * @notice 将资金转移到池中
     * @param token 代币地址
     * @param amount 转账金额
     * @return return 转账金额
     */
    function getPayableAmount(
        address token,
        uint256 amount
    ) internal returns (uint256) {
        if (token == address(0)) {
            // ETH
            amount = msg.value;
        } else if (amount > 0) {
            // ERC20代币
            IERC20 oToken = IERC20(token);
            oToken.safeTransferFrom(msg.sender, address(this), amount);
        }
        return amount;
    }

    /**
     * @dev 赎回
     * @notice 将资金从池中赎回
     * @param recieptor 收款方
     * @param token 代币地址
     * @param amount 转账金额
     */
    function _redeem(
        address payable recieptor,
        address token,
        uint256 amount
    ) internal {
        if (token == address(0)) {
            recieptor.transfer(amount);
        } else {
            IERC20 oToken = IERC20(token);
            oToken.safeTransfer(recieptor, amount);
        }
        emit Redeem(recieptor, token, amount);
    }
}
