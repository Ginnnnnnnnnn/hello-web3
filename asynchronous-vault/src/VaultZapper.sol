//SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC7540, IERC4626} from "./interfaces/IERC7540.sol";
import {PermitParams, AsyncVault} from "./AsyncVault.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

contract VaultZapper is Ownable2Step, Pausable {
    /**
     * @dev The `SafeERC20` lib is only used for `safeTransfer`,
     * `safeTransferFrom` and `forceApprove` operations.
     */
    using SafeERC20 for IERC20;

    /**
     * @dev The `Address` lib is only used for `sendValue` operations.
     */
    using Address for address payable;

    // =================== 状态变量 ===================

    // 金库合约授权映射
    mapping(IERC4626 vault => bool isAuthorized) public authorizedVaults;

    // 交易合约授权映射
    mapping(address routerAddress => bool isAuthorized)
        public authorizedRouters;

    // =================== 事件 ===================

    /**
     * @dev The `ZapAndDeposit` event is emitted when a user zaps in and
     * deposits
     * assets into a vault.
     */
    event ZapAndRequestDeposit(
        IERC7540 indexed vault,
        address indexed router,
        IERC20 tokenIn,
        uint256 amount
    );

    /**
     * @dev The `ZapAndDeposit` event is emitted when a user zaps in and
     * deposits
     * assets into a vault.
     */
    event ZapAndDeposit(
        IERC4626 indexed vault,
        address indexed router,
        IERC20 tokenIn,
        uint256 amount,
        uint256 shares
    );

    /**
     * @dev The `RouterApproved` event is emitted when a router is approved to
     * interact with a token.
     */
    event RouterApproved(address indexed router, IERC20 indexed token);
    /**
     * @dev The `RouterAuthorized` event is emitted when a router is authorized
     * to interact with the `VaultZapper` contract.
     */
    event RouterAuthorized(address indexed router, bool allowed);
    /**
     * @dev The `VaultAuthorized` event is emitted when a vault is authorized to
     * interact with the `VaultZapper` contract.
     */
    event VaultAuthorized(IERC4626 indexed vault, bool allowed);

    // =================== 错误 ===================

    /**
     * @dev The `NotRouter` error is emitted when a router is not authorized to
     * interact with the `VaultZapper` contract.
     */
    error NotRouter(address router);
    /**
     * @dev The `NotVault` error is emitted when a vault is not authorized to
     * interact with the `VaultZapper` contract.
     */
    error NotVault(IERC4626 vault);
    /**
     * @dev The `SwapFailed` error is emitted when a swap fails.
     */
    error SwapFailed(string reason);
    /**
     * @dev The `InconsistantSwapData` error is emitted when the swap data is
     * inconsistant.
     */
    error InconsistantSwapData(
        uint256 expectedTokenInBalance,
        uint256 actualTokenInBalance
    );
    /**
     * @dev The `NotEnoughSharesMinted` error is emitted when the amount of
     * shares
     * minted is not enough.
     */
    error NotEnoughSharesMinted(uint256 sharesMinted, uint256 minSharesMinted);
    /**
     * @dev The `NotEnoughUnderlying` error is emitted when the amount of
     * underlying assets is not enough.
     */
    error NotEnoughUnderlying(
        uint256 previewedUnderlying,
        uint256 withdrawedUnderlying
    );

    /**
     * @dev The `NullMinShares` error is emitted when the minimum amount of
     * shares
     * to mint is null.
     */
    error NullMinShares();

    /**
     * @dev See
     * https://dedaub.com/blog/phantom-functions-and-the-billion-dollar-no-op
     */
    error PermitFailed();

    // =================== 修饰器 ===================

    /**
     * @dev The `onlyAllowedRouter` modifier is used to check if a router is
     * authorized to interact with the `VaultZapper` contract.
     */
    modifier onlyAllowedRouter(address router) {
        if (!authorizedRouters[router]) revert NotRouter(router);
        _;
    }

    /**
     * @dev The `onlyAllowedVault` modifier is used to check if a vault is
     * authorized to interact with the `VaultZapper` contract.
     */
    modifier onlyAllowedVault(IERC4626 vault) {
        if (!authorizedVaults[vault]) revert NotVault(vault);
        _;
    }

    // =================== 初始化 ===================

    constructor() Ownable(_msgSender()) {}

    // =================== 合约设置 ===================

    /**
     * @dev 暂停
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev 取消暂停
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev 提现代币
     */
    function withdrawToken(IERC20 token) external onlyOwner {
        token.safeTransfer(_msgSender(), token.balanceOf(address(this)));
    }

    /**
     * @dev 提现代币-ETH
     */
    function withdrawNativeToken() external onlyOwner {
        payable(_msgSender()).sendValue(address(this).balance);
    }

    /**
     * @dev 授权 Token 到 交易合约
     */
    function approveTokenForRouter(
        IERC20 token,
        address router
    ) public onlyOwner onlyAllowedRouter(router) {
        token.forceApprove(router, type(uint256).max);
        emit RouterApproved(router, token);
    }

    /**
     * @dev 设置交易合约授权
     */
    function toggleRouterAuthorization(address router) public onlyOwner {
        bool authorized = !authorizedRouters[router];
        authorizedRouters[router] = authorized;
        emit RouterAuthorized(router, authorized);
    }

    /**
     * @dev 设置金库合约授权
     */
    function toggleVaultAuthorization(IERC7540 vault) public onlyOwner {
        bool authorized = !authorizedVaults[vault];
        IERC20(vault.asset()).forceApprove(
            address(vault),
            authorized ? type(uint256).max : 0
        );
        authorizedVaults[vault] = authorized;
        emit VaultAuthorized(vault, authorized);
    }

    // =================== 功能方法 ===================

    /**
     * @dev 存款-离线许可授权
     * @param tokenIn 代币地址
     * @param vault 金库地址
     * @param router 交易地址
     * @param amount 代币金额
     * @param swapData 交易参数
     * @param permitParams 离线许可参数
     * @return 股份
     */
    function zapAndDepositWithPermit(
        IERC20 tokenIn,
        IERC4626 vault,
        address router,
        uint256 amount,
        bytes calldata swapData,
        PermitParams calldata permitParams
    ) public returns (uint256) {
        // 检查授权
        if (tokenIn.allowance(_msgSender(), address(this)) < amount) {
            // 执行授权
            _execPermit(tokenIn, _msgSender(), address(this), permitParams);
        }
        return zapAndDeposit(tokenIn, vault, router, amount, swapData);
    }

    /**
     * @dev 存款
     * @param tokenIn 代币地址
     * @param vault 金库地址
     * @param router 交易地址
     * @param amount 代币金额
     * @param data 交易参数
     * @return 股份
     */
    function zapAndDeposit(
        IERC20 tokenIn,
        IERC4626 vault,
        address router,
        uint256 amount,
        bytes calldata data
    )
        public
        payable
        onlyAllowedRouter(router)
        onlyAllowedVault(vault)
        whenNotPaused
        returns (uint256)
    {
        // 查询用户金库资金余额
        uint256 initialTokenOutBalance = IERC20(vault.asset()).balanceOf(
            address(this)
        );
        // 兑换
        _zapIn(tokenIn, router, amount, data);
        // 存款，兑换后余额 - 兑换前余额
        uint256 shares = vault.deposit(
            IERC20(vault.asset()).balanceOf(address(this)) -
                initialTokenOutBalance,
            _msgSender()
        );
        // 发送事件
        emit ZapAndDeposit({
            vault: vault,
            router: router,
            tokenIn: tokenIn,
            amount: amount,
            shares: shares
        });
        // 返回
        return shares;
    }

    /**
     * @dev 请求存款
     * @param tokenIn 代币地址
     * @param vault 金库地址
     * @param router 交易地址
     * @param amount 代币金额
     * @param swapData 交易参数
     * @param callback7540Data 要发送给接收者的数据
     */
    function zapAndRequestDeposit(
        IERC20 tokenIn,
        IERC7540 vault,
        address router,
        uint256 amountIn,
        bytes calldata swapData,
        bytes calldata callback7540Data
    )
        public
        payable
        onlyAllowedRouter(router)
        onlyAllowedVault(vault)
        whenNotPaused
    {
        // 查询用户金库资金余额
        uint256 initialTokenOutBalance = IERC20(vault.asset()).balanceOf(
            address(this)
        );
        // 兑换
        _zapIn(tokenIn, router, amountIn, swapData);
        // 请求存款，兑换后余额 - 兑换前余额
        vault.requestDeposit(
            IERC20(vault.asset()).balanceOf(address(this)) -
                initialTokenOutBalance,
            _msgSender(),
            address(this),
            callback7540Data
        );
        // 发送事件
        emit ZapAndRequestDeposit({
            vault: vault,
            router: router,
            tokenIn: tokenIn,
            amount: amountIn
        });
    }

    /**
     * @dev 请求存款
     * @param tokenIn 代币地址
     * @param vault 金库地址
     * @param router 交易地址
     * @param amount 代币金额
     * @param swapData 交易参数
     * @param permitParams 离线许可参数
     * @param callback7540Data 要发送给接收者的数据
     */
    function zapAndRequestDepositWithPermit(
        IERC20 tokenIn,
        IERC7540 vault,
        address router,
        uint256 amount,
        bytes calldata swapData,
        PermitParams calldata permitParams,
        bytes calldata callback7540Data
    ) public {
        // 检查授权
        if (tokenIn.allowance(_msgSender(), address(this)) < amount) {
            // 执行授权
            _execPermit(tokenIn, _msgSender(), address(this), permitParams);
        }
        // 请求存款
        zapAndRequestDeposit(
            tokenIn,
            vault,
            router,
            amount,
            swapData,
            callback7540Data
        );
    }

    /**
     * @dev 兑换代币
     * @param tokenIn 代币地址
     * @param router 交易地址
     * @param amount 代币金额
     * @param data 交易参数
     */
    function _zapIn(
        IERC20 tokenIn,
        address router,
        uint256 amount,
        bytes calldata data
    ) internal {
        // 记录当期余额
        uint256 expectedBalance;
        if (msg.value == 0) {
            expectedBalance = tokenIn.balanceOf(address(this));
            // 转账 和 授权 代币
            _transferTokenInAndApprove(router, tokenIn, amount);
        } else {
            expectedBalance = address(this).balance - msg.value;
        }
        // 执行兑换
        _executeZap(router, data);
        // 交易后余额
        uint256 balanceAfterZap = msg.value == 0
            ? tokenIn.balanceOf(address(this))
            : address(this).balance;
        // 校验是否成功
        if (balanceAfterZap > expectedBalance) {
            // 余额高于预期
            revert InconsistantSwapData({
                expectedTokenInBalance: expectedBalance,
                actualTokenInBalance: balanceAfterZap
            });
        }
    }

    /**
     * @dev 转账 和 授权 代币
     */
    function _transferTokenInAndApprove(
        address router,
        IERC20 tokenIn,
        uint256 amount
    ) internal {
        tokenIn.safeTransferFrom(_msgSender(), address(this), amount);
        if (tokenIn.allowance(address(this), router) < amount) {
            tokenIn.forceApprove(router, amount);
        }
    }

    /**
     * @dev 兑换
     */
    function _executeZap(
        address target,
        bytes memory data
    ) internal returns (bytes memory response) {
        (bool success, bytes memory _data) = target.call{value: msg.value}(
            data
        );
        if (!success) {
            if (data.length > 0) revert SwapFailed(string(_data));
            else revert SwapFailed("Unknown reason");
        }
        return _data;
    }

    /**
     * @dev 执行授权
     * @param token 代币地址
     * @param owner 拥有者
     * @param spender 授权接收地址
     * @param permitParams 离线签名参数
     */
    function _execPermit(
        IERC20 token,
        address owner,
        address spender,
        PermitParams calldata permitParams
    ) internal {
        ERC20Permit(address(token)).permit(
            owner,
            spender,
            permitParams.value,
            permitParams.deadline,
            permitParams.v,
            permitParams.r,
            permitParams.s
        );
        if (token.allowance(owner, spender) != permitParams.value) {
            revert PermitFailed();
        }
    }
}
