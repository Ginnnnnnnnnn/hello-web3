//SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {IERC7540, IERC165, IERC7540Redeem, IERC7540Deposit} from "./interfaces/IERC7540.sol";
import {ERC7540Receiver} from "./interfaces/ERC7540Receiver.sol";
import {IERC20, SafeERC20, Math, PermitParams} from "./SyncVault.sol";

import {SyncVault} from "./SyncVault.sol";

/**
 *         @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
 *         @@@@@@@@@@@@@@@@@@@@%=::::::=%@@@@@@@@@@@@@@@@@@@@
 *         @@@@@@@@@@@@@@@@@@@@*=#=--=*=*@@@@@@@@@@@@@@@@@@@@
 *         @@@@@@@@@@@@@@@@@@@@:*=    =#:@@@@@@@@@@@@@@@@@@@@
 *         @@@@@@@@@@@@@@@@@@@@:@@    @@:@@@@@@@@@@@@@@@@@@@@
 *         @@@@@@@@@@@@@@@@@@@@:@@    @@:@@@@@@@@@@@@@@@@@@@@
 *         @@@@@@@@@@@@@@@@@@@@:@@    @@:@@@@@@@@@@@@@@@@@@@@
 *         @@@@@@@@@@@@@@@@@@@@*-.    .-*@@@@@@@@@@@@@@@@@@@@
 *         @@@@@@@@@@@@@@@@@@@@*        *@@@@@@@@@@@@@@@@@@@@
 *         @@@@@@@@@@@@@@@@@@@.         .@@@@@@@@@@@@@@@@@@@@
 *         @@@@@@@@@@@@@@@@@@@*  Amphor  *@@@@@@@@@@@@@@@@@@@
 *         @@@@@@@@@@@@@@@@@@@*==========#@@@@@@@@@@@@@@@@@@@
 *         @@@@@@@@@@@@@@@@@@@+==========*@@@@@@@@@@@@@@@@@@@
 *         @@@@@@@@@@@@@@@@@@*   Async   *@@@@@@@@@@@@@@@@@@@
 *         @@@@@@@@@@@@@@@@@@@%  Vault  %@@@@@@@@@@@@@@@@@@@@
 *         @@@@@@@@@@@@@@@@@@@@=        +@@@@@@@@@@@@@@@@@@@@
 *         @@@@@@@@@@@@@@@@@@@@%       %@@@@@@@@@@@@@@@@@@@@@
 *         @@@@@@@@@@@@@@@@@@@@@=      =@@@@@@@@@@@@@@@@@@@@@
 *         @@@@@@@@@@@@@@@@@@@@@%     .@@@@@@@@@@@@@@@@@@@@@@
 *         @@@@@@@@@@@@@@@@@@@@@@=    =@@@@@@@@@@@@@@@@@@@@@@
 *         @@@@@@@@@@@@@@@@@@@@@@%----%@@@@@@@@@@@@@@@@@@@@@@
 *         @@@@@@@@@@@@@@@@@@@@%+:::::+%@@@@@@@@@@@@@@@@@@@@@
 *         @@@@@@@@@@@@@@@@@@@@@########@@@@@@@@@@@@@@@@@@@@@
 *         @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
 *
 *            d8888                        888
 *           d88888                        888
 *          d88P888                        888
 *         d88P 888 88888b.d88b.  88888b.  88888b.   .d88b.  888d888
 *        d88P  888 888 "888 "88b 888 "88b 888 "88b d88""88b 888P"
 *       d88P   888 888  888  888 888  888 888  888 888  888 888
 *      d8888888888 888  888  888 888 d88P 888  888 Y88..88P 888
 *     d88P     888 888  888  888 88888P"  888  888  "Y88P"  888.io
 *                                888
 *                                888
 *                                888
 */

// 此常量用于将费用除以 10_000 以获得费用的百分比。
uint256 constant BPS_DIVIDER = 10_000;

using Math for uint256; // only used for `mulDiv` operations.
using SafeERC20 for IERC20; // `safeTransfer` and `safeTransferFrom`

/**
 * @title EpochData
 * @dev 周期信息
 */
struct EpochData {
    uint256 totalSupplySnapshot; // 总股份快照
    uint256 totalAssetsSnapshot; // 总资产快照
    mapping(address => uint256) depositRequestBalance; // 存款请求余额-资产
    mapping(address => uint256) redeemRequestBalance; // 赎回请求余额-股份
}

/**
 * @title SettleValues
 * @dev 结算信息
 */
struct SettleValues {
    uint256 lastSavedBalance; // 最后保存余额（包含费用）
    uint256 fees; // 费用
    uint256 pendingRedeem; // 请求中股份
    uint256 sharesToMint; // 请求中资产所需股份
    uint256 pendingDeposit; // 请求中资产
    uint256 assetsToWithdraw; // 请求总股份所需资产
    uint256 totalAssetsSnapshot; // 总资产（不包含费用）（不包含请求中）
    uint256 totalSupplySnapshot; // 总份额（不包含请求中）
}

/**
 * @title Silo
 * @dev 此合约用于保存请求充值/赎回的用户的资产/股份。
 * 它用于简化保险库的逻辑。
 */
contract Silo {
    constructor(IERC20 underlying) {
        underlying.forceApprove(msg.sender, type(uint256).max);
    }
}

contract AsyncVault is IERC7540, SyncVault {
    // =================== 状态变量 ===================

    // 周期编号
    uint256 public epochId;
    // 费用接收地址
    address public treasury;
    // 存放“请求中”的资产/股份
    Silo public pendingSilo;
    // 存放“可领取”的资产/股份
    Silo public claimableSilo;
    // 周期数据
    mapping(uint256 epochId => EpochData epoch) public epochs;
    // 用户最后一次存款周期
    mapping(address user => uint256 epochId) public lastDepositRequestId;
    // 用户最后一次赎回周期
    mapping(address user => uint256 epochId) public lastRedeemRequestId;

    // =================== 事件 ===================

    /**
     * @notice This event is emitted when a user request a deposit.
     * @param requestId The id of the request.
     * @param owner The address of the user that requested the deposit.
     * @param previousRequestedAssets The amount of assets requested by the user
     * before the new request.
     * @param newRequestedAssets The amount of assets requested by the user.
     */
    event DecreaseDepositRequest(
        uint256 indexed requestId,
        address indexed owner,
        uint256 indexed previousRequestedAssets,
        uint256 newRequestedAssets
    );

    /**
     * @notice This event is emitted when a user request a redeem.
     * @param requestId The id of the request.
     * @param owner The address of the user that requested the redeem.
     * @param previousRequestedShares The amount of shares requested by the user
     * before the new request.
     * @param newRequestedShares The amount of shares requested by the user.
     */
    event DecreaseRedeemRequest(
        uint256 indexed requestId,
        address indexed owner,
        uint256 indexed previousRequestedShares,
        uint256 newRequestedShares
    );

    /**
     * @notice This event is emitted when a user request a redeem.
     * @param requestId The id of the request.
     * @param owner The address of the user that requested the redeem.
     * @param receiver The amount of shares requested by the user
     * before the new request.
     * @param assets The amount of shares requested by the user.
     * @param shares The amount of shares requested by the user.
     */
    event ClaimDeposit(
        uint256 indexed requestId,
        address indexed owner,
        address indexed receiver,
        uint256 assets,
        uint256 shares
    );

    /**
     * @notice This event is emitted when a user request a redeem.
     * @param requestId The id of the request.
     * @param owner The address of the user that requested the redeem.
     * @param receiver The amount of shares requested by the user
     * before the new request.
     * @param assets The amount of shares requested by the user.
     * @param shares The amount of shares requested by the user.
     */
    event ClaimRedeem(
        uint256 indexed requestId,
        address indexed owner,
        address indexed receiver,
        uint256 assets,
        uint256 shares
    );

    // =================== 错误 ===================

    /**
     * @notice This error is emitted when the user request more shares than the
     * maximum allowed.
     * @param receiver The address of the user that requested the redeem.
     * @param shares The amount of shares requested by the user.
     */
    error ExceededMaxRedeemRequest(
        address receiver,
        uint256 shares,
        uint256 maxShares
    );

    /**
     * @notice This error is emitted when the user request more assets than the
     * maximum allowed.
     * @param receiver The address of the user that requested the deposit.
     * @param assets The amount of assets requested by the user.
     * @param maxDeposit The maximum amount of assets the user can request.
     */
    error ExceededMaxDepositRequest(
        address receiver,
        uint256 assets,
        uint256 maxDeposit
    );

    /**
     * @notice This error is emitted when the user try to make a new request
     * with an incorrect data.
     */
    error ReceiverFailed();
    /**
     * @notice This error is emitted when the user try to make a new request
     * on behalf of someone else.
     */
    error ERC7540CantRequestDepositOnBehalfOf();
    /**
     * @notice This error is emitted when the user try to make a request
     * when there is no claimable request available.
     */
    error NoClaimAvailable(address owner);
    /**
     * @notice This error is emitted when the user try to make a request
     * when the vault is open.
     */
    error InvalidTreasury();

    // =================== 初始化 ===================

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() SyncVault() {
        _disableInitializers();
    }

    function initialize(
        uint16 fees,
        address owner,
        address _treasury,
        IERC20 underlying,
        uint256 bootstrapAmount,
        string memory name,
        string memory symbol
    ) public initializer {
        // 初始化SyncVault
        super.initialize(
            fees,
            owner,
            underlying,
            bootstrapAmount,
            name,
            symbol
        );
        // 初始化周期ID
        epochId = 1;
        setTreasury(_treasury);
        // 部署请求中仓库
        pendingSilo = new Silo(underlying);
        // 部署可领取仓库
        claimableSilo = new Silo(underlying);
    }

    // =================== 合约设置 ===================

    /**
     * @dev 设置费用接收地址
     * @param _treasury 接收地址
     */
    function setTreasury(address _treasury) public onlyOwner {
        if (_treasury == address(0)) revert InvalidTreasury();
        treasury = _treasury;
    }

    /**
     * @dev 关闭vault
     * @notice 只能由合同的所有者调用
     */
    function close() external override onlyOwner {
        // 校验合约是否已经关闭
        if (!vaultIsOpen) revert VaultIsClosed();
        // 校验合约资产是否为0
        if (totalAssets() == 0) revert VaultIsEmpty();
        // 合约总资产
        lastSavedBalance = totalAssets();
        // 设置金库状态
        vaultIsOpen = false;
        // 转账资产到owner
        _asset.safeTransfer(owner(), lastSavedBalance);
        // 发送事件
        emit EpochStart(block.timestamp, lastSavedBalance, totalSupply());
    }

    /**
     * @dev 打开vault
     * @notice 只能由合同的所有者调用，如果有盈利，则收取履约费并发送给合约所有者。
     * @param assetReturned 待存入金库的标的资产金额
     */
    function open(
        uint256 assetReturned
    ) external override onlyOwner whenNotPaused whenClosed {
        // 结算
        (uint256 newBalance, ) = _settle(assetReturned);
        // 设置金库状态
        vaultIsOpen = true;
        // 转账资产到合约
        _asset.safeTransferFrom(owner(), address(this), newBalance);
    }

    // =================== 功能方法 ===================

    /**
     * @dev 请求存款-离线许可授权
     * @notice 当金库关闭时，用户只能请求存款。这样，资金将被发送并等待在 pendingSilo 中。
     * 当所有者调用 `open` 或 `settle` 函数时，资金将被存入，铸造的份额将被发送到 claimableSilo。
     * 等待用户领取。
     * @param assets 资产数量
     * @param receiver 接收者地址
     * @param data 要发送给接收者的数据
     * @param permitParams 离线许可参数
     */
    function requestDepositWithPermit(
        uint256 assets,
        address receiver,
        bytes memory data,
        PermitParams calldata permitParams
    ) public {
        address _msgSender = _msgSender();
        // 检查授权余额
        if (_asset.allowance(_msgSender, address(this)) < assets) {
            // 余额不够，执行授权
            execPermit(_msgSender, address(this), permitParams);
        }
        // 请求存款
        return requestDeposit(assets, receiver, _msgSender, data);
    }

    /**
     * @dev 请求存款
     * @notice 当金库关闭时，用户只能请求存款。这样，资金将被发送并等待在 pendingSilo 中。
     * 当所有者调用 `open` 或 `settle` 函数时，资金将被存入，铸造的份额将被发送到 claimableSilo。
     * 等待用户领取。
     * @param assets 资产数量
     * @param receiver 接收者地址
     * @param owner 资产拥有者地址
     * @param data 要发送给接收者的数据
     */
    function requestDeposit(
        uint256 assets,
        address receiver,
        address owner,
        bytes memory data
    ) public whenNotPaused whenClosed {
        // 校验发起者是否为资金拥有者
        if (_msgSender() != owner) {
            revert ERC7540CantRequestDepositOnBehalfOf();
        }
        // 预计算股份
        if (previewClaimDeposit(receiver) > 0) {
            // 认领历史股份
            _claimDeposit(receiver, receiver);
        }
        // 校验最大请求存款
        if (assets > maxDepositRequest(owner)) {
            revert ExceededMaxDepositRequest(
                receiver,
                assets,
                maxDepositRequest(owner)
            );
        }
        // 转账资产到请求中资产仓
        _asset.safeTransferFrom(owner, address(pendingSilo), assets);
        // 创建存款请求
        _createDepositRequest(assets, receiver, owner, data);
    }

    /**
     * @dev 请求存款-减少
     * @param assets 资产
     */
    function decreaseDepositRequest(
        uint256 assets
    ) external whenClosed whenNotPaused {
        address owner = _msgSender();
        // 更新存款信息
        uint256 oldBalance = epochs[epochId].depositRequestBalance[owner];
        epochs[epochId].depositRequestBalance[owner] -= assets;
        // 转账资产
        _asset.safeTransferFrom(address(pendingSilo), owner, assets);
        // 发送事件
        emit DecreaseDepositRequest(
            epochId,
            owner,
            oldBalance,
            epochs[epochId].depositRequestBalance[owner]
        );
    }

    /**
     * @dev 请求赎回
     * @notice 当金库关闭时，用户只能请求赎回。这样，股份将被发送并等待在 pendingSilo 中。
     * 当所有者调用 `open` 或 `settle` 函数时，股份将被赎回，资产将被发送到 claimableSilo。
     * 等待用户领取。
     * @param shares 股份
     * @param receiver 接收者地址
     * @param owner 股份拥有者
     * @param data 要发送给接收者的数据
     */
    function requestRedeem(
        uint256 shares,
        address receiver,
        address owner,
        bytes memory data
    ) public whenNotPaused whenClosed {
        // 如果发起者不是股份拥有者，需要授权
        if (_msgSender() != owner) {
            _spendAllowance(owner, _msgSender(), shares);
        }
        // 预计算资金
        if (previewClaimRedeem(receiver) > 0) {
            // 认领历史股份
            _claimRedeem(receiver, receiver);
        }
        // 校验最大请求赎回
        if (shares > maxRedeemRequest(owner)) {
            revert ExceededMaxRedeemRequest(
                receiver,
                shares,
                maxRedeemRequest(owner)
            );
        }
        // 转账股份
        _update(owner, address(pendingSilo), shares);
        // 创建赎回请求
        _createRedeemRequest(shares, receiver, owner, data);
    }

    /**
     * @dev 请求赎回-减少
     * @param shares 股份
     */
    function decreaseRedeemRequest(
        uint256 shares
    ) external whenClosed whenNotPaused {
        address owner = _msgSender();
        // 更新股份信息
        uint256 oldBalance = epochs[epochId].redeemRequestBalance[owner];
        epochs[epochId].redeemRequestBalance[owner] -= shares;
        // 转账股份
        _update(address(pendingSilo), owner, shares);
        // 发送事件
        emit DecreaseRedeemRequest(
            epochId,
            owner,
            oldBalance,
            epochs[epochId].redeemRequestBalance[owner]
        );
    }

    /**
     * @dev 结算
     * @notice 由合约所有者，如果有盈利，则收取绩效费并发送给合约所有者。
     * 由于 amphor 策略可能具有时间敏感性，因此我们必须能够在切换 epoch 时无需将所有资金存回。
     * 使用 _settle，我们可以虚拟地存回资金，检查我们欠想要赎回的用户的金额，并可能从存款请求中提取额外的资金。
     * @param newSavedBalance 待存入金库的资产
     */
    function settle(
        uint256 newSavedBalance
    ) external onlyOwner whenNotPaused whenClosed {
        // 结算
        (uint256 _lastSavedBalance, uint256 totalSupply) = _settle(
            newSavedBalance
        );
        emit EpochStart(block.timestamp, _lastSavedBalance, totalSupply);
    }

    /**
     * @dev 获取用户赎回请求余额-当期
     * @notice 用户通过 `claimRedeem` 函数存入
     * @param owner 用户地址
     */
    function pendingRedeemRequest(
        address owner
    ) external view returns (uint256) {
        return epochs[epochId].redeemRequestBalance[owner];
    }

    /**
     * @dev 获取用户赎回请求余额-往期
     * @notice 用户通过 `claimRedeem` 函数存入
     * @param owner 用户地址
     */
    function claimableRedeemRequest(
        address owner
    ) external view returns (uint256) {
        uint256 lastRequestId = lastRedeemRequestId[owner];
        return
            isCurrentEpoch(lastRequestId)
                ? 0
                : epochs[lastRequestId].redeemRequestBalance[owner];
    }

    /**
     * @dev 获取用户存款请求余额-当期
     * @notice 用户通过 `claimDeposit` 函数存入
     * @param owner 用户地址
     */
    function pendingDepositRequest(
        address owner
    ) external view returns (uint256 assets) {
        return epochs[epochId].depositRequestBalance[owner];
    }

    /**
     * @dev 获取用户存款请求余额-往期
     * @notice 用户通过 `claimDeposit` 函数存入
     * @param owner 用户地址
     */
    function claimableDepositRequest(
        address owner
    ) external view returns (uint256 assets) {
        uint256 lastRequestId = lastDepositRequestId[owner];
        return
            isCurrentEpoch(lastRequestId)
                ? 0
                : epochs[lastRequestId].depositRequestBalance[owner];
    }

    /**
     * @dev 总待结算资产
     */
    function totalPendingDeposits() external view returns (uint256) {
        return vaultIsOpen ? 0 : _asset.balanceOf(address(pendingSilo));
    }

    /**
     * @dev 总待结算股份
     */
    function totalPendingRedeems() external view returns (uint256) {
        return vaultIsOpen ? 0 : balanceOf(address(pendingSilo));
    }

    /**
     * @dev 总待领取资产
     */
    function totalClaimableAssets() external view returns (uint256) {
        return _asset.balanceOf(address(claimableSilo));
    }

    /**
     * @dev 总待领取股份
     */
    function totalClaimableShares() external view returns (uint256) {
        return balanceOf(address(claimableSilo));
    }

    /**
     * @dev This function let users claim the shares we owe them after we
     * processed their deposit request, in the _settle function.
     * @param receiver The address of the user that requested the deposit.
     */
    function claimDeposit(
        address receiver
    ) public whenNotPaused returns (uint256 shares) {
        return _claimDeposit(_msgSender(), receiver);
    }

    /**
     * @dev This function let users claim the assets we owe them after we
     * processed their redeem request, in the _settle function.
     * @param receiver The address of the user that requested the redeem.
     */
    function claimRedeem(
        address receiver
    ) public whenNotPaused returns (uint256 assets) {
        return _claimRedeem(_msgSender(), receiver);
    }

    /**
     * @dev 最大请求存款
     * @notice 如果保险库被锁定或暂停，则为0。
     * @return 最大请求存款
     */
    function maxDepositRequest(address) public view returns (uint256) {
        return vaultIsOpen || paused() ? 0 : type(uint256).max;
    }

    /**
     * @dev 最大请求赎回
     * @notice 如果保险库被锁定或暂停，则为0。
     * @return 最大请求存款
     */
    function maxRedeemRequest(address owner) public view returns (uint256) {
        return vaultIsOpen || paused() ? 0 : balanceOf(owner);
    }

    /**
     * @dev 预计算股份-存款
     * @param owner 用户地址
     * @return 股份
     */
    function previewClaimDeposit(address owner) public view returns (uint256) {
        uint256 lastRequestId = lastDepositRequestId[owner];
        uint256 assets = epochs[lastRequestId].depositRequestBalance[owner];
        return _convertToShares(assets, lastRequestId, Math.Rounding.Floor);
    }

    /**
     * @dev 预计算资金-赎回
     * @param owner 用户地址
     * @return 资金
     */
    function previewClaimRedeem(address owner) public view returns (uint256) {
        uint256 lastRequestId = lastRedeemRequestId[owner];
        uint256 shares = epochs[lastRequestId].redeemRequestBalance[owner];
        return _convertToAssets(shares, lastRequestId, Math.Rounding.Floor);
    }

    /**
     * @dev This function convertToShares is used to convert the assets into
     * shares.
     * @param assets The amount of assets to convert.
     * @param _epochId The epoch id.
     * @return The amount of shares.
     */
    function convertToShares(
        uint256 assets,
        uint256 _epochId
    ) public view returns (uint256) {
        return _convertToShares(assets, _epochId, Math.Rounding.Floor);
    }

    /**
     * @dev This function convertToAssets is used to convert the shares into
     * assets.
     * @param shares The amount of shares to convert.
     * @param _epochId The epoch id.
     * @return The amount of assets.
     */
    function convertToAssets(
        uint256 shares,
        uint256 _epochId
    ) public view returns (uint256) {
        return _convertToAssets(shares, _epochId, Math.Rounding.Floor);
    }

    /**
     * Utils function to convert the shares claimable into assets. It can
     * be used in the front end to save an rpc call.
     */
    /**
     * @dev This function claimableDepositBalanceInAsset is used to know if the
     * owner will have to send money to the claimableSilo (for users who want to
     * leave the vault) or if he will receive money from it.
     * @notice Using this the owner can know if he will have to send money to
     * the
     * claimableSilo (for users who want to leave the vault) or if he will
     * receive money from it.
     * @param owner The address of the user that requested the deposit.
     * @return The amount of assets the user will get if they claim their
     * deposit request.
     */
    function claimableDepositBalanceInAsset(
        address owner
    ) public view returns (uint256) {
        uint256 shares = previewClaimDeposit(owner);
        return convertToAssets(shares);
    }

    /**
     * @dev 预结算
     * @param newSavedBalance 待存入金库的资产
     * @return assetsToOwner The amount of assets the user will get if they claim their redeem request.
     * @return assetsToVault The amount of assets the user will get if they claim their redeem request.
     * @return expectedAssetFromOwner The amount of assets that will be taken from the owner.
     * @return settleValues 结算信息
     */
    function previewSettle(
        uint256 newSavedBalance
    )
        public
        view
        returns (
            uint256 assetsToOwner,
            uint256 assetsToVault,
            uint256 expectedAssetFromOwner,
            SettleValues memory settleValues
        )
    {
        // 上次保存资产余额
        uint256 _lastSavedBalance = lastSavedBalance;
        // 检查最大回撤
        _checkMaxDrawdown(_lastSavedBalance, newSavedBalance);
        // 计算费用
        uint256 fees = _computeFees(_lastSavedBalance, newSavedBalance);
        // 总股份
        uint256 totalSupply = totalSupply();
        // 待存入金库的资产 - 费用
        _lastSavedBalance = newSavedBalance - fees;

        // 请求中仓库
        address pendingSiloAddr = address(pendingSilo);
        // 请求中股份
        uint256 pendingRedeem = balanceOf(pendingSiloAddr);
        // 请求中资产
        uint256 pendingDeposit = _asset.balanceOf(pendingSiloAddr);

        // 计算请求中资产所需股份：请求中资产 * 总股份 / 总资产
        uint256 sharesToMint = pendingDeposit.mulDiv(
            totalSupply + 1,
            _lastSavedBalance + 1,
            Math.Rounding.Floor
        );

        // 计算请求总股份所需资产：请求中股份 * （ 总资产 + 请求中资产 ） / （ 总股份 + 请求中资产所需股份 ）
        uint256 assetsToWithdraw = pendingRedeem.mulDiv(
            _lastSavedBalance + pendingDeposit + 1,
            totalSupply + sharesToMint + 1,
            Math.Rounding.Floor
        );

        // 总资产
        uint256 totalAssetsSnapshot = _lastSavedBalance;
        // 总份额
        uint256 totalSupplySnapshot = totalSupply;
        // 构建结算信息
        settleValues = SettleValues({
            lastSavedBalance: _lastSavedBalance + fees,
            fees: fees,
            pendingRedeem: pendingRedeem,
            sharesToMint: sharesToMint,
            pendingDeposit: pendingDeposit,
            assetsToWithdraw: assetsToWithdraw,
            totalAssetsSnapshot: totalAssetsSnapshot,
            totalSupplySnapshot: totalSupplySnapshot
        });

        // 判断需要多少 资产 和 股份
        if (pendingDeposit > assetsToWithdraw) {
            // 请求中资产 > 请求总股份所需资产，需补：请求中资产 - 请求总股份所需资产
            assetsToOwner = pendingDeposit - assetsToWithdraw;
        } else if (pendingDeposit < assetsToWithdraw) {
            // 请求中资产 < 请求总股份所需资产，多出：请求总股份所需资产 - 请求中资产
            assetsToVault = assetsToWithdraw - pendingDeposit;
        }
        // 费用 + 多出
        expectedAssetFromOwner = fees + assetsToVault;
    }

    /**
     * @dev see EIP
     * @param interfaceId The interface id to check for.
     * @return True if the contract implements the interface.
     */
    function supportsInterface(bytes4 interfaceId) public pure returns (bool) {
        return
            interfaceId == type(IERC165).interfaceId ||
            interfaceId == type(IERC7540Redeem).interfaceId ||
            interfaceId == type(IERC7540Deposit).interfaceId;
    }

    /**
     * @dev 创建存款请求
     * @param assets 资产数量
     * @param receiver 接收者
     * @param owner 拥有者
     * @param data 要发送给接收者的数据
     */
    function _createDepositRequest(
        uint256 assets,
        address receiver,
        address owner,
        bytes memory data
    ) internal {
        // 更新用户请求存款信息
        epochs[epochId].depositRequestBalance[receiver] += assets;
        // 更新用户最后存款周期ID
        if (lastDepositRequestId[receiver] != epochId) {
            lastDepositRequestId[receiver] = epochId;
        }
        // 回调校验
        if (
            data.length > 0 &&
            ERC7540Receiver(receiver).onERC7540DepositReceived(
                _msgSender(),
                owner,
                epochId,
                assets,
                data
            ) !=
            ERC7540Receiver.onERC7540DepositReceived.selector
        ) revert ReceiverFailed();
        // 发送事件
        emit DepositRequest(receiver, owner, epochId, _msgSender(), assets);
    }

    /**
     * @dev 创建赎回请求
     * @param shares 股份数量
     * @param receiver 接收者
     * @param owner 拥有者
     * @param data 要发送给接收者的数据
     */
    function _createRedeemRequest(
        uint256 shares,
        address receiver,
        address owner,
        bytes memory data
    ) internal {
        // 更新用户请求赎回信息
        epochs[epochId].redeemRequestBalance[receiver] += shares;
        // 更新用户最后赎回周期ID
        if (lastRedeemRequestId[receiver] != epochId) {
            lastRedeemRequestId[receiver] = epochId;
        }
        // 回调校验
        if (
            data.length > 0 &&
            ERC7540Receiver(receiver).onERC7540RedeemReceived(
                _msgSender(),
                owner,
                epochId,
                shares,
                data
            ) !=
            ERC7540Receiver.onERC7540RedeemReceived.selector
        ) revert ReceiverFailed();
        // 发送事件
        emit RedeemRequest(receiver, owner, epochId, _msgSender(), shares);
    }

    /**
     * @dev 认领存款股份
     * @param owner 拥有者
     * @param receiver 接收者
     * @return shares 股份
     */
    function _claimDeposit(
        address owner,
        address receiver
    ) internal returns (uint256 shares) {
        // 判断是否是当期，当期报错
        uint256 lastRequestId = lastDepositRequestId[owner];
        if (lastRequestId == epochId) revert NoClaimAvailable(owner);
        // 预计算股份
        shares = previewClaimDeposit(owner);
        // 更新请求存款
        epochs[lastRequestId].depositRequestBalance[owner] = 0;
        // 转账股份
        _update(address(claimableSilo), receiver, shares);
        // 发送事件
        uint256 assets = epochs[lastRequestId].depositRequestBalance[owner];
        emit ClaimDeposit(lastRequestId, owner, receiver, assets, shares);
    }

    /**
     * @dev 认领赎回资产
     * @param owner 拥有者
     * @param receiver 接收者
     * @return assets 资产
     */
    function _claimRedeem(
        address owner,
        address receiver
    ) internal whenNotPaused returns (uint256 assets) {
        // 判断是否是当期，当期报错
        uint256 lastRequestId = lastRedeemRequestId[owner];
        if (lastRequestId == epochId) revert NoClaimAvailable(owner);
        // 预计算资产
        assets = previewClaimRedeem(owner);
        // 更新请求股份
        epochs[lastRequestId].redeemRequestBalance[owner] = 0;
        // 转账资金
        _asset.safeTransferFrom(address(claimableSilo), receiver, assets);
        // 发送事件
        uint256 shares = epochs[lastRequestId].redeemRequestBalance[owner];
        emit ClaimRedeem(lastRequestId, owner, receiver, assets, shares);
    }

    /**
     * @dev 结算
     * @param newSavedBalance 待存入金库的资产
     * @return lastSavedBalance
     * @return totalSupply
     */
    function _settle(
        uint256 newSavedBalance
    ) internal returns (uint256, uint256) {
        // 预计算
        (
            uint256 assetsToOwner,
            uint256 assetsToVault,
            ,
            SettleValues memory settleValues
        ) = previewSettle(newSavedBalance);
        // 发送事件
        emit EpochEnd(
            block.timestamp,
            lastSavedBalance,
            newSavedBalance,
            settleValues.fees,
            totalSupply()
        );

        // 转账费用
        _asset.safeTransferFrom(owner(), treasury, settleValues.fees);

        // ===== 结算股份 =====

        // 销毁周期请求中股份
        _burn(address(pendingSilo), settleValues.pendingRedeem);
        // 铸造周期请求中资产所需股份
        _mint(address(claimableSilo), settleValues.sharesToMint);

        // ===== 结算资产 =====

        //
        if (settleValues.pendingDeposit > settleValues.assetsToWithdraw) {
            _asset.safeTransferFrom(
                address(pendingSilo),
                owner(),
                assetsToOwner
            );
            if (settleValues.assetsToWithdraw > 0) {
                _asset.safeTransferFrom(
                    address(pendingSilo),
                    address(claimableSilo),
                    settleValues.assetsToWithdraw
                );
            }
        } else if (
            settleValues.pendingDeposit < settleValues.assetsToWithdraw
        ) {
            _asset.safeTransferFrom(
                owner(),
                address(claimableSilo),
                assetsToVault
            );
            if (settleValues.pendingDeposit > 0) {
                _asset.safeTransferFrom(
                    address(pendingSilo),
                    address(claimableSilo),
                    settleValues.pendingDeposit
                );
            }
        } else if (settleValues.pendingDeposit > 0) {
            // if _pendingDeposit == assetsToWithdraw AND _pendingDeposit > 0
            // (and assetsToWithdraw > 0)
            _asset.safeTransferFrom(
                address(pendingSilo),
                address(claimableSilo),
                settleValues.assetsToWithdraw
            );
        }

        emit Deposit(
            address(pendingSilo),
            address(claimableSilo),
            settleValues.pendingDeposit,
            settleValues.sharesToMint
        );

        emit Withdraw(
            address(pendingSilo),
            address(claimableSilo),
            address(pendingSilo),
            settleValues.assetsToWithdraw,
            settleValues.pendingRedeem
        );

        settleValues.lastSavedBalance =
            settleValues.lastSavedBalance -
            settleValues.fees +
            settleValues.pendingDeposit -
            settleValues.assetsToWithdraw;
        lastSavedBalance = settleValues.lastSavedBalance;

        epochs[epochId].totalSupplySnapshot = settleValues.totalSupplySnapshot;
        epochs[epochId].totalAssetsSnapshot = settleValues.totalAssetsSnapshot;

        epochId++;

        return (settleValues.lastSavedBalance, totalSupply());
    }

    /**
     * @dev 是否是当期
     */
    function isCurrentEpoch(uint256 requestId) internal view returns (bool) {
        return requestId == epochId;
    }

    /**
     * @dev 预计算股份
     * @param assets 资金
     * @param requestId 周期ID
     * @param rounding 取舍方式
     */
    function _convertToShares(
        uint256 assets,
        uint256 requestId,
        Math.Rounding rounding
    ) internal view returns (uint256) {
        // 校验是否是当期，当期返回0
        if (isCurrentEpoch(requestId)) return 0;
        // 总资产
        uint256 totalAssets = epochs[requestId].totalAssetsSnapshot + 1;
        // 总股份
        uint256 totalSupply = epochs[requestId].totalSupplySnapshot + 1;
        // 计算股份
        return assets.mulDiv(totalSupply, totalAssets, rounding);
    }

    /**
     * @dev 预计算资金
     * @param shares 股份
     * @param requestId 周期ID
     * @param rounding 取舍方式
     */
    function _convertToAssets(
        uint256 shares,
        uint256 requestId,
        Math.Rounding rounding
    ) internal view returns (uint256) {
        // 校验是否是当期，当期返回0
        if (isCurrentEpoch(requestId)) return 0;
        // 总股份
        uint256 totalSupply = epochs[requestId].totalSupplySnapshot + 1;
        // 总资产
        uint256 totalAssets = epochs[requestId].totalAssetsSnapshot + 1;
        // 计算资产
        return shares.mulDiv(totalAssets, totalSupply, rounding);
    }

    /**
     * @dev 检查最大回撤
     * @param _lastSavedBalance 最后保存余额
     * @param newSavedBalance 最新保存余额
     */
    function _checkMaxDrawdown(
        uint256 _lastSavedBalance,
        uint256 newSavedBalance
    ) internal view {
        // 最新保存余额 < 计算回撤金额：最后保存余额 * （ 100% - 最大回撤阈值 ）
        if (
            newSavedBalance <
            _lastSavedBalance.mulDiv(
                BPS_DIVIDER - _maxDrawdown,
                BPS_DIVIDER,
                Math.Rounding.Ceil
            )
        ) revert MaxDrawdownReached();
    }

    /**
     * @dev 计算费用
     * @param _lastSavedBalance 最后保存余额
     * @param newSavedBalance 最新保存余额
     */
    function _computeFees(
        uint256 _lastSavedBalance,
        uint256 newSavedBalance
    ) internal view returns (uint256 fees) {
        if (newSavedBalance > _lastSavedBalance && feesInBps > 0) {
            // 计算剩余金额
            uint256 profits;
            unchecked {
                profits = newSavedBalance - _lastSavedBalance;
            }
            // 计算费用：剩余金额 * 费率
            fees = (profits).mulDiv(
                feesInBps,
                BPS_DIVIDER,
                Math.Rounding.Floor
            );
        }
    }
}
